# Proposed PRs for openclaw/openclaw upstream

> DRAFT — for discussion and grouping only. Nothing submitted yet.
> Base: current upstream/main
> Source: AdsTable/openclaw origin/main

---

## PR 1: `feat(ui): guard markdown renderer against pathological inputs`

**Problem:** Long lines or deeply nested bracket patterns can cause `marked.parse()` 
to hang or crash the UI, freezing the browser tab.

**Changes:**
- `ui/src/ui/markdown.ts`
  - Added `MARKDOWN_MAX_LINE_LENGTH = 6_000` and `MARKDOWN_BRACKET_PAIR_LIMIT = 1_500`
  - Added `isLikelyPathologicalMarkdown()` detection function
  - Wrapped `marked.parse()` in try/catch with `<pre>` fallback
  - Pathological input rendered as escaped `<pre>` block instead of hanging

**Impact:** 50 lines added/changed in 1 file. Zero breaking changes.

**Commit:** `8db866cec`

---

## PR 2: `feat(ui): add session history viewer`

**Problem:** No way to view archived/past sessions from the UI.

**Changes:**
- `src/gateway/control-ui.ts` — new `/history` route (90 lines)
- `ui/src/ui/views/sessions.ts` — "History" button + subtitle update (16 lines)

**Impact:** 106 lines across 2 files. Additive only.

**Commit:** `2505155fe`

---

## PR 3: `feat(agents): validate API keys before saving model config`

**Problem:** Users can select a model with an invalid/missing API key, save the config, 
and only discover the error when the agent fails to respond. No feedback loop.

**Changes:**
- `src/gateway/server-methods-list.ts` — register `"agents.auth.check"` (1 line)
- `src/gateway/server-methods/agents.ts` — handler: validates provider key via 
  `resolveApiKeyForProvider()`, returns `{ valid, provider }` (18 lines)
- `ui/src/ui/app-render.ts` — call `agents.auth.check` on model change and before save;
  block save if key invalid; show error via `agentsModelKeyError` (70 lines)
- `ui/src/ui/app-settings.ts` — check primary model key on Agents tab open (20 lines)
- `ui/src/ui/app-view-state.ts` — add `agentsModelKeyError` + `agentsModelKeyModalError` types
- `ui/src/ui/app.ts` — add `@state()` properties
- `ui/src/ui/views/agents.ts` — inline callout near Save button (9 lines)
- `ui/src/ui/components/modal.ts` — modal overlay for tab-open check (37 lines)
- `ui/src/styles/components.css` — `.api-key-modal-*` CSS (61 lines)

**Impact:** ~220 lines across 9 files. New RPC method `agents.auth.check`.

**Commits:** `da69ec013`, `445982fe9`, `e8f36766c`, `b4fde200c`

---

## PR 4: `feat(agents): improve model selection UX`

**Problem:** Hard to see which model is currently active. No visual feedback 
when a model has an invalid key. Models not sorted logically.

**Changes:**
- `ui/src/ui/views/agents-utils.ts` — `buildModelOptions()`:
  - Active model sorted FIRST in dropdown
  - Active model bold (`font-weight: bold`) + `← current` suffix
  - New `invalidProviders?: Set<string>` param: `❌` prefix for invalid-key models
  - Missing current model auto-prepended to list
- `ui/src/ui/views/agents.ts` — pass `invalidProviders` Set (filtered, no empty strings)

**Impact:** ~30 lines across 2 files. Pure UI improvement.

**Commits:** `da69ec013`, `1791c8141`, `7c5e6871f`, `a1fab3a3f`, `42e1fb0d7`

---

## PR 5: `fix(agents): fallbacks not displayed when agent not in agents.list`

**Problem:** When `agents.list` is null/empty (common for default agent), 
`resolveModelFallbacks(config.entry?.model)` returns null because `config.entry` 
is undefined. The Fallbacks input field appears empty despite having configured fallbacks.

**Changes:**
- `ui/src/ui/views/agents.ts` — change to `resolveModelFallbacks(config.entry?.model ?? config.defaults?.model)`

**Impact:** 1 line changed. Bug fix.

**Commit:** `9c859da95`

---

## PR 6: `fix(agents): model save writes to wrong config path when agent not in list`

**Problem:** `onModelChange` and `onModelFallbacksChange` fail to update the correct 
config path when the agent is not in `agents.list` (uses `agents.list[i].model` 
which doesn't exist). Falls silently — config appears saved but reverts on reload.

**Changes:**
- `ui/src/ui/app-render.ts` — fallback to `agents.defaults.model` when agent not in list

**Impact:** ~10 lines changed. Critical bug fix.

**Commit:** `da69ec013`

---

## NOT for upstream (internal tooling)

These files are AdsTable-specific and should NOT be submitted upstream:

| File | Reason |
|------|--------|
| `dev.docs/*` | Fork management documentation |
| `.githooks/*` | Fork-specific hooks |
| `.gitleaks.toml` | Our security scanning config |
| `.gitignore` additions | `auth-profiles.json`, `*.env` — our additions |
| `CUSTOMIZATIONS.md` | Fork inventory |

---

## Grouping Summary

| PR | Title | Files | Lines | Type |
|----|-------|-------|-------|------|
| 1 | Markdown pathological input guard | 1 | ~50 | Security |
| 2 | Session history viewer | 2 | ~106 | Feature |
| 3 | API key validation before save | 9 | ~220 | Feature |
| 4 | Model selection UX improvements | 2 | ~30 | UX |
| 5 | Fallbacks display fix | 1 | 1 | Bug fix |
| 6 | Model save config path fix | 1 | ~10 | Bug fix |

**Recommended submission order:** 5 → 6 → 1 → 4 → 2 → 3 (bug fixes first, then features)
