# Build & Deploy — MarsinDictation

This document defines the build and deployment process for all MarsinDictation platforms.

---

## Current Status

| Platform | Status | Build System | Notes |
|----------|--------|-------------|-------|
| **Windows** | 🔴 No code yet | .NET 8+ / `dotnet` CLI | WinUI 3 app — see [Windows v0 Design](../01_designs/01_win_design_v0.md) |
| **macOS** | 🔴 No code yet | Swift / Xcode / `xcodebuild` | Swift app — see [macOS v0 Design](../01_designs/02_mac_design_v0.md) |
| **iOS** | 🔴 Not started | Swift / Xcode | Custom keyboard extension — future |
| **Android** | 🔴 Not started | Kotlin / Gradle | Custom IME — future |

---

## Unified Deploy Script

All platforms share a single deployment entry point:

```
deploy/deploy.py
```

This script handles the full lifecycle for any platform:
1. **Prerequisites** — check and install required toolchains
2. **Build** — compile platform-specific binaries
3. **Install** — install or deploy to the target device/system

### CLI Design

```
python deploy/deploy.py <platform> [options]

Platforms:
  windows     Build and install the Windows tray app
  mac         Build and install the macOS app
  ios         Build the iOS keyboard extension (Xcode archive)
  android     Build the Android IME (Gradle APK)

Options:
  --build-only        Build without installing
  --install-only      Install without rebuilding (uses last build)
  --clean             Clean build artifacts before building
  --release           Build in Release configuration (default: Debug)
  --verbose           Show full build output
  --dry-run           Show what would be done without executing
```

### Design Principles

Inspired by the MarsinLED `deploy.py` pattern:

- **Single entry point** — one script for all platforms, dispatched by first argument
- **Phased execution** — prerequisites → build → install, each phase logged and tracked
- **Colored output** — clear visual feedback for success/failure at each step
- **Result tracking** — each step records success/failure, summary printed at end
- **Tee logging** — output goes to both terminal and a timestamped log file in `tmp/logs/`
- **Idempotent** — safe to run repeatedly; skips already-satisfied prerequisites
- **No silent failures** — every step reports its outcome clearly

### Platform-Specific Details

#### Windows

```
python deploy/deploy.py windows
```

Steps:
1. Check .NET 8+ SDK is installed
2. Check Windows App SDK workload
3. `dotnet restore` in `windows/`
4. `dotnet build` (or `dotnet publish` for release)
5. Register as startup app (optional, via settings)

Build output: `windows/MarsinDictation.App/bin/`

#### macOS

```
python deploy/deploy.py mac
```

Steps:
1. Check Xcode and Swift toolchain
2. `xcodebuild` with appropriate scheme
3. Copy `.app` to `/Applications/` (optional)

Build output: `mac/build/`

#### iOS

```
python deploy/deploy.py ios
```

Steps:
1. Check Xcode and iOS SDK
2. `xcodebuild archive` with provisioning profile
3. Export IPA for distribution or install via Xcode

Build output: `ios/build/`

#### Android

```
python deploy/deploy.py android
```

Steps:
1. Check Android SDK and Gradle
2. `./gradlew assembleDebug` (or `assembleRelease`)
3. `adb install` for local deployment

Build output: `android/app/build/outputs/apk/`

---

## Build Artifacts

All build artifacts must be gitignored. Platform-specific output locations:

| Platform | Build Output | Gitignored |
|----------|-------------|------------|
| Windows | `windows/**/bin/`, `windows/**/obj/` | ✅ |
| macOS | `mac/build/` | ✅ |
| iOS | `ios/build/` | ✅ |
| Android | `android/app/build/` | ✅ |
| Deploy logs | `tmp/logs/` | ✅ |

---

## Placeholder Note

> [!IMPORTANT]
> The `deploy/deploy.py` script does **not exist yet**. This document defines its intended design. Implementation will begin when the first platform (Windows) has buildable code. The script should follow the patterns established in the MarsinLED `deploy.py` (argparse-based CLI, phased execution, colored output, tee logging, result summary).
