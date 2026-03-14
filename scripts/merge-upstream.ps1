# Delegates to the hardened merge script in dev.docs/scripts/.
# Usage: pwsh scripts/merge-upstream.ps1 [-DryRun]
param([switch]$DryRun)
$script = Join-Path $PSScriptRoot "..\dev.docs\scripts\merge-upstream.ps1"
if (-not (Test-Path $script)) { Write-Error "Not found: $script"; exit 1 }
& $script @PSBoundParameters