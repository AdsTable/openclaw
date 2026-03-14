# AdsTable Developer Tools & Documentation

> All custom tools, scripts, hooks, and documentation for the AdsTable/openclaw fork.

## Structure

```
dev.docs/
├── CUSTOMIZATIONS.md          # Full inventory of all custom changes vs upstream
├── README.md                  # This file
├── patches/                   # Saved patches for upstream merge recovery
│   ├── *.fmtpatch            # git format-patch (reapply with: git am)
│   └── *.diff                # git diff (reapply with: git apply --3way)
├── scripts/
│   └── merge-upstream.ps1    # Safe upstream merge: backup + patch + merge + rebuild
└── hooks/                    # Reference copies (originals in .githooks/)
    ├── post-merge.sh         # Verifies customization markers after merge
    └── pre-push.sh           # TypeScript check + marker verification before push
```

## Quick Reference

### Upstream Merge
```powershell
pwsh dev.docs/scripts/merge-upstream.ps1 -DryRun   # Preview only
pwsh dev.docs/scripts/merge-upstream.ps1            # Full merge
```

### Recovery from Patch
```bash
git am dev.docs/patches/customizations-LATEST.fmtpatch       # Reapply ALL our commits
git apply --3way dev.docs/patches/customizations-LATEST.diff  # Fallback: apply diff
```

### Build Commands
```bash
pnpm run ui:build    # Vite UI bundle (REQUIRED after ui/src/ changes)
npx tsdown          # Node.js gateway backend
```

### Gateway Startup
```powershell
# From BitBucket/adstable.site repo:
scripts\start-gateway.bat    # Rebuilds UI + starts gateway on port 18789
```

## External Tools (in BitBucket/adstable.site repo)

These scripts are in `D:\BitBucket\adstable.site\`:

| Script | Purpose |
|--------|---------|
| `scripts/check-api-keys.ps1` | Validates all API keys (auth-profiles.json + .env) |
| `scripts/start-gateway.bat` | Rebuilds UI + starts OpenClaw gateway |
| `scripts/check-skills.js` | Validates skills configuration |

## Git Configuration

```bash
git config core.hooksPath .githooks          # Hooks directory
git config rerere.enabled true               # Auto-reuse conflict resolutions
git config rerere.autoupdate true            # Auto-stage rerere resolutions
```

## Protected Files (never commit)

| File | Contains |
|------|----------|
| `~/.openclaw/.env` | GROK_API_KEY, TELEGRAM_BOT_TOKEN, GATEWAY_AUTH_TOKEN |
| `~/.openclaw/openclaw.json` | Full OpenClaw configuration |
| `~/.openclaw/agents/main/agent/auth-profiles.json` | All provider API keys |
