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
#   7. Show upstream changelog + auto-detect $CustomFiles drift (WARN if unprotected files found)
#   8. Merge upstream/main into temp branch; auto-restore $CustomFiles on conflict
#   9. Post-merge verification + pnpm install + build + postbuild (elevated) + typecheck (TS errors ABORT)
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
# Verified: 2026-03-24 post-merge v2026.3.23 (storage.ts, tsdown.config.ts, status.scan.ts now = upstream)
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
  # Repo infrastructure
  "CUSTOMIZATIONS.md",
  "scripts/merge-upstream.ps1",
  ".gitignore",
  ".gitleaks.toml",
  ".githooks/post-merge",
  ".githooks/pre-push",
  # Dependencies — both M in post-merge diff (z-ai-web-dev-sdk + pnpm bump)
  "package.json",
  "pnpm-lock.yaml",
  # Build config — Vite node stubs + browser polyfills (fork-only fixes)
  "ui/vite.config.ts",
  "ui/src/node-stubs/fs.ts",
  "ui/src/node-stubs/empty.ts",
  "ui/src/node-stubs/path.ts",
  "ui/src/node-stubs/os.ts",
  "ui/src/process-polyfill.ts",
  "ui/src/main.ts",
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

# Auto-detect drift — WARN only (not FAIL) for large squash-based forks.
# The real protection is backup tag (Step 5) + auto-restore $CustomFiles on conflict (Step 8).
# --diff-filter=M: Modified files (exist in both sides, we changed them)
$detectedFiles = @(
  git diff upstream/main HEAD --name-only --diff-filter=M |
  Where-Object { $_ -and -not ($_ -match '^dev[/\\]docs') -and -not ($_ -match '^docs[/\\]zh') } |
  ForEach-Object { $_.Replace('\', '/') }
)
$unprotected = $detectedFiles | Where-Object { $CustomFiles -notcontains $_ }
if ($unprotected) {
  Write-Host "`nINFO: $($unprotected.Count) modified file(s) not in CustomFiles (will take upstream version on conflict):" -ForegroundColor DarkGray
  $unprotected | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
  if ($unprotected.Count -gt 10) { Write-Host "  ... and $($unprotected.Count - 10) more" -ForegroundColor DarkGray }
}
$cfCount = ($detectedFiles | Where-Object { $CustomFiles -contains $_ }).Count
Write-Host "CustomFiles protected: $cfCount / $($detectedFiles.Count) modified files." -ForegroundColor $(if($cfCount -gt 0){'Green'}else{'Yellow'})

# Step 7: Merge upstream into temp branch (already fetched in Step 3)
Write-Host "`nMerging upstream/main into $mergeBranch..." -ForegroundColor Cyan
git merge upstream/main --no-ff -m "chore: merge upstream/main $date"
$mergeExitCode = $LASTEXITCODE

if ($mergeExitCode -ne 0) {
  $conflicts = @(git diff --name-only --diff-filter=U)
  Write-Host "`nCONFLICTS in:" -ForegroundColor Yellow
  $conflicts | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }

  # ── TRUE three-way merge per custom file ────────────────────────────────
  # CRITICAL: `git checkout --ours` takes the ENTIRE pre-merge file, losing
  # upstream's auto-merged hunks.  Instead, use `git merge-file --ours` which
  # performs a real three-way merge: non-conflicting changes from BOTH sides
  # are kept, only conflicting hunks resolve in favor of ours.
  #
  # During a merge conflict, git's index has three stages:
  #   :1:file = common ancestor (merge base)
  #   :2:file = ours  (HEAD, our branch)
  #   :3:file = theirs (upstream/main)
  Write-Host "`nResolving conflicts in custom files (true three-way merge)..." -ForegroundColor Cyan
  $restoreErrors = @()
  $conflictSet = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )
  $conflicts | ForEach-Object { [void]$conflictSet.Add($_.Replace('\','/')) }

  foreach ($f in $CustomFiles) {
    $fNorm = $f.Replace('\','/')
    if (-not $conflictSet.Contains($fNorm)) { continue }

    # Extract three stages from git index using BOM-free UTF8 + LF
    # CRITICAL: Set-Content converts LF→CRLF on Windows, corrupting merge.
    # Use WriteAllText with explicit UTF8-no-BOM encoding.
    $tmpBase   = [System.IO.Path]::GetTempFileName()
    $tmpOurs   = [System.IO.Path]::GetTempFileName()
    $tmpTheirs = [System.IO.Path]::GetTempFileName()
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    try {
      $baseContent   = (git show ":1:$f" 2>$null) -join "`n"
      $oursContent   = (git show ":2:$f" 2>$null) -join "`n"
      $theirsContent = (git show ":3:$f" 2>$null) -join "`n"

      # Stage 1 (base) may not exist for newly added files;
      # Stage 2 (ours) missing means file is new from upstream only.
      if (-not $baseContent -and -not $oursContent) {
        # File is new in upstream, not in ours — take theirs
        git checkout --theirs -- $f 2>&1 | Out-Null
        git add $f 2>&1 | Out-Null
        Write-Host "  THEIRS: $f (new upstream file)" -ForegroundColor DarkGray
        continue
      }
      if (-not $baseContent) { $baseContent = "" }

      [System.IO.File]::WriteAllText($tmpBase,   $baseContent,   $utf8NoBom)
      [System.IO.File]::WriteAllText($tmpOurs,   $oursContent,   $utf8NoBom)
      [System.IO.File]::WriteAllText($tmpTheirs, $theirsContent, $utf8NoBom)

      # Three-way merge: keeps both sides' changes, conflicts → ours wins
      # Exit codes: 0=clean, >0=N conflicts (resolved by --ours), <0=error
      git merge-file --ours $tmpOurs $tmpBase $tmpTheirs 2>$null
      if ($LASTEXITCODE -lt 0) { throw "git merge-file returned error ($LASTEXITCODE)" }
      Copy-Item $tmpOurs $f -Force
      git add $f 2>&1 | Out-Null
      Write-Host "  MERGE: $f (three-way, ours wins conflicts)" -ForegroundColor Green
    } catch {
      Write-Host "  ERR  : $f (merge-file failed: $_)" -ForegroundColor Red
      # Fallback: leave conflict markers for manual resolution
      $restoreErrors += $f
    } finally {
      Remove-Item $tmpBase, $tmpOurs, $tmpTheirs -Force -ErrorAction SilentlyContinue
    }
  }

  # Resolve remaining non-custom conflicts by taking upstream version
  $remainingConflicts = @(git diff --name-only --diff-filter=U)
  foreach ($rc in $remainingConflicts) {
    $rcNorm = $rc.Replace('\','/')
    if ($CustomFiles -notcontains $rcNorm) {
      git checkout --theirs -- $rc 2>&1 | Out-Null
      git add $rc 2>&1 | Out-Null
      Write-Host "  THEIRS: $rc (non-custom → took upstream)" -ForegroundColor DarkGray
    }
  }

  if ($restoreErrors) {
    Write-Host "`nERROR: $($restoreErrors.Count) custom file(s) could not be auto-resolved:" -ForegroundColor Red
    $restoreErrors | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    Write-Host "Fix conflicts manually, then: git add . && git commit" -ForegroundColor Yellow
    Write-Host "Rollback: git merge --abort; git checkout main; git branch -D $mergeBranch" -ForegroundColor Yellow
    exit 1
  }
  git add -u
  git commit -m "chore: merge upstream/main $date (conflicts resolved — three-way strategy)"
  Write-Host "`nConflicts resolved and committed." -ForegroundColor Green
  Write-Host "REVIEW the merge in: $mergeBranch" -ForegroundColor Yellow
} else {
  Write-Host "Merge successful (no conflicts)." -ForegroundColor Green
}

# ── Post-merge audit ──────────────────────────────────────────────────────
# Compare each CustomFile's diff vs upstream BEFORE and AFTER merge.
# If the number of removed lines INCREASED, we likely lost upstream additions.
# This avoids false positives on files we intentionally modified (CSS, etc.).
Write-Host "`nPost-merge audit — detecting NEW upstream line losses..." -ForegroundColor Cyan
$auditIssues = @()
foreach ($f in $CustomFiles) {
  if (-not (Test-Path $f)) { continue }
  # Lines removed vs upstream in the NEW merge result
  $removedNow = @(git diff upstream/main HEAD -- $f 2>&1 |
    Select-String "^\-" | Where-Object { $_ -notmatch "^\-\-\-" }).Count
  # Lines removed vs upstream BEFORE merge (from backup tag)
  $removedBefore = @(git diff upstream/main $backupTag -- $f 2>&1 |
    Select-String "^\-" | Where-Object { $_ -notmatch "^\-\-\-" }).Count
  $delta = $removedNow - $removedBefore
  if ($delta -gt 10) {
    $auditIssues += "  AUDIT: $f — $delta NEW lines lost vs upstream (was -$removedBefore, now -$removedNow)"
  }
}
if ($auditIssues) {
  Write-Host "`n$($auditIssues.Count) file(s) with significant upstream deletions:" -ForegroundColor Yellow
  $auditIssues | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
  Write-Host "  Run: git diff upstream/main HEAD -- <file> to review each one." -ForegroundColor DarkGray
} else {
  Write-Host "  Audit OK — no unexpected large deletions detected." -ForegroundColor Green
}

# Step 8: Post-merge verification
Write-Host "`nVerifying custom files..." -ForegroundColor Cyan
$verifyOk = Test-CustomFilesPresent -Files $CustomFiles

# Step 9: Reproducible install + build + type-check
# NOTE: pnpm-lock.yaml cannot be reliably text-merged (YAML semantics).
# Always run `pnpm install` (without --frozen) after merge to regenerate
# the lockfile with both our additions and upstream's new packages.
# Then commit the updated lockfile if it changed.
Write-Host "`nInstalling dependencies (regenerating lockfile after merge)..." -ForegroundColor Cyan
pnpm install
if ($LASTEXITCODE -ne 0) {
  Write-Host "ERROR: pnpm install FAILED." -ForegroundColor Red
  Write-Host "Rollback: git checkout main; git branch -D $mergeBranch" -ForegroundColor Yellow
  exit 1
}
$lockChanged = git status --porcelain pnpm-lock.yaml 2>&1
if ($lockChanged) {
  git add pnpm-lock.yaml
  git commit -m "chore: regenerate pnpm-lock.yaml after upstream merge $date" --no-verify
  Write-Host "  Lockfile regenerated and committed." -ForegroundColor Green
} else {
  Write-Host "  Lockfile unchanged." -ForegroundColor DarkGray
}

Write-Host "Rebuilding UI..." -ForegroundColor Cyan
pnpm run ui:build
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

# ── Runtime postbuild (requires admin for symlinks on Windows) ───────────────
# runtime-postbuild.mjs creates symlinks in dist-runtime/ and dist/plugin-sdk/.
# Windows requires Developer Mode OR elevated (admin) to create symlinks.
# We auto-elevate via Start-Process -Verb RunAs and wait for completion.
Write-Host "Running runtime-postbuild (elevated for symlink support)..." -ForegroundColor Cyan
$postbuildLog = "$env:TEMP\openclaw-postbuild-$date.log"
$postbuildScript = @"
Set-Location '$RepoRoot'
`$errors = @()
node scripts/runtime-postbuild.mjs 2>&1 | Out-File '$postbuildLog' -Encoding UTF8
if (`$LASTEXITCODE -ne 0) { `$errors += 'runtime-postbuild.mjs' }
node --import tsx scripts/write-build-info.ts 2>&1 | Out-File '$postbuildLog' -Encoding UTF8 -Append
if (`$LASTEXITCODE -ne 0) { `$errors += 'write-build-info.ts' }
node --import tsx scripts/write-cli-startup-metadata.ts 2>&1 | Out-File '$postbuildLog' -Encoding UTF8 -Append
if (`$LASTEXITCODE -ne 0) { `$errors += 'write-cli-startup-metadata.ts' }
node --import tsx scripts/write-cli-compat.ts 2>&1 | Out-File '$postbuildLog' -Encoding UTF8 -Append
if (`$LASTEXITCODE -ne 0) { `$errors += 'write-cli-compat.ts' }
if (`$errors) { "POSTBUILD_FAILED:`$(`$errors -join ',')" | Out-File '$postbuildLog' -Append }
else { "POSTBUILD_OK" | Out-File '$postbuildLog' -Append }
"@
$encodedScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($postbuildScript))
Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -EncodedCommand $encodedScript" -Wait
$postbuildResult = Get-Content $postbuildLog -ErrorAction SilentlyContinue | Select-Object -Last 1
if ($postbuildResult -match "^POSTBUILD_FAILED:(.+)$") {
  Write-Host "ERROR: postbuild failed — $($Matches[1])" -ForegroundColor Red
  Write-Host "  Log: $postbuildLog" -ForegroundColor DarkGray
  Write-Host "  Run manually (as admin): node scripts/runtime-postbuild.mjs" -ForegroundColor Yellow
  Write-Host "Rollback: git checkout main; git branch -D $mergeBranch" -ForegroundColor Yellow
  exit 1
} elseif ($postbuildResult -ne "POSTBUILD_OK") {
  Write-Host "WARN: postbuild log missing or incomplete — verify manually." -ForegroundColor Yellow
  Write-Host "  Log: $postbuildLog" -ForegroundColor DarkGray
} else {
  Write-Host "  Postbuild OK." -ForegroundColor Green
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
