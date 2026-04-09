# Copilot & AI Agent Instructions — AdsTable/openclaw

## 🔒 CRITICAL: CI/CD Runner & Tooling Policy

> These rules are enforced automatically by `.github/workflows/no-macos-runners.yml`.
> Any PR violating them will FAIL CI automatically.

---

### ❌ BANNED — macOS runners
NEVER add `runs-on: macos-latest`, `runs-on: macos-14`, `runs-on: macos-*`,
or ANY macOS runner label to ANY workflow file in this repository.

**Reason:** macOS GitHub-hosted runners cost $0.08/min — **10x more expensive**
than Linux ($0.008/min). They caused significant unexpected billing charges and
provide zero value for this Windows/Node.js codebase.

### ✅ APPROVED runners
| Runner | Use for |
|--------|---------|
| `ubuntu-latest` / `ubuntu-24.04` | All general jobs (default choice) |
| `windows-latest` | Windows-specific jobs only |
| `blacksmith-16vcpu-ubuntu-2404` | Heavy parallel builds (prefer 16vcpu, not 32) |

---

### ❌ BANNED — Swift / Xcode / iOS CI tooling
Do NOT add any of the following to any workflow file:

```
xcode-select    xcodebuild     swift build    swift test
swift package   swiftlint      swiftformat    xcodegen
brew install    (for Swift/iOS tooling)
```

**Reason:** This is a Windows/Node.js project. No iOS/macOS builds needed in CI.

---

### ❌ BANNED — Android / Gradle native CI
Do NOT add any of the following to any workflow file:

```
gradle    gradlew    android-sdk    avdmanager    sdkmanager    emulator
```

**Reason:** No Android native CI needed. Use `ubuntu-latest` for Node.js builds.

---

### ⚠️ CAUTION — Large/Expensive Runners
Avoid `blacksmith-32vcpu-*` and `ubuntu-32core` / `windows-32core` runners unless
absolutely necessary. These cost **8x** a standard runner. Prefer `blacksmith-16vcpu-ubuntu-2404`.
