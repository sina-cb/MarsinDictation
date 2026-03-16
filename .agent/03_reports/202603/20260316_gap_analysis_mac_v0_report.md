# Report: Gap Analysis — macOS v0 — 2026-03-16

## Summary

This report maps the current macOS codebase against the macOS v0 design (`02_mac_design_v0.md`). Analysis based on **direct source code audit** of all files in `mac/`, `devtool/`, and project configuration. Includes **open-source readiness** review.

---

## Work Completed (Verified in Source)

### Phase 0: Bootstrap & Walking Skeleton ✅
- XcodeGen project (`project.yml` → `.xcodeproj`)
- Menu bar icon (`StatusBarController.swift` with SF Symbols `mic.fill`)
- App runs hidden via `LSUIElement = true` + `.accessory` activation policy
- `HotkeyManager` with `NSEvent` global/local monitors — Control+Option hold-to-record
- `.env` file loading via `EnvLoader.swift` (bundle Resources → cwd traversal → fallback)
- `RecordingHUD` floating toast (`NSPanel`, non-activating, bottom-center)
- Transcript state model (`Transcript`, `TranscriptStore`) with persistence
- `deploy.py mac` — regenerate, build, open
- `Local.xcconfig` for personal signing (gitignored) + `Local.xcconfig.example` template
- CLI-only workflow: `deploy.py mac --build` + `open .app`

### Phase 1: Core App Infrastructure ✅
- Control+Option hold starts recording, release stops + transcribes
- Recovery hotkey: ⌘⇧Z (Command+Shift+Z) re-injects last/pending transcript
- RecordingHUD toast states: recording (pink), transcribing (blue), success (green), error (yellow)
- Menu bar icon changes during recording (`mic.fill` → `mic.circle.fill`)
- Mic permission pre-requested at startup

### Phase 2: Audio Capture ✅
- AVAudioEngine microphone capture (`AudioCapture.swift`)
- PCM float32 → int16 downmix with proper WAV header encoding
- WAV header uses actual hardware sample rate (48kHz)
- AudioGuard (25 MB upload-size limit — auto-stop before exceeding)
- Debug audio playback gated behind `-debug-playback` launch argument

### Phase 3: Transcription ✅
- `GenericTranscriptionClient` — one client for both providers (OpenAI-compatible endpoint)
- LocalAI transcription working with `whisper-large-turbo` on `localhost:3840`
- OpenAI transcription support with configurable API key and model
- Language selection (defaults to `en`)

### Phase 4: Injection ✅
- `PasteboardInjector` — NSPasteboard + CGEvent Cmd+V (primary, requires Accessibility)
- `KeystrokeInjector` — AppleScript `keystroke` fallback (Unicode-safe)
- Pasteboard save/restore after injection (500ms delay, `changeCount` check)
- Accessibility check — auto-paste when granted, clipboard fallback when not
- Recovery hotkey (⌘⇧Z) re-runs injection with pending/last transcript

### Phase 5 (Partial): Settings & Distribution ✅
- **Settings UI** (`SettingsView.swift`) — provider picker, LocalAI/OpenAI config, SecureField for API key, language, hotkey display
- **SettingsManager** — UserDefaults (preferences) + Keychain (API keys) + env var fallback
- **Keychain for API keys** — OpenAI API key stored in Keychain, not `.env`
- **EnvLoader migration** — seeds SettingsManager from `.env` on first run
- **DMG installer** (`deploy.py mac --install`) — Release build, direct install to `/Applications`, tccutil reset, DMG creation
- **Custom app icon** — `AppIcon.icns` from `icon.png` via `build_icon.sh`
- **Build fail-fast** — `--install` aborts on build failure (no stale DMG)

---

## Remaining Gaps (vs Design)

### Missing: Per-App Exclusion List
- `HotkeyManager.isForegroundAppExcluded(exclusionList:)` exists but always receives an empty list
- No UI for configuring excluded apps

### Missing: History Panel
- `TranscriptStore` persists transcripts but has no browsable UI
- Design specifies scrollable panel with copy/re-inject

### Missing: TextPostProcessor (Minimal)
- `TextPostProcessor.swift` exists but likely minimal
- Whisper models handle most cleanup — low impact

### Missing: Launch at Login
- Not implemented — design specifies starting hidden at login

### Missing: Settings Toggles
- No auto-punctuation or filler word stripping toggles in Settings UI

### Design Deviation: Recovery Hotkey
- Design: `Option+Z` → Implementation: `⌘⇧Z` (user preference)
- ⌘⇧Z conflicts with "Redo" in most apps

### Design Deviation: CLI Signing
- Design expected Apple Development signing for persistent Accessibility
- macOS Keychain blocks CLI codesign — `--install` uses ad-hoc + tccutil reset

---

## Code Review Findings

### Security ✅

| Check | Status | Detail |
|-------|--------|--------|
| No API keys in source | ✅ | API keys referenced via env vars and Keychain only |
| No personal info in tracked files | ✅ | `Local.xcconfig` gitignored; `project.pbxproj` regenerated clean |
| Keychain for secrets | ✅ | `KeychainHelper` uses `kSecClassGenericPassword` with `kSecAttrAccessibleWhenUnlocked` |
| SecureField for API key input | ✅ | `SettingsView.swift` uses `SecureField` |
| `.env` gitignored | ✅ | Only `.env.example` tracked (no real keys) |
| No hardcoded user paths | ✅ | No `/Users/...` paths in any source file |
| No personal team ID in tracked files | ✅ | Scrubbed from `project.pbxproj` and README |

### Code Quality

| Check | Status | Detail |
|-------|--------|--------|
| Clean module boundaries | ✅ | Core/ has no UI dependencies; App layer wraps SwiftUI/AppKit |
| Error handling | ✅ | Transcription errors caught and displayed via HUD |
| Memory management | ✅ | `[weak self]` in closures, no retain cycles observed |
| Thread safety | ⚠️ | `SettingsManager` published properties mutated on main thread via SwiftUI, but `buildTranscriptionConfig()` called from async Task — potential race |
| Debug prints in production | ⚠️ | Multiple `print("[DictationService]")` statements remain — should use `os_log` or compile-out for Release |
| Pasteboard restoration | ✅ | Saved/restored with `changeCount` check and 500ms delay |

### Files Reviewed

| File | Lines | Notes |
|------|-------|-------|
| `SettingsManager.swift` | 169 | Clean. Keychain helper is well-implemented. |
| `SettingsView.swift` | 166 | Clean. `SecureField` for API key. `LabeledField` reusable component. |
| `StatusBarController.swift` | 80 | Fixed: now uses direct `NSWindow` instead of unreliable `showSettingsWindow:` selector. |
| `DictationService.swift` | ~180 | Functional. Config reads from `SettingsManager`. Debug prints should be removed for release. |
| `HotkeyManager.swift` | ~85 | Clean. `flagsChanged` for modifier-only detection. |
| `AudioCapture.swift` | ~100 | Clean. Proper WAV encoding. |
| `PasteboardInjector.swift` | ~60 | Clean. Pasteboard save/restore with verification. |
| `KeystrokeInjector.swift` | ~40 | Clean. AppleScript fallback. |
| `EnvLoader.swift` | ~57 | Clean. Bundle → cwd → fallback chain. Seeds SettingsManager. |
| `GenericTranscriptionClient.swift` | ~74 | Clean. Bearer auth only when API key present. |
| `RecordingHUD.swift` | ~150 | Clean. Non-activating NSPanel with animation. |
| `AppDelegate.swift` | ~28 | Clean. Accessibility check at startup. |
| `project.yml` | 47 | Clean. No personal info. `Local.xcconfig` referenced for signing. |
| `deploy.py` (mac section) | ~100 | Clean. Fail-fast on build errors. Direct install to /Applications. |

### .gitignore Coverage

| Item | Gitignored | Notes |
|------|:---:|-------|
| `.env` | ✅ | Real keys never committed |
| `Local.xcconfig` | ✅ | Personal team ID protected |
| `xcuserdata/` | ✅ | Added for `.xcodeproj` |
| `xcshareddata/` | ✅ | Added |
| `*.orig`, `*.rej`, `*.patch` | ✅ | Added |
| `tmp/` | ✅ | DMG and build artifacts |
| `DerivedData/` | ✅ | Xcode build output |

---

## Summary Table

| Component | Design | Code |
|-----------|:---:|:---:|
| SwiftUI/AppKit Menu Bar App | ✅ | ✅ |
| Hold-to-Record Hotkey (Control+Option) | ✅ | ✅ |
| Recovery Hotkey (⌘⇧Z) | ✅ | ✅ |
| AVAudioEngine Capture | ✅ | ✅ |
| WAV Encoding (48kHz, mono, 16-bit) | ✅ | ✅ |
| AudioGuard (25 MB limit) | ✅ | ✅ |
| LocalAI Transcription | ✅ | ✅ |
| OpenAI Transcription | ✅ | ✅ (untested) |
| PasteboardInjector (Cmd+V) | ✅ | ✅ |
| KeystrokeInjector (AppleScript) | ✅ | ✅ |
| Pasteboard Save/Restore | ✅ | ✅ |
| Accessibility Auto-Paste | ✅ | ✅ |
| Clipboard Fallback | ✅ | ✅ |
| TranscriptStore (persistence) | ✅ | ✅ |
| RecordingHUD Overlay | ✅ | ✅ |
| Settings UI (provider, API key, model) | ✅ | ✅ |
| Keychain for API Keys | ✅ | ✅ |
| SettingsManager (UserDefaults + Keychain) | ✅ | ✅ |
| DMG Installer (--install) | ✅ | ✅ |
| Custom App Icon (.icns) | ✅ | ✅ |
| Code Signing (Local.xcconfig) | ✅ | ✅ |
| CLI Build + Launch | ✅ | ✅ |
| DictationService Orchestrator | ✅ | ✅ |
| TextPostProcessor | ✅ | 🚧 Minimal |
| Per-App Exclusion List | ✅ | ❌ Not implemented |
| History Panel | ✅ | ❌ Not implemented |
| Launch at Login | ✅ | ❌ Not implemented |
| Settings: toggle auto-punctuation | ✅ | ❌ Not in UI |
| Settings: toggle filler word stripping | ✅ | ❌ Not in UI |

---

## Open Source Readiness ✅

| Check | Status |
|-------|--------|
| No leaked API keys or secrets | ✅ |
| No personal team IDs in tracked files | ✅ |
| No hardcoded user-specific paths | ✅ |
| `.gitignore` covers all sensitive files | ✅ |
| `.env.example` provided (no real keys) | ✅ |
| `Local.xcconfig.example` provided | ✅ |
| README with setup, build, and install instructions | ✅ |
| License file | ❓ Not checked |

---

## Recommendations

1. **Before public release:** Add a LICENSE file (MIT/Apache 2.0) and verify no other personal info exists in commit history
2. **Polish:** Replace `print()` debug statements with `os_log` or `#if DEBUG` guards
3. **Thread safety:** Add `@MainActor` to `SettingsManager` or dispatch config reads to main thread
4. **Usability:** History panel — transcripts are stored but not browsable
5. **Nice-to-have:** Per-app exclusion list, launch at login
