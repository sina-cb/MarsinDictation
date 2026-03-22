# MarsinDictation — macOS

Native macOS dictation app. Hold **Control+Option** to record, release to transcribe and inject text at your cursor.

## Prerequisites

- **Xcode** (with Command Line Tools) — `xcode-select --install`
- **XcodeGen** — `brew install xcodegen`
- **LocalAI** running locally (or an OpenAI API key configured in `.env`)

## Quick Start

```bash
# From the repo root — regenerate project, build, and open in Xcode
python3 devtool/deploy.py mac

# Build and run WITHOUT Xcode UI
python3 devtool/deploy.py mac --build
open ~/Library/Developer/Xcode/DerivedData/MarsinDictation-*/Build/Products/Debug/MarsinDictation.app

# Only regenerate + open in Xcode (no build)
python3 devtool/deploy.py mac --run
```

### Running Without Xcode

You can build and launch entirely from the terminal — no Xcode window needed:

```bash
# 1. Build
python3 devtool/deploy.py mac --build

# 2. Launch the built app directly
open ~/Library/Developer/Xcode/DerivedData/MarsinDictation-*/Build/Products/Debug/MarsinDictation.app
```

The app runs as a menu bar icon. Hold **Control+Option** to dictate.

---

## Installation (DMG)

To install MarsinDictation as a proper macOS app in `/Applications`:

```bash
python3 devtool/deploy.py mac --install
```

This will:
1. Build a **Release** binary (ad-hoc signed)
2. Bundle your `.env` config into the app
3. Create a compressed DMG at `tmp/MarsinDictation.dmg`
4. **Install directly to `/Applications/MarsinDictation.app`**
5. Reset Accessibility so the app prompts on first launch
6. Auto-open the DMG (for backup/distribution)

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

Run `--install` again. It replaces the app in `/Applications`, resets Accessibility (you'll need to re-grant), and creates a fresh DMG.

### Clean Spotlight Duplicates

If you see multiple MarsinDictation entries in Spotlight after development builds:
```bash
# Remove DerivedData build copies
rm -rf ~/Library/Developer/Xcode/DerivedData/MarsinDictation-*/Build/Products/*/MarsinDictation.app
# Rebuild Spotlight index (requires password)
sudo mdutil -E /
```

### Regenerating the Icon

If you change `icon.png`, regenerate the app icon:

```bash
./devtool/build_icon.sh
python3 devtool/deploy.py mac --install
```

---

## Settings

Settings are available from the menu bar: **mic icon → Settings...**

| Setting | Storage | Default |
|---------|---------|---------|
| Transcription provider | UserDefaults | `localai` |
| Language | UserDefaults | `en` |
| LocalAI endpoint | UserDefaults | `http://localhost:3840` |
| LocalAI model | UserDefaults | `whisper-large-turbo` |
| OpenAI model | UserDefaults | `gpt-4o-mini-transcribe` |
| OpenAI API key | **Keychain** | *(empty)* |

On first run, settings are seeded from `.env` if present (one-time migration). After that, `.env` values serve as fallbacks only — in-app settings take priority.

---

## Signing Setup

The Xcode project (`.xcodeproj`) is **auto-generated** by [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml` and is **gitignored**. Code signing is configured via a `Local.xcconfig` file that is also gitignored — your personal team ID never enters the repo.

### First-Time Setup

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
   python3 devtool/deploy.py mac --install
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

| Context | Signing | Accessibility |
|---------|---------|---------------|
| `--install` | Ad-hoc (`-`) | Resets on each install; re-grant in System Settings |
| `--build` / default | Release, ad-hoc (`-`) | Same binary identity per build path |
| Xcode (⌘R) | Apple Development (from `Local.xcconfig`) | Persists across builds |

> **Note:** CLI builds use ad-hoc signing because macOS Keychain blocks CLI tools from accessing the Apple Development certificate's private key by default. Xcode has special keychain entitlements that bypass this. The `--install` flow compensates by running `tccutil reset Accessibility` so the app prompts cleanly on first launch.

---

## Accessibility Permission (Auto-Paste)

The app uses the system pasteboard + synthetic Cmd+V to inject text. This requires **Accessibility permission**.

### First Run

1. On first dictation, macOS will prompt to grant Accessibility access
2. Open **System Settings → Privacy & Security → Accessibility**
3. Toggle **MarsinDictation** to **ON**
4. Restart the app

### After Reinstall

Each `--install` resets Accessibility (new binary). You'll see "📋 ⌘V to paste" until you re-grant access. The `--install` command automatically runs `tccutil reset` to ensure a clean prompt.

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
| `MARSIN_TRANSCRIPTION_PROVIDER` | `localai` (default) or `openai` |
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
