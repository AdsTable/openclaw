# Copilot & AI Agent Instructions — AdsTable/openclaw

## 🔒 CRITICAL: CI/CD Runner & Tooling Policy

> These rules are enforced automatically by `.github/workflows/no-macos-runners.yml`.
> Any PR violating them will FAIL CI automatically.

### ❌ BANNED — macOS runners
NEVER add `runs-on: macos-latest`, `runs-on: macos-14`, `runs-on: macos-*`,
or ANY macOS runner label to ANY workflow file in this repository.

**Reason:** macOS runners cost $0.08/min — **10x more expensive** than Linux ($0.008/min).
They caused significant unexpected billing charges.

### ✅ APPROVED runners
| Runner | Use for |
|--------|---------|
| `ubuntu-latest` / `ubuntu-24.04` | All general jobs (default) |
| `blacksmith-16vcpu-ubuntu-2404` | Heavy Linux jobs (build, test) |
| `windows-latest` / `windows-2025` | Windows-specific jobs only |

### ❌ BANNED — Swift / Xcode / iOS CI tooling
Do NOT add to any workflow:
`xcode-select`, `xcodebuild`, `swift build`, `swift test`, `swift package`,
`swiftlint`, `swiftformat`, `xcodegen`, `brew install <swift-tool>`

**Reason:** This is a Windows/Node.js codebase. Swift source in `apps/macos/`, `apps/ios/`
is not actively maintained and does not need CI.

### ❌ BANNED — Android / Gradle native CI
Do NOT add to any workflow:
`gradlew`, `android-sdk`, `avdmanager`, `sdkmanager`

**Reason:** Android native CI is not needed for this Node.js project.

### ❌ BANNED — Daily Dependabot for Swift/Gradle
Do NOT add `package-ecosystem: swift` or `package-ecosystem: gradle` to `dependabot.yml`
with `interval: daily`. These generate dozens of PRs per week that trigger expensive CI.

### ⚠️ COST RULES — General CI hygiene
1. **Always set `timeout-minutes`** on every job (default: 20) — prevents runaway 6h billing.
2. **Use `retention-days: 1`** for intermediate build artifacts (dist/, coverage/).
3. **Never use matrix with 3+ platforms** — ubuntu + windows is sufficient for Node.js.
4. **Always cache dependencies** with `actions/cache` — never re-install from scratch.
5. **Prefer `workflow_dispatch`** over `schedule:` cron for heavy scanning jobs.

### Enforcement
The workflow `.github/workflows/no-macos-runners.yml` automatically FAILS any PR that
introduces macOS runners, Swift/Xcode tools, or Android native CI into any workflow file.
