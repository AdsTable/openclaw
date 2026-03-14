# Safe upstream merge script for AdsTable/openclaw fork.
# Run from repo root: pwsh dev.docs/scripts/merge-upstream.ps1 [-DryRun]
#
# SAFETY MODEL (10 steps):
#   1. Verify clean working tree
#   2. Verify remotes origin + upstream exist
#   3. Fetch upstream (required before patch generation)
#   4. Save patches BOM-free UTF-8 LF (git am compatible) BEFORE any merge
#   5. Create permanent backup tag in origin (survives branch deletion)
#   6. Checkout main, pull ff-only, create TEMP merge branch
#   7. Show upstream changelog + auto-detect $CustomFiles drift (FAIL if unprotected files found)
#   8. Merge upstream/main into temp branch; auto-restore $CustomFiles on conflict
#   9. Post-merge verification + npm ci + build + typecheck (TS errors ABORT)
#  10. Push merge branch; user manually fast-forwards main after review
#
# Recovery: git am dev.docs/patches/customizations-DATE.fmtpatch
#           OR: git apply --3way dev.docs/patches/customizations-DATE.diff

param([switch]$DryRun)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location $RepoRoot

# ── ALL files we customized vs upstream ─────────────────────────────────────
# Source of truth: git diff --name-only upstream/main HEAD
# Verified: 2026-03-14 (39 files diff total; dev.docs/* and docs/zh-CN/* filtered below)
# RULE: add ONLY files present in `git diff upstream/main HEAD` AND documented in
#       dev.docs/CUSTOMIZATIONS.md. Never add files just because they are open in IDE.
$CustomFiles = @(
  # Gateway
  "src/gateway/server-methods-list.ts",
  "src/gateway/server-methods/agents.ts",
  "src/gateway/control-ui.ts",
  # UI layer
  "ui/src/ui/app-render.ts",
  "ui/src/ui/app-settings.ts",
  "ui/src/ui/app-view-state.ts",
  "ui/src/ui/app.ts",
  "ui/src/ui/views/agents-utils.ts",
  "ui/src/ui/views/agents.ts",
  "ui/src/ui/views/sessions.ts",
  "ui/src/ui/components/modal.ts",
  "ui/src/ui/markdown.ts",
  # Styles — both exist in upstream (verified: git ls-tree upstream/main)
  "ui/src/styles/components.css",
  "ui/src/styles/base.css",
  # Storage utility — exists in upstream (verified: git ls-tree upstream/main)
  "ui/src/ui/storage.ts",
  # Repo infrastructure
  "CUSTOMIZATIONS.md",
  "scripts/merge-upstream.ps1",
  ".gitignore",
  ".gitleaks.toml",
  ".githooks/post-merge",
  ".githooks/pre-push",
  # zh-CN templates translated to English (all 13 files)
  "docs/zh-CN/reference/templates/AGENTS.dev.md",
  "docs/zh-CN/reference/templates/AGENTS.md",
  "docs/zh-CN/reference/templates/BOOT.md",
  "docs/zh-CN/reference/templates/BOOTSTRAP.md",
  "docs/zh-CN/reference/templates/HEARTBEAT.md",
  "docs/zh-CN/reference/templates/IDENTITY.dev.md",
  "docs/zh-CN/reference/templates/IDENTITY.md",
  "docs/zh-CN/reference/templates/SOUL.dev.md",
  "docs/zh-CN/reference/templates/SOUL.md",
  "docs/zh-CN/reference/templates/TOOLS.dev.md",
  "docs/zh-CN/reference/templates/TOOLS.md",
  "docs/zh-CN/reference/templates/USER.dev.md",
  "docs/zh-CN/reference/templates/USER.md"
)

# ── Helpers ──────────────────────────────────────────────────────────────────
function Write-BomFreeUtf8 {
  param([string]$Path, [string[]]$Lines)
  # PS 5.1 Out-File -Encoding UTF8 adds BOM → breaks git am. Use WriteAllText with LF.
  $enc = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($Path, ($Lines -join "`n") + "`n", $enc)
}

function Test-CustomFilesPresent {
  param([string[]]$Files)
  $missing = $Files | Where-Object { -not (Test-Path $_) }
  if ($missing) {
    Write-Host "WARN: custom files missing after merge:" -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "  MISSING: $_" -ForegroundColor Red }
    return $false
  }
  Write-Host "Verification OK — all $($Files.Count) custom files present." -ForegroundColor Green
  return $true
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " OpenClaw Upstream Merge (AdsTable fork)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Step 1: Verify clean working tree
$gitStatus = git status --porcelain 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: git status failed." -ForegroundColor Red; exit 1 }
if ($gitStatus) {
  Write-Host "ERROR: Uncommitted changes detected. Commit or stash first." -ForegroundColor Red
  git status --short
  exit 1
}

# Step 2: Verify remotes exist
$hasOrigin   = git remote get-url origin   2>&1; if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: remote 'origin' not found."   -ForegroundColor Red; exit 1 }
$hasUpstream = git remote get-url upstream 2>&1; if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: remote 'upstream' not found." -ForegroundColor Red; exit 1 }
Write-Host "Remotes OK: origin=$hasOrigin" -ForegroundColor Green

# Step 3: Fetch upstream FIRST — upstream/main must exist locally before git format-patch
Write-Host "Fetching upstream (required before patch generation)..." -ForegroundColor Cyan
git fetch upstream
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: git fetch upstream failed." -ForegroundColor Red; exit 1 }
$upstreamRef = git rev-parse upstream/main 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: upstream/main not found after fetch." -ForegroundColor Red; exit 1 }
Write-Host "  upstream/main = $upstreamRef" -ForegroundColor Green

# Step 4: Save patches BEFORE merge (BOM-free, LF endings for git am)
$date     = Get-Date -Format "yyyyMMdd-HHmmss"
$patchDir = "dev.docs/patches"
New-Item -ItemType Directory -Path $patchDir -Force | Out-Null

$fmtPatch  = "$patchDir/customizations-$date.fmtpatch"
$diffPatch = "$patchDir/customizations-$date.diff"

Write-Host "Saving patches (UTF-8 no-BOM, LF)..." -ForegroundColor Cyan
Write-BomFreeUtf8 -Path $fmtPatch  -Lines (git format-patch upstream/main --stdout)
Write-BomFreeUtf8 -Path $diffPatch -Lines (git diff upstream/main origin/main -- @($CustomFiles))
$fmtSize  = [math]::Round((Get-Item $fmtPatch).Length/1KB,1)
$diffSize = [math]::Round((Get-Item $diffPatch).Length/1KB,1)
if ($fmtSize -eq 0) { Write-Host "WARN: format-patch is 0 KB — no commits ahead of upstream?" -ForegroundColor Yellow }
Write-Host "  format-patch : $fmtPatch  ($fmtSize KB)" -ForegroundColor Green
Write-Host "  diff patch   : $diffPatch ($diffSize KB)" -ForegroundColor Green

if ($DryRun) {
  Write-Host "`nDRY RUN complete." -ForegroundColor Yellow
  Write-Host "  Side effects: upstream fetched, patch files created (no git history changed)." -ForegroundColor DarkGray
  Write-Host "  Patch files are untracked — commit or delete manually:" -ForegroundColor DarkGray
  Write-Host "    git add dev.docs/patches/ && git commit -m 'chore: save patches $date'" -ForegroundColor DarkGray
  Write-Host "  Reapply after merge: git am $fmtPatch" -ForegroundColor Yellow
  Write-Host "  OR (partial):        git apply --3way $diffPatch" -ForegroundColor Yellow
  exit 0
}

# Step 5: Permanent backup tag (survives branch deletion)
$backupTag = "backup/pre-upstream-$date"
git tag $backupTag
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: git tag '$backupTag' failed (already exists?)." -ForegroundColor Red; exit 1 }
git push origin $backupTag
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: git push tag '$backupTag' failed (no connectivity?)." -ForegroundColor Red; git tag -d $backupTag; exit 1 }
Write-Host "Backup tag pushed : $backupTag" -ForegroundColor Green

# Step 6: Ensure we are on main, then create TEMP merge branch
git checkout main
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: cannot checkout main." -ForegroundColor Red; exit 1 }
git pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: cannot fast-forward main from origin (diverged or unreachable). Resolve manually." -ForegroundColor Red; exit 1 }

$mergeBranch = "merge/upstream-$date"
$branchExists = git branch --list $mergeBranch
if ($branchExists) { Write-Host "ERROR: branch '$mergeBranch' already exists. Delete it first." -ForegroundColor Red; exit 1 }

git checkout -b $mergeBranch
Write-Host "Working branch    : $mergeBranch" -ForegroundColor Cyan

# Show what upstream is bringing (changelog)
$newCommits = @(git log HEAD..upstream/main --oneline --no-merges)
Write-Host "`nUpstream brings $($newCommits.Count) new commit(s):" -ForegroundColor Cyan
$showCount = [Math]::Min(20, $newCommits.Count)
$newCommits | Select-Object -First $showCount | ForEach-Object { Write-Host "  $_" }
if ($newCommits.Count -gt $showCount) { Write-Host "  ... and $($newCommits.Count - $showCount) more (see git log HEAD..upstream/main)" -ForegroundColor DarkGray }

# Auto-detect customized files — FAIL if $CustomFiles is out of sync (path-sep normalized)
# --diff-filter=M: only MODIFIED files (exist in both fork+upstream, we changed them).
# Added (A) and Deleted (D) files are NOT conflict risks during this merge.
$detectedFiles = @(
  git diff upstream/main HEAD --name-only --diff-filter=M |
  Where-Object { $_ -and -not ($_ -match '^dev[/\\]docs') -and -not ($_ -match '^docs[/\\]zh') } |
  ForEach-Object { $_.Replace('\', '/') }   # normalize Windows backslashes
)
$untracked = $detectedFiles | Where-Object { $CustomFiles -notcontains $_ }
if ($untracked) {
  Write-Host "`nERROR: files modified vs upstream but NOT in CustomFiles:" -ForegroundColor Red
  Write-Host "  These WILL BE OVERWRITTEN if merge conflicts occur." -ForegroundColor Red
  $untracked | ForEach-Object { Write-Host "  MISSING: $_  ← add to CustomFiles + dev.docs/CUSTOMIZATIONS.md" -ForegroundColor Red }
  Write-Host "`nABORTING. Fix CustomFiles list, then re-run." -ForegroundColor Red
  git checkout main
  git branch -D $mergeBranch
  exit 1
} else {
  Write-Host "CustomFiles sync OK — all $($detectedFiles.Count) detected changes are protected." -ForegroundColor Green
}

# Step 7: Merge upstream into temp branch (already fetched in Step 3)
Write-Host "`nMerging upstream/main into $mergeBranch..." -ForegroundColor Cyan
git merge upstream/main --no-ff -m "chore: merge upstream/main $date"
$mergeExitCode = $LASTEXITCODE

if ($mergeExitCode -ne 0) {
  $conflicts = git diff --name-only --diff-filter=U
  Write-Host "`nCONFLICTS in:" -ForegroundColor Yellow
  $conflicts | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }

  Write-Host "`nAuto-restoring custom files from origin/main..." -ForegroundColor Cyan
  $restoreErrors = @()
  foreach ($f in $CustomFiles) {
    git checkout origin/main -- $f 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
      Write-Host "  OK : $f" -ForegroundColor Green
    } else {
      Write-Host "  ERR: $f (not in origin/main?)" -ForegroundColor Red
      $restoreErrors += $f
    }
  }
  if ($restoreErrors) {
    Write-Host "`nWARN: $($restoreErrors.Count) file(s) could not be restored. Review manually." -ForegroundColor Yellow
  }
  git add -u
  git commit -m "chore: merge upstream/main $date (conflicts resolved — custom files restored)"
  Write-Host "`nConflicts resolved and committed." -ForegroundColor Green
  Write-Host "REVIEW the merge in: $mergeBranch" -ForegroundColor Yellow
} else {
  Write-Host "Merge successful (no conflicts)." -ForegroundColor Green
}

# Step 8: Post-merge verification
Write-Host "`nVerifying custom files..." -ForegroundColor Cyan
$verifyOk = Test-CustomFilesPresent -Files $CustomFiles

# Step 9: Reproducible install + build + type-check
Write-Host "`nInstalling dependencies (npm ci)..." -ForegroundColor Cyan
npm ci
if ($LASTEXITCODE -ne 0) {
  Write-Host "ERROR: npm ci FAILED." -ForegroundColor Red
  Write-Host "Rollback: git checkout main; git branch -D $mergeBranch" -ForegroundColor Yellow
  exit 1
}

Write-Host "Rebuilding UI..." -ForegroundColor Cyan
npm run ui:build
if ($LASTEXITCODE -ne 0) {
  Write-Host "ERROR: UI build FAILED." -ForegroundColor Red
  Write-Host "Rollback: git checkout main; git branch -D $mergeBranch" -ForegroundColor Yellow
  exit 1
}

Write-Host "Rebuilding backend..." -ForegroundColor Cyan
npx tsdown
if ($LASTEXITCODE -ne 0) {
  Write-Host "ERROR: tsdown FAILED." -ForegroundColor Red
  Write-Host "Rollback: git checkout main; git branch -D $mergeBranch" -ForegroundColor Yellow
  exit 1
}

Write-Host "`nType-check..." -ForegroundColor Cyan
$tsErrors = npx tsc --noEmit 2>&1 | Where-Object { $_ -match "error TS" -and $_ -notmatch "e2e.test" }
if ($tsErrors) {
  Write-Host "TypeScript errors — MERGE BRANCH IS NOT READY:" -ForegroundColor Red
  $tsErrors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
  Write-Host "`nOptions:" -ForegroundColor Yellow
  Write-Host "  Fix errors in branch '$mergeBranch', then: git push -u origin $mergeBranch" -ForegroundColor Yellow
  Write-Host "  Rollback (discard merge):  git checkout main; git branch -D $mergeBranch" -ForegroundColor Yellow
  Write-Host "  Recover patches:           git am $fmtPatch" -ForegroundColor DarkGray
  exit 1
}
Write-Host "TypeScript OK." -ForegroundColor Green

# Step 10: Push merge branch for review — DO NOT touch main automatically
git push -u origin $mergeBranch
Write-Host "`n========================================" -ForegroundColor Cyan
if ($verifyOk) {
  Write-Host " MERGE BRANCH READY: $mergeBranch" -ForegroundColor Green
} else {
  Write-Host " MERGE BRANCH HAS MISSING FILES — REVIEW REQUIRED" -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Review the diff, then fast-forward main:" -ForegroundColor White
Write-Host "  git checkout main" -ForegroundColor White
Write-Host "  git merge --ff-only $mergeBranch" -ForegroundColor White
Write-Host "  git push origin main" -ForegroundColor White
Write-Host "  git branch -d $mergeBranch" -ForegroundColor White
Write-Host "  git push origin --delete $mergeBranch" -ForegroundColor White
Write-Host ""
Write-Host "Recovery (if needed): git am $fmtPatch" -ForegroundColor DarkGray
Write-Host "  OR partial:          git apply --3way $diffPatch" -ForegroundColor DarkGray
Write-Host "========================================`n" -ForegroundColor Cyan
