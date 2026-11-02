# MarsinDictation — macOS

Native macOS dictation app. The default English speech model is `ggml-base.en.bin` (about 148 MB). At launch, a missing model downloads automatically from Hugging Face with visible progress, then loads locally. Subsequent launches work offline. Failed downloads are retried on the next dictation; partial downloads are never installed. Model filename changes apply on the next dictation without restarting. The previous `large-v3-turbo` macOS default migrates to `base.en` to match this app's bundled model and older SwiftWhisper engine. Audio stays local with the embedded provider.

Native macOS dictation app. Hold **Control+Option** to record, release to transcribe and inject text at your cursor.

## Prerequisites

- **Xcode** (with Command Line Tools) — `xcode-select --install`
- **XcodeGen** — `brew install xcodegen`
- Internet access for the first model download (embedded transcription runs offline afterward)

## Quick Start

```bash
# From the repo root — regenerate project, build, and open in Xcode
python3 devtool/deploy.py mac

# Build and run WITHOUT Xcode UI
python3 devtool/deploy.py mac --build
open ~/Library/Developer/Xcode/DerivedData/MarsinDictation-*/Build/Products/Release/MarsinDictation.app

# Only regenerate + open in Xcode (no build)
python3 devtool/deploy.py mac --run
```

### Running Without Xcode

You can build and launch entirely from the terminal — no Xcode window needed:

```bash
# 1. Build
python3 devtool/deploy.py mac --build

# 2. Launch the built app directly
open ~/Library/Developer/Xcode/DerivedData/MarsinDictation-*/Build/Products/Release/MarsinDictation.app
```

The app runs as a menu bar icon. Hold **Control+Option** to dictate.

---

## Installation (DMG)

Installed distribution apps must be **Developer ID Application signed, notarized,
and accepted by Gatekeeper** unless the user explicitly requests a development
build. Apple Development/ad-hoc builds are for development and testing.

```bash
# Create a signed, notarized DMG without replacing an installed app
python3 devtool/deploy.py mac --package
# Package and install directly (see update safeguards below first)
python3 devtool/deploy.py mac --install
```

Both commands require a Developer ID Application certificate plus `APPLE_TEAM_ID`,
`APPLE_ID_EMAIL`, and `APPLE_APP_SPECIFIC_PASSWORD`. They create a universal Release
app and `tmp/MarsinDictation.dmg`, exclude developer `.env` files, verify the app
signature, and sign/notarize/staple/validate/Gatekeeper-assess the DMG. Missing
credentials or failed checks stop packaging. `--install` also replaces
`/Applications/MarsinDictation.app` and opens the DMG. `--local-sign` instead creates
an ad-hoc, unnotarized development package; use it only when explicitly requested.

### Post-Install

1. **Launch** from Spotlight (⌘Space → "MarsinDictation") or from `/Applications`
2. **Grant Accessibility** — On first dictation, macOS will prompt:
   - Open **System Settings → Privacy & Security → Accessibility**
   - Toggle **MarsinDictation** to **ON**
   - Restart the app
3. **Configure via Settings** — Click the mic icon in the menu bar → **Settings...**:
   - Switch between **LocalAI** and **OpenAI** providers
   - Set API key (stored securely in Keychain)
   - Configure endpoint, model, and language

### Updating

Use `--package` or a signed CI artifact so verification precedes replacement.
The current `--install` command does not save a rollback or explicitly Gatekeeper-assess
the extracted app; perform these safeguards yourself:

1. Record the source commit, artifact/run, app version/build, and Developer ID team.
   Verify the DMG with `codesign --verify --strict`, `xcrun stapler validate`, and
   `spctl --assess --type open --context context:primary-signature --verbose=2`.
2. Mount the DMG read-only. Check the contained app with `codesign --display --verbose=4`
   (Developer ID Application authority and expected TeamIdentifier),
   `codesign --verify --deep --strict`, and
   `spctl --assess --type execute --verbose=2`. Require acceptance from a notarized
   Developer ID source and confirm the intended version/build before replacement.
3. Quit dependent API clients and the running app. Keep one private rollback copy
   outside indexed Applications folders, then replace only `/Applications/MarsinDictation.app`.
   Preserve UserDefaults/preferences, Keychain, Application Support/history, and model files.
4. Recheck the installed bundle's signature, Gatekeeper acceptance, and version/build;
   launch that exact path and verify API health/version and a fixture transcription.
   Accessibility and microphone permissions remain separate OS checks.

### Clean Spotlight Duplicates

After the replacement passes verification, remove only identified superseded
MarsinDictation `.app` copies (including old DerivedData build copies). Keep the active
`/Applications` app and one private rollback. Confirm each path before deletion;
do not delete user storage. Never use `python3 devtool/deploy.py mac --clean` for
old-install cleanup: it deletes the app, settings, history/models, caches, and DerivedData.

### Regenerating the Icon

If you change `icon.png`, regenerate the app icon:

```bash
./devtool/build_icon.sh
python3 devtool/deploy.py mac --package
```

---

## Settings

Settings are available from the menu bar: **mic icon → Settings...**

| Setting | Storage | Default |
|---------|---------|---------|
| Transcription provider | UserDefaults | `embedded` |
| Language | UserDefaults | `en` |
| LocalAI endpoint | UserDefaults | `http://localhost:3840` |
| LocalAI model | UserDefaults | `whisper-large-turbo` |
| OpenAI model | UserDefaults | `gpt-4o-mini-transcribe` |
| OpenAI API key | **Keychain** | *(empty)* |

On first run, settings are seeded from `.env` if present (one-time migration). After that, `.env` values serve as fallbacks only — in-app settings take priority.

---

## Signing Setup

The Xcode project (`.xcodeproj`) is **auto-generated** by [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml` and is **gitignored**. Code signing is configured via a `Local.xcconfig` file that is also gitignored — your personal team ID never enters the repo.

### Development Signing Setup

1. **Copy the example config:**

   ```bash
   cp mac/Local.xcconfig.example mac/Local.xcconfig
   ```

2. **Edit `mac/Local.xcconfig`** with your Apple Development Team ID:

   ```
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   CODE_SIGN_IDENTITY = Apple Development
   ```

3. **Build the project** — the deploy script runs XcodeGen automatically:

   ```bash
   python3 devtool/deploy.py mac --build
   ```

> **Note:** Without `Local.xcconfig`, builds will still work but use ad-hoc signing. Xcode UI builds require `Local.xcconfig` to resolve automatic signing.

### Finding Your Team ID

```bash
# List signing identities
security find-certificate -a -c "Apple Development" -p ~/Library/Keychains/login.keychain-db | \
  openssl x509 -noout -subject | grep OU
```

The `OU=` value is your team ID (e.g., `ABC1234DEF`).

### Creating an Apple Development Certificate

If you don't have one:

1. Open **Xcode → Settings (⌘,) → Accounts**
2. Click **+** → **Apple ID** → sign in (free Apple ID works)
3. Select your account → click **"Manage Certificates..."**
4. Click **+** → **Apple Development**

### Build Signing Behavior

| Context | Signing | Installation use |
|---------|---------|------------------|
| `--package` / `--install` | Developer ID Application; notarized DMG | Distribution; verify extracted/installed app too |
| `--package --local-sign` / `--install --local-sign` | Ad-hoc (`-`), no notarization | Explicit development use only |
| `--build` / default / Xcode | Release CLI build; signing from project/`Local.xcconfig` | Development compilation/testing |

Accessibility is an OS permission independent of notarization. Development apps can
also receive it. A stable signing identity helps preserve trust across updates;
a changed identity or ad-hoc replacement may require granting access again. The
installer does not reset permissions, and signing does not grant them automatically.


---

## Accessibility Permission (Auto-Paste)

The app uses the system pasteboard + synthetic Cmd+V to inject text. This requires **Accessibility permission**.

### First Run

1. On first dictation, macOS will prompt to grant Accessibility access
2. Open **System Settings → Privacy & Security → Accessibility**
3. Toggle **MarsinDictation** to **ON**
4. Restart the app

### After Reinstall

If an update changes the app's signing identity, macOS may require access again. The app requests Accessibility access at every untrusted launch; a saved prompt flag no longer suppresses the request. Use **Enable Auto-Paste…** in the menu or Settings to reopen the Accessibility pane. Enable the app in `/Applications`, then quit and reopen it.

---

## Project Regeneration

The Xcode project is generated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen). **Do not edit `.xcodeproj` manually** — it will be overwritten.

```bash
# Regenerate after adding/removing files or changing project settings
xcodegen generate --spec mac/project.yml --project mac/

# Or use the deploy tool
python3 devtool/deploy.py mac --build
```

### When to Regenerate

- After adding or removing `.swift` files
- After modifying `project.yml` (targets, schemes, entitlements, etc.)
- After changing launch arguments or build settings

## Project Structure

```
mac/
├── project.yml                 # XcodeGen project definition (source of truth)
├── Local.xcconfig              # Personal signing config (gitignored)
├── Local.xcconfig.example      # Template for Local.xcconfig
├── Info.plist                  # App metadata (LSUIElement, permissions)
├── MarsinDictation.entitlements
├── Core/                       # Business logic (no UI dependencies)
│   ├── Audio/                  # AudioCapture, AudioGuard
│   ├── History/                # TranscriptStore
│   ├── Hotkey/                 # HotkeyManager (Control+Option hold)
│   ├── Injection/              # PasteboardInjector, KeystrokeInjector
│   ├── Processing/             # TextPostProcessor
│   ├── Transcription/          # GenericTranscriptionClient, ITranscriptionClient
│   └── DictationService.swift  # Main orchestrator
└── MarsinDictationApp/         # UI layer (SwiftUI + AppKit)
    ├── AppDelegate.swift       # App entry point, .env loading, Accessibility check
    ├── EnvLoader.swift         # Parses .env file into environment
    ├── MarsinDictationApp.swift
    ├── RecordingHUD.swift      # Floating toast popup (recording/transcribing/done)
    ├── SettingsView.swift      # Settings window (placeholder)
    └── StatusBarController.swift # Menu bar icon
```

## Configuration

All settings are in the root `.env` file (see `.env.example`):

| Setting | Description |
|---------|-------------|
| `MARSIN_TRANSCRIPTION_PROVIDER` | `embedded` (default) or `openai` |
| `MARSIN_LANGUAGE` | ISO 639-1 code, e.g. `en` |
| `LOCALAI_ENDPOINT` | LocalAI server URL |
| `LOCALAI_MODEL` | Whisper model name |

## Hotkeys

| Action | Hotkey |
|--------|--------|
| **Dictation** | Hold **Control+Option** (⌃⌥) |
| **Recovery paste** | **⌘⇧Z** (Command+Shift+Z) |

- The dictation hotkey uses modifier-only detection via `flagsChanged` events — **no Accessibility permission** required for hotkeys
- Accessibility permission is only needed for **auto-paste** (injecting text via CGEvent Cmd+V)
- The recovery hotkey re-injects the last transcription at the current cursor

## Debug Options

### Audio Playback

To hear the recorded audio after each dictation (for debugging):

1. In Xcode: **Product → Scheme → Edit Scheme → Run → Arguments**
2. Enable `-debug-playback` (already configured in `project.yml`, disabled by default)

Or edit `project.yml`:

```yaml
schemes:
  MarsinDictation:
    run:
      commandLineArguments:
        "-debug-playback": true   # Toggle audio playback
```

Then regenerate with `python3 devtool/deploy.py mac --build`.

## Customization

### Changing the Hotkey

Edit `mac/Core/Hotkey/HotkeyManager.swift`. The dictation combo is defined as:

```swift
let dictationCombo: NSEvent.ModifierFlags = [.control, .option]
```

### Adding New Source Files

1. Add the `.swift` file to the appropriate directory (`Core/` or `MarsinDictationApp/`)
2. Regenerate the project: `python3 devtool/deploy.py mac --build`
3. Reopen in Xcode if using Xcode UI

### Changing App Settings

Edit `project.yml` then regenerate with `python3 devtool/deploy.py mac --build`.

## Model regression tests

Run `python3 devtool/test_mac_models.py` from the repository root. Tests use a local HTTP fixture and temporary directories to verify download, offline cache reuse, corrupt-cache replacement, retry, invalid payloads, and filename validation. To include real offline transcription, set `MODEL_TEST_REAL_MODEL` to a base.en model and `MODEL_TEST_AUDIO` to a synthetic mono 16-bit PCM WAV file. Microphone capture, global hotkeys and pasting remain OS integration checks.

## Signed distribution builds

The `macOS validation and signed package` workflow runs regression tests and a universal Intel/Apple Silicon build on pull requests. Trusted pushes to `main` or `dev/mac-*`, and manual `workflow_dispatch` on the selected branch, also build a Developer ID signed DMG, submit it to Apple, staple and validate its notarization ticket, and check Gatekeeper acceptance before uploading the installer artifact. No GitHub release or tag is created by this workflow. When using CI to install a branch build, record the run's full commit SHA, require both jobs to pass, and download `MarsinDictation-macOS-signed-<SHA>` from that run. The existing encrypted repository secrets supply signing/notarization credentials; do not expose or copy their values into documentation. Follow the update checks above before replacing the installed app.

For signed local packaging, set `APPLE_TEAM_ID`, `APPLE_ID_EMAIL`, and `APPLE_APP_SPECIFIC_PASSWORD`, install a Developer ID Application certificate, then run `python3 devtool/deploy.py mac --package`. Missing credentials or any failed signing/notarization step stops packaging. Use `--local-sign` only for development packages, which are not notarized. Distribution packages never embed developer `.env` files.

## Local upload API (1.0.5)

While the menu bar app runs, native clients can use `http://127.0.0.1:6976/health` and upload normalized WAV to `/transcribe`. The API uses an existing local embedded model independently of the desktop provider and shares inference with hotkeys. It never downloads models or captures, injects, or stores user content. See [the API/build/update guide](../docs/mac-local-api.md).
