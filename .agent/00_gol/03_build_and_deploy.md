# Build & Deploy — MarsinDictation

This document defines the build and deployment process for all MarsinDictation platforms.

---

## Current Status

| Platform | Status | Build System | Notes |
|----------|--------|-------------|-------|
| **Windows** | 🟡 Phase 0 | .NET 8+ / `dotnet` CLI | WPF tray app — see [Windows v0 Design](../01_designs/01_win_design_v0.md) |
| **macOS** | Implemented; 1.0.5/build 5 local API | Swift / XcodeGen / `xcodebuild` | Developer ID distribution; see [macOS guide](../../mac/README.md) |
| **iOS** | 🔴 Not started | Swift / Xcode | Custom keyboard extension — future |
| **Android** | 🔴 Not started | Kotlin / Gradle | Custom IME — future |

---

## Unified Deploy Script

All platforms share a single deployment entry point:

```
devtool/deploy.py
```

This script handles the full lifecycle for any platform:
1. **Prerequisites** — check and install required toolchains
2. **Build** — compile platform-specific binaries
3. **Install** — install or deploy to the target device/system

### CLI Design

The overview below describes the original cross-platform CLI design. For current macOS commands and destructive `--clean` behavior, use the macOS section below and `python3 devtool/deploy.py --help`.

```
python devtool/deploy.py <platform> [options]

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
  --hold              Keep terminal open and tail app logs in real-time
  --test              Build and run tests with evidence output
  --filter EXPR       Filter which tests to run (used with --test)
```

### Design Principles

Design principles:

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
python devtool/deploy.py windows
```

Steps:
1. Check .NET 8+ SDK is installed
2. Check Windows App SDK workload
3. `dotnet restore` in `windows/`
4. `dotnet build` (or `dotnet publish` for release)
5. Register as startup app (optional, via settings)

Build output: `windows/MarsinDictation.App/bin/`

#### macOS

**Operator install rule (2026-11-02):** The installed app must be Developer ID
Application signed, notarized, and accepted by Gatekeeper unless the user explicitly
requests a development build. Apple Development and ad-hoc builds are permitted for
compilation/testing; they do not fulfill a fully signed installation request.
Accessibility is a separate macOS permission and still needs user authorization.

```sh
# Development compilation; does not install
python3 devtool/deploy.py mac --build
# Distribution DMG; does not replace the installed app
python3 devtool/deploy.py mac --package
# Distribution packaging plus direct /Applications replacement
python3 devtool/deploy.py mac --install
```

macOS builds use Release. Packaging builds universal arm64/x86_64 into
`tmp/mac-build/`; the DMG is `tmp/MarsinDictation.dmg`. Distribution commands require
a Developer ID Application certificate and `APPLE_TEAM_ID`, `APPLE_ID_EMAIL`,
`APPLE_APP_SPECIFIC_PASSWORD`. They sign the app with hardened runtime/timestamp,
verify its signature, sign/notarize/staple/validate the DMG, and assess the DMG with
Gatekeeper. Failures stop packaging. `--local-sign` explicitly makes an ad-hoc,
unnotarized development package; never substitute it when distribution is requested.

When local distribution credentials are unavailable, use `.github/workflows/macos.yml`
with `workflow_dispatch` on the exact authorized branch, recording the run's full
commit SHA. Its signed-package job uses existing encrypted repository secrets and
uploads `MarsinDictation-macOS-signed-<SHA>`. Pull requests only validate/build;
trusted pushes to `main`/`dev/mac-*` and manual dispatch also package. No release or
tag is created. Check both validation and signed-package job results.

For an existing installation, prefer `--package` or the CI artifact, then follow the
[verified update procedure](../../mac/README.md#updating). Before replacing anything,
verify the DMG signature and stapled ticket, and the mounted app's Developer ID,
strict signature, version/build, and Gatekeeper acceptance. Keep one private rollback
copy, quit the old app/clients, replace only the app bundle, and verify the installed
copy and API. Preserve settings, Keychain, transcript history, and downloaded models.
The current `--install` path replaces the destination directly: it does not create a
rollback or explicitly assess the extracted app with Gatekeeper. Supply those checks
before replacement; do not treat packaging success alone as installation proof.

Remove only identified superseded app copies after successful verification; retain
one rollback outside indexed Applications folders. **Never use `mac --clean` to
clean up old installs**: it uninstalls the app and deletes Application Support
(including history/models), preferences, caches, and DerivedData.

#### iOS

```
python devtool/deploy.py ios
```

Steps:
1. Check Xcode and iOS SDK
2. `xcodebuild archive` with provisioning profile
3. Export IPA for distribution or install via Xcode

Build output: `ios/build/`

#### Android

```
python devtool/deploy.py android
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

> [!NOTE]
> The `devtool/deploy.py` script is implemented with Windows and macOS support. iOS and Android handlers are placeholder stubs. The script uses argparse-based CLI dispatch, phased execution, colored output, and result summaries.
