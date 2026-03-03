# Safe upstream merge script for AdsTable/openclaw fork.
# Run from repo root: pwsh scripts/merge-upstream.ps1

param([switch]$DryRun)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
Set-Location $RepoRoot

$CustomFiles = @(
  "src/gateway/server-methods-list.ts",
  "src/gateway/server-methods/agents.ts",
  "ui/src/ui/app-render.ts",
  "ui/src/ui/app-settings.ts",
  "ui/src/ui/app-view-state.ts",
  "ui/src/ui/app.ts",
  "ui/src/ui/views/agents-utils.ts",
  "ui/src/ui/views/agents.ts",
  "ui/src/ui/components/modal.ts",
  "ui/src/ui/markdown.ts",
  "ui/src/ui/views/sessions.ts",
  "ui/src/styles/components.css",
  "src/gateway/control-ui.ts",
  ".gitignore"
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " OpenClaw Upstream Merge (AdsTable fork)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Step 1: Verify clean working tree
$status = git status --porcelain
if ($status) {
  Write-Host "ERROR: Uncommitted changes detected. Commit or stash first." -ForegroundColor Red
  git status --short
  exit 1
}

# Step 2: Save patch of our customizations BEFORE merge
$date = Get-Date -Format "yyyyMMdd-HHmm"
$patchFile = "docs/patches/customizations-$date.patch"
New-Item -ItemType Directory -Path "docs/patches" -Force | Out-Null
git diff upstream/main origin/main -- @($CustomFiles) | Out-File $patchFile -Encoding UTF8
Write-Host "Patch saved: $patchFile ($((Get-Item $patchFile).Length) bytes)" -ForegroundColor Green

if ($DryRun) {
  Write-Host "`nDRY RUN complete. Patch saved for review. No branches created, no merge performed." -ForegroundColor Yellow
  Write-Host "To apply patch after a future merge: git apply $patchFile" -ForegroundColor Yellow
  exit 0
}

# Step 3: Create backup branch
$backupBranch = "backup/pre-upstream-$date"
git checkout -b $backupBranch
git push origin $backupBranch
Write-Host "Backup branch pushed: $backupBranch" -ForegroundColor Green

# Step 4: Return to main
git checkout main

# Step 5: Fetch and merge upstream
Write-Host "`nFetching upstream..." -ForegroundColor Cyan
git fetch upstream
Write-Host "Merging upstream/main..." -ForegroundColor Cyan
$mergeResult = git merge upstream/main --no-ff -m "chore: merge upstream/main $date" 2>&1
$mergeExitCode = $LASTEXITCODE

if ($mergeExitCode -ne 0) {
  Write-Host "`nCONFLICTS detected in:" -ForegroundColor Yellow
  git diff --name-only --diff-filter=U
  Write-Host "`nAuto-restoring our custom files..." -ForegroundColor Yellow
  foreach ($f in $CustomFiles) {
    if (Test-Path $f) {
      git checkout origin/main -- $f 2>$null
      Write-Host "  Restored: $f" -ForegroundColor Green
    }
  }
  Write-Host "`nWARNING: Custom files restored from origin/main." -ForegroundColor Yellow
  Write-Host "Review remaining conflicts: git diff --name-only --diff-filter=U" -ForegroundColor Yellow
  Write-Host "To recover all custom changes: git apply $patchFile" -ForegroundColor Yellow
  Write-Host "Then: git add . && git commit -m 'chore: merge upstream/main $date'" -ForegroundColor Yellow
} else {
  Write-Host "Merge successful (no conflicts)." -ForegroundColor Green
}

# Step 6: Rebuild
Write-Host "`nRebuilding UI..." -ForegroundColor Cyan
npm run ui:build
Write-Host "Rebuilding backend..." -ForegroundColor Cyan
npx tsdown

Write-Host "`nType-check..." -ForegroundColor Cyan
$tsErrors = npx tsc --noEmit 2>&1 | Where-Object { $_ -match "error TS" -and $_ -notmatch "e2e.test" }
if ($tsErrors) {
  Write-Host "TypeScript errors found:" -ForegroundColor Red
  $tsErrors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
} else {
  Write-Host "TypeScript OK." -ForegroundColor Green
}

Write-Host "`nDone. Push with: git push origin main" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan
