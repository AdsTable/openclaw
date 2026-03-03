# OpenClaw Fork Customizations (AdsTable)

> **CRITICAL**: This file documents ALL custom changes made to this fork vs upstream.
> When merging upstream, these changes MUST be preserved or re-applied.
> Upstream: https://github.com/openclaw/openclaw

## Custom Commits (upstream/main..origin/main)

| SHA | Description | Files |
|-----|-------------|-------|
| 2505155fe | Session history viewer at /history, History button | `sessions.ts`, `control-ui.ts` |
| 8db866cec | Guard markdown renderer against pathological inputs | `markdown.ts` |
| da69ec013 | Agents: model save fix for defaults, auth check, bold+sort | 8 files |
| 9c859da95 | Agents: show fallbacks from defaults when agent not in list | `agents.ts` |
| 445982fe9 | Agents: API key warning modal + upstream merge script | `modal.ts`, `components.css`, `app-render.ts` |
| e8f36766c | Agents: split modal/callout into two states (no spam) | `app-settings.ts`, `modal.ts`, `app.ts`, `app-view-state.ts` |
| 42e1fb0d7 | Agents: ❌ invalid provider marker in dropdown | `agents-utils.ts`, `agents.ts` |
| b4fde200c | Fix: unify error format, guard empty provider Set, protect auth-profiles.json | `app-render.ts`, `agents.ts`, `.gitignore` |

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
- Added `agentsModelKeyError: string | null` — inline callout (Scenario 2: model change)
- Added `agentsModelKeyModalError: string | null` — modal overlay (Scenario 1: tab open)

### 7. `ui/src/ui/app.ts`
- Added `@state() agentsModelKeyError: string | null = null`
- Added `@state() agentsModelKeyModalError: string | null = null`

### 8. `ui/src/ui/markdown.ts`
- Added `isLikelyPathologicalMarkdown()` guard
- Added `MARKDOWN_MAX_LINE_LENGTH = 6_000` and `MARKDOWN_BRACKET_PAIR_LIMIT = 1_500`
- Wrapped `marked.parse()` in try/catch fallback

### 9. `ui/src/ui/views/agents-utils.ts`
- `buildModelOptions()`: active model sorted FIRST, `font-weight:bold`, label `Name ← current`
- `invalidProviders?: Set<string>` param: prefixes invalid-key models with `❌`
- Provider extracted from `agentsModelKeyError` (quotes regex `/"([^"]+)"/`)

### 9a. `ui/src/ui/app-render.ts` key-check error messages (unified format)
- All `agentsModelKeyError` messages use `"${provider}"` (quoted) so regex always matches
- Scenario 2 (model change): `API key for "${provider}" is missing or invalid`
- Scenario 2 (save block): `API key for "${provider}" is invalid or missing`
- Scenario 2 (network fail): `Cannot verify API key for provider "${provider}"`

### 10. `ui/src/ui/views/agents.ts`
- `renderAgentOverview`: `modelKeyError` prop, inline callout, fallbacks fix
- `buildModelOptions` call passes `invalidProviders` Set (filtered, no empty strings)

### 11. `ui/src/ui/views/sessions.ts`
- Added "📜 History" button linking to `/history`
- Updated subtitle text

### 12. `ui/src/ui/components/modal.ts` *(new file)*
- `renderApiKeyModal(state)`: modal overlay for **Scenario 1 only** (tab open) via `agentsModelKeyModalError`
- **Scenario 1** (tab open): `agentsModelKeyModalError` → **Modal** (dismissable overlay)
- **Scenario 2** (model change): `agentsModelKeyError` → **Inline callout** near Save button
- Two separate states prevent modal spam on every model change

### 13. `ui/src/styles/components.css`
- Added `.api-key-modal-*` CSS classes following `exec-approval` pattern

### 14. `scripts/merge-upstream.ps1` *(new file)*
- Safe upstream merge: backup branch → save patch → merge → auto-restore custom files on conflict → rebuild

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
