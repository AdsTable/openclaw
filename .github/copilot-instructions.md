# Copilot & AI Agent Instructions — AdsTable/openclaw

## CRITICAL: CI/CD Runner Policy

### ❌ BANNED — macOS runners
NEVER add `runs-on: macos-latest`, `runs-on: macos-14`, `runs-on: macos-*`,
or ANY macOS runner label to ANY workflow file in this repository.

**Reason:** This project is maintained on Windows only.
macOS GitHub-hosted runners cost $0.062/min — approximately 10x more expensive
than Linux ($0.006/min). They caused significant unexpected billing charges and
provide zero value for this codebase.

### ✅ APPROVED runners
- `ubuntu-latest` / `ubuntu-24.04` — general Linux jobs
- `windows-latest` / `windows-2025` — Windows-specific jobs  
- `blacksmith-16vcpu-ubuntu-2404` — heavy Linux jobs
- `blacksmith-32vcpu-windows-2025` — heavy Windows jobs

### ❌ BANNED — Swift / Xcode / iOS CI
Do NOT add any of the following to workflows:
- `xcode-select`, `xcodebuild`, `swift build`, `swift test`
- `swiftlint`, `swiftformat`, `xcodegen`
- `brew install` for Swift tooling

### Enforcement
The workflow `.github/workflows/no-macos-runners.yml` automatically FAILS
any PR that introduces `runs-on: macos-*` into any workflow file.
