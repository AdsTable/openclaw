# OpenClaw Fork Customizations (AdsTable)

> **CRITICAL**: This file documents ALL custom changes made to this fork vs upstream.
> When merging upstream, these changes MUST be preserved or re-applied.
> Upstream: https://github.com/openclaw/openclaw

## Custom Commits (upstream/main..origin/main)

| SHA | Description | Files |
|-----|-------------|-------|
| 2505155fe | Session history viewer at /history, History button in Sessions UI | `sessions.ts`, `control-ui.ts` |
| 8db866cec | Guard markdown renderer against pathological inputs and parser timeout | `markdown.ts` |
| da69ec013 | Agents: active model first+bold+arrow, auth check on load/change, fix model save for defaults | 8 files |
| 1791c8141 | Agents: arrow direction left + add (current) label | `agents-utils.ts` |
| 7c5e6871f | Agents: label format 'Name <- current' | `agents-utils.ts` |
| a1fab3a3f | Agents: unicode arrow ← in current model label | `agents-utils.ts` |
| 9c859da95 | Agents: show fallbacks from defaults when agent not in list | `agents.ts` |

## Changed Files Summary

### 1. `src/gateway/control-ui.ts`
- Session history route `/history` added

### 2. `src/gateway/server-methods-list.ts`
- Added `"agents.auth.check"` to BASE_METHODS

### 3. `src/gateway/server-methods/agents.ts`
- Added `agents.auth.check` handler (validates provider API key via auth-profiles)

### 4. `ui/src/ui/app-render.ts`
- `onModelChange`: falls back to `agents.defaults.model` when agent not in `agents.list`
- `onModelFallbacksChange`: same fallback fix
- `onConfigSave`: validates API key via `agents.auth.check` BEFORE saving (Scenario 2)
- `onConfigReload`: clears `agentsModelKeyError`
- Passes `modelKeyError` prop to `renderAgents`

### 5. `ui/src/ui/app-settings.ts`
- `refreshActiveTab("agents")`: checks current model's API key validity on tab open (Scenario 1)

### 6. `ui/src/ui/app-view-state.ts`
- Added `agentsModelKeyError: string | null`

### 7. `ui/src/ui/app.ts`
- Added `@state() agentsModelKeyError: string | null = null`

### 8. `ui/src/ui/markdown.ts`
- Added `isLikelyPathologicalMarkdown()` guard
- Added `MARKDOWN_MAX_LINE_LENGTH = 6_000` and `MARKDOWN_BRACKET_PAIR_LIMIT = 1_500`
- Wrapped `marked.parse()` in try/catch fallback

### 9. `ui/src/ui/views/agents-utils.ts`
- `buildModelOptions()`: active model sorted FIRST, bold (`font-weight:bold`), label `Name ← current`

### 10. `ui/src/ui/views/agents.ts`
- `renderAgentOverview`: added `modelKeyError` prop + callout display
- `modelFallbacks`: fixed to use `config.entry?.model ?? config.defaults?.model`

### 11. `ui/src/ui/views/sessions.ts`
- Added "📜 History" button linking to `/history`
- Updated subtitle text

## How to Merge Upstream Safely

```bash
# Step 1: Fetch upstream
git fetch upstream

# Step 2: Create a backup branch before merge
git checkout -b backup/before-upstream-merge-$(date +%Y%m%d)
git push origin backup/before-upstream-merge-$(date +%Y%m%d)

# Step 3: Merge upstream into main
git checkout main
git merge upstream/main --no-ff -m "chore: merge upstream/main"

# Step 4: If conflicts - our files ALWAYS WIN for these paths:
# git checkout origin/main -- src/gateway/server-methods/agents.ts
# git checkout origin/main -- src/gateway/server-methods-list.ts
# git checkout origin/main -- ui/src/ui/app-render.ts
# git checkout origin/main -- ui/src/ui/app-settings.ts
# git checkout origin/main -- ui/src/ui/app-view-state.ts
# git checkout origin/main -- ui/src/ui/app.ts
# git checkout origin/main -- ui/src/ui/views/agents-utils.ts
# git checkout origin/main -- ui/src/ui/views/agents.ts
# Then manually re-apply our changes on top of upstream's version

# Step 5: Rebuild
npm run ui:build
npx tsdown

# Step 6: Push
git push origin main
```

## External Config Files (NOT in git — must be backed up separately)

| File | Description |
|------|-------------|
| `C:\Users\Martin\.openclaw\.env` | Infrastructure secrets (GROK, TELEGRAM, GATEWAY) |
| `C:\Users\Martin\.openclaw\openclaw.json` | Main OpenClaw configuration |
| `C:\Users\Martin\.openclaw\agents\main\agent\auth-profiles.json` | API keys and OAuth tokens |

## Build Commands

```bash
npm run ui:build    # Rebuild Vite UI bundle (REQUIRED after any ui/src/ changes)
npx tsdown          # Rebuild Node.js gateway backend
npm run build       # Full build (backend only, does NOT rebuild UI)
```

## Dev Workflow

```bash
# Terminal 1: Vite HMR (instant UI updates, no restart needed)
npm run ui:dev

# Terminal 2: Gateway
scripts\start-gateway.bat
```
