# Proposed PRs for openclaw/openclaw upstream

> DRAFT — for discussion and grouping only. Nothing submitted yet.
> Base: current upstream/main
> Source: AdsTable/openclaw origin/main

## Prerequisites (BEFORE creating any PR)

1. **Sync fork with upstream:** `git fetch upstream && git rebase upstream/main`
2. **Create per-PR branches FROM upstream/main** — NOT from our origin/main
3. **Each PR = clean commits rewritten from scratch** (our commits are mixed, cannot cherry-pick)
4. **Write tests** — upstream requires `pnpm build && pnpm check && pnpm test`
5. **Run formatting:** `pnpm format:fix` (oxfmt)
6. **Follow:** https://github.com/openclaw/openclaw/blob/main/CONTRIBUTING.md

### Branch strategy per PR
```bash
git fetch upstream
git checkout -b pr/fix-fallbacks-display upstream/main
# Apply ONLY the changes for this PR (manual or git diff extraction)
# Write tests
# pnpm build && pnpm check && pnpm test
git push origin pr/fix-fallbacks-display
# Create PR on github.com/openclaw/openclaw from AdsTable:pr/fix-fallbacks-display
```

---

## PR 5: `fix(agents): fallbacks not displayed when agent not in agents.list`

**Priority:** 🔴 Submit FIRST — smallest, clearest bug fix.

**Problem:** When `agents.list` is null/empty (common for default agent),
`resolveModelFallbacks(config.entry?.model)` returns null because `config.entry`
is undefined. The Fallbacks input appears empty despite configured fallbacks.

**Changes (1 file, 1 line):**
- `ui/src/ui/views/agents.ts` — `resolveModelFallbacks(config.entry?.model ?? config.defaults?.model)`

**Tests needed:** Unit test for `renderAgentOverview` with null `agents.list`.

**Branch:** `pr/fix-fallbacks-display`

---

## PR 6: `fix(agents): model save writes to wrong config path when agent not in list`

**Priority:** 🔴 Submit SECOND — critical bug, small change.

**Problem:** `onModelChange` and `onModelFallbacksChange` use `agents.list[i].model`
which is undefined when agent not in list. Config reverts on reload.

**Changes (1 file, ~10 lines):**
- `ui/src/ui/app-render.ts` — fallback to `agents.defaults.model`

**Tests needed:** Integration test: change model when agent not in agents.list, verify config persistence.

**NOTE:** Must be extracted from `da69ec013` manually — that commit mixes 3 features.

**Branch:** `pr/fix-model-save-path`

---

## PR 1: `feat(ui): guard markdown renderer against pathological inputs`

**Priority:** 🟡 Third — security improvement, 1 file.

**Problem:** Long lines or deeply nested brackets can hang `marked.parse()`.

**Changes (1 file, ~50 lines):**
- `ui/src/ui/markdown.ts`
  - `isLikelyPathologicalMarkdown()` detection
  - `MARKDOWN_MAX_LINE_LENGTH = 6_000`, `MARKDOWN_BRACKET_PAIR_LIMIT = 1_500`
  - try/catch wrapper with `<pre>` fallback

**Tests needed:**
- `isLikelyPathologicalMarkdown()` unit tests with edge cases
- `toSanitizedMarkdownHtml()` test with pathological input

**Branch:** `pr/markdown-pathological-guard`

---

## PR 4: `feat(agents): improve model selection UX in dropdown`

**Priority:** 🟡 Fourth — pure UX, 2 files.

**Problem:** Hard to see active model. Unsorted list.

**Changes (2 files, ~30 lines):**
- `ui/src/ui/views/agents-utils.ts` — sort active first, bold, `← current` suffix
- `ui/src/ui/views/agents.ts` — pass current model

**Tests needed:** Unit test for `buildModelOptions()` sorting and label generation.

**NOTE:** Do NOT include `invalidProviders` param — that depends on PR 3 (auth check).

**Branch:** `pr/model-selection-ux`

---

## PR 7: `chore: add auth-profiles.json to .gitignore`

**Priority:** 🟢 Small, can submit anytime.

**Problem:** `auth-profiles.json` (API keys) not in upstream `.gitignore`.

**Changes (1 file, 2 lines):**
- `.gitignore` — add `auth-profiles.json` and `**/auth-profiles.json`

**Branch:** `pr/gitignore-auth-profiles`

---

## PR 2: `feat(ui): add session history viewer`

**Priority:** 🟢 Fifth — additive feature.

**Changes (2 files, ~106 lines):**
- `src/gateway/control-ui.ts` — `/history` route
- `ui/src/ui/views/sessions.ts` — History button

**Tests needed:** Route test for `/history`.

**Branch:** `pr/session-history-viewer`

---

## PR 3: `feat(agents): validate API keys before saving model config`

**Priority:** 🟢 LAST — largest PR, depends on all others being accepted.

**Should be split into:**

### PR 3a: Backend `agents.auth.check` RPC method
- `src/gateway/server-methods-list.ts` (1 line)
- `src/gateway/server-methods/agents.ts` (18 lines)
- Tests: RPC handler unit test

### PR 3b: Frontend API key validation on model change
- `ui/src/ui/app-render.ts` — onModelChange check
- `ui/src/ui/app-view-state.ts` — `agentsModelKeyError` type
- `ui/src/ui/app.ts` — `@state()` property
- `ui/src/ui/views/agents.ts` — inline callout
- Depends on: PR 3a merged

### PR 3c: Frontend API key validation on tab open (modal)
- `ui/src/ui/app-settings.ts` — Scenario 1 check
- `ui/src/ui/components/modal.ts` — modal component
- `ui/src/styles/components.css` — modal CSS
- Depends on: PR 3a + 3b merged

### PR 3d: Invalid provider marker in dropdown
- `ui/src/ui/views/agents-utils.ts` — `invalidProviders` param, `❌` prefix
- `ui/src/ui/views/agents.ts` — pass Set to `buildModelOptions`
- Depends on: PR 3b merged

---

## NOT for upstream (internal tooling)

| File | Reason |
|------|--------|
| `dev.docs/*` | Fork management |
| `.githooks/*` | Fork hooks |
| `.gitleaks.toml` | Our scanning config |
| `CUSTOMIZATIONS.md` | Fork inventory |
| `dev.docs/patches/*` | Recovery patches |

---

## Submission Plan

| Order | PR | Type | Files | Risk | Depends on |
|-------|-----|------|-------|------|------------|
| 1st | PR 5 | Bug fix | 1 | None | — |
| 2nd | PR 6 | Bug fix | 1 | None | — |
| 3rd | PR 7 | Security | 1 | None | — |
| 4th | PR 1 | Security | 1 | Low | — |
| 5th | PR 4 | UX | 2 | Low | — |
| 6th | PR 2 | Feature | 2 | Medium | — |
| 7th | PR 3a | Feature | 2 | Medium | — |
| 8th | PR 3b | Feature | 4 | Medium | PR 3a |
| 9th | PR 3c | Feature | 3 | Medium | PR 3a+3b |
| 10th | PR 3d | Feature | 2 | Low | PR 3b |

**Total: 10 PRs, all from upstream/main branches, each with tests.**
