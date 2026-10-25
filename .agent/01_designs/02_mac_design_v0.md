# MarsinDictation — macOS v0 Design

> This document defines the v0 desktop implementation for macOS. It intentionally prioritizes speed, reliability, and low operational complexity over cross-platform code sharing.

---

## Vision

A small macOS menu bar app that does one thing well:

**hotkey → record → transcribe → inject text**

The user holds a hotkey, speaks naturally, releases the hotkey, and polished text appears at the user's cursor in most standard macOS text inputs, with recovery if direct injection fails.

---

## Non-Goals (v0)

- Sandbox gymnastics (distribute outside the App Store initially)
- App-specific formatting profiles
- Local embedded Python runtime
- Offline bundled model
- Command grammar ("make this formal", "summarize")
- Code-mode / email-mode / tone transforms
- Cross-platform shared runtime code

---

## Requirements & Environment Setup

### Prerequisites

| Dependency | Version | Purpose |
|-----------|---------|---------|
| Xcode | 15.0+ | Build and run the application |
| macOS | 13.0+ (Ventura) | Minimum deployment target |
| Swift | 5.9+ | Language version |
| LocalAI *(optional)* | Latest | Local transcription server (whisper.cpp backend) |

### Permissions

The app must handle these permissions correctly:

| Permission | Why | API / Mechanism |
|-----------|-----|-----------------|
| **Microphone** | Audio capture for dictation | `AVCaptureDevice.requestAccess(for: .audio)` — requested automatically on first use |

> [!NOTE]
> **Accessibility permission is needed for auto-paste only.** The Control+Option hotkey uses modifier-only detection via `flagsChanged` events, which macOS delivers to global monitors without Accessibility access. Accessibility is only required for synthetic Cmd+V (auto-paste via CGEvent). Without it, text copies to clipboard and HUD shows "📋 ⌘V to paste".

> [!NOTE]
> **Signing for persistent Accessibility.** With a proper Apple Development certificate + team ID in `Local.xcconfig`, Accessibility permission persists across rebuilds. With ad-hoc signing, it resets each rebuild.

### Transcription Providers (one or both)

| Provider | Requirement | Purpose |
|----------|------------|---------|
| **OpenAI** | `OPENAI_API_KEY` env var | Cloud transcription — best accuracy, requires internet |
| **LocalAI** | LocalAI server running locally | Local transcription via whisper.cpp — free, offline, private |

> [!NOTE]
> The local provider uses [LocalAI](https://localai.io), which exposes the same `/v1/audio/transcriptions` endpoint as OpenAI. Both providers use the same OpenAI-compatible transcription request shape. They may differ in base URL, auth requirements, and model availability. LocalAI supports multiple backends including `whisper.cpp`, `moonshine`, and `faster-whisper`.
>
> **Why not Ollama?** Ollama is out of scope for v0 because its documented primary APIs are text-generation-oriented, while this design standardizes on OpenAI-compatible audio transcription endpoints.

> [!CAUTION]
> **whisper.cpp in-process** is a last-resort fallback only. It requires bundling native binaries, adds build complexity, and changes the architecture from "HTTP client" to "embedded native inference." Do not pursue this path without explicit approval. If LocalAI does not meet local transcription needs, escalate before implementing direct whisper.cpp integration.

### Environment Variables

```bash
MARSIN_TRANSCRIPTION_PROVIDER=localai|openai    # default: localai
MARSIN_LANGUAGE=en                              # ISO 639-1 language code

OPENAI_API_KEY=sk-...                           # required if provider=openai
OPENAI_MODEL=gpt-4o-mini-transcribe             # or whisper-1 / gpt-4o-transcribe

LOCALAI_ENDPOINT=http://localhost:3840          # required if provider=localai
LOCALAI_MODEL=whisper-large-turbo               # Whisper model loaded in LocalAI
```

### Build & Run

```bash
# Using deploy.py — regenerate project, build, and open in Xcode
python3 devtool/deploy.py mac

# Build + launch WITHOUT Xcode UI (CLI-only workflow)
python3 devtool/deploy.py mac --build
open ~/Library/Developer/Xcode/DerivedData/MarsinDictation-*/Build/Products/Debug/MarsinDictation.app

# Or manually
cd mac
xcodegen generate --spec project.yml --project .
open MarsinDictation.xcodeproj
# Press ⌘R in Xcode to run
```

### Signing Setup

The project uses `Local.xcconfig` for signing configuration (gitignored to protect personal info):

```bash
# First-time setup
cp mac/Local.xcconfig.example mac/Local.xcconfig
# Edit Local.xcconfig with your team ID:
#   DEVELOPMENT_TEAM = YOUR_TEAM_ID
#   CODE_SIGN_IDENTITY = Apple Development
```

Without a certificate, the app works with ad-hoc signing (`CODE_SIGN_IDENTITY = -`).

---

## UX

### Default Hotkey

**`Control + Option` (hold)** — hold to record, release to stop and transcribe

> [!NOTE]
> Hold-to-record (walkie-talkie style) was chosen over toggle mode for a more natural interaction. The hotkey uses modifier-only detection via `flagsChanged` events, which requires no Accessibility permission.

### Recovery Hotkey

**`⌘⇧Z`** (Command+Shift+Z) — paste the last transcription

If text injection fails (unsupported app, locked text field, no focused cursor), the transcript is **not lost**. The user can switch to any text field and press `⌘⇧Z` to inject the most recent result. This also provides a general "paste last dictation" shortcut for workflows where the user dictates first and decides where to put it afterward.

### UI Elements

| Element | Description |
|---------|-------------|
| **Menu bar icon** | Persistent status item with dropdown menu (Settings, History, Quit) |
| **Recording HUD** | Small floating indicator — turns red/pulsing while recording |
| **Settings window** | Compact window for hotkey, language, provider, and preferences |
| **Transcript history** | Scrollable panel showing recent transcriptions with copy/re-inject |
| **Per-app exclusion list** | Allows disabling dictation in specific apps |

---

## Architecture

### Process Model

Single process: SwiftUI/AppKit shell with a menu bar presence and a background dictation service inside the same app.

### Module Structure

```
mac/
├── project.yml                               # XcodeGen project definition (source of truth)
├── Local.xcconfig                            # Personal signing config (gitignored)
├── Local.xcconfig.example                    # Template for contributors
├── MarsinDictation.xcodeproj                 # Generated — do NOT edit manually
├── MarsinDictationApp/                       # Application shell
│   ├── AppDelegate.swift                     # App lifecycle, .env loading, Accessibility check
│   ├── MarsinDictationApp.swift              # SwiftUI App entry point
│   ├── EnvLoader.swift                       # Parses .env into ProcessInfo environment
│   ├── StatusBarController.swift             # Menu bar icon & dropdown
│   ├── SettingsView.swift                    # Preferences window (placeholder)
│   └── RecordingHUD.swift                    # Floating toast popup (recording/transcribing/done)
│
├── Core/                                     # Core logic (no UI dependencies)
│   ├── Hotkey/
│   │   └── HotkeyManager.swift               # Control+Option hold + ⌘⇧Z recovery
│   ├── Audio/
│   │   ├── AudioCapture.swift                 # AVAudioEngine mic capture + WAV encoding
│   │   └── AudioGuard.swift                   # 25 MB upload limit enforcement
│   ├── Transcription/
│   │   ├── GenericTranscriptionClient.swift    # Single client for both providers
│   │   └── TranscriptionConfig.swift          # Endpoint, apiKey, model, language
│   ├── Processing/
│   │   └── TextPostProcessor.swift            # Filler removal, punctuation, cleanup
│   ├── Injection/
│   │   ├── PasteboardInjector.swift           # NSPasteboard + CGEvent Cmd+V (primary)
│   │   └── KeystrokeInjector.swift            # AppleScript keystroke fallback
│   ├── History/
│   │   └── TranscriptStore.swift              # Transcript storage with state tracking
│   └── DictationService.swift                 # Orchestrator: capture → transcribe → inject
│
├── MarsinDictation.entitlements
└── Info.plist
```

---

## Flow

```
┌──────────────────────────────────────────────────────────┐
│  1. Check foreground process against exclusion list      │
│     → If excluded: no-op with subtle notification        │
│  2. User presses and holds Control + Option              │
│  3. HotkeyManager receives flagsChanged event            │
│  4. DictationService.dictationHotkeyPressed()            │
│  5. AudioCapture begins AVAudioEngine recording          │
│  6. RecordingHUD appears (🔴 Recording... — pink dot)    │
│  7. AudioGuard monitors estimated WAV size               │
│     → Auto-stops if approaching 25 MB                    │
│  8. User speaks...                                       │
│  9. User releases Control + Option                       │
│     (or AudioGuard auto-stops at limit)                  │
│ 10. DictationService.dictationHotkeyReleased()           │
│ 11. AudioCapture produces WAV buffer (48kHz, mono, 16-bit) │
│ 12. RecordingHUD shows (⏳ Transcribing... — blue dot)   │
│ 13. GenericTranscriptionClient.transcribe(wav)           │
│     ├─ OpenAI:  POST /v1/audio/transcriptions            │
│     └─ LocalAI: POST /v1/audio/transcriptions            │
│     (language field set from MARSIN_LANGUAGE env var)     │
│ 14. TextPostProcessor.process(rawText)                   │
│     ├─ Strip filler words ("um", "uh", "like")           │
│     ├─ Fix punctuation & capitalization                  │
│     └─ Return cleaned text                               │
│ 15. Injection targets the CURRENTLY FOCUSED field        │
│     (not the field focused when recording started)       │
│ 16. Injection ladder (with pasteboard preservation):     │
│     ├─ Try: PasteboardInjector (Cmd+V)                   │
│     └─ Fallback: KeystrokeInjector (Unicode text events) │
│ 17. RecordingHUD shows (✔ Injected — green dot, 1.5s)   │
│ 18. If ALL injection fails:                              │
│     ├─ Store in TranscriptStore as "pending"             │
│     └─ HUD shows "📋 Copied to clipboard"                │
│ 19. TranscriptStore.save(transcript)                     │
└──────────────────────────────────────────────────────────┘
```

---

## Implementation Choices

### Hotkey — Single HotkeyManager

Use a single `HotkeyManager` that detects modifier-only key combinations via `flagsChanged` events. This approach does **not** require Accessibility permission.

```swift
// Control+Option pressed → start recording
let dictationCombo: NSEvent.ModifierFlags = [.control, .option]
// ⌘⇧Z (keyDown) → recovery paste
if event.keyCode == 6 && flags == [.command, .shift] { ... }
```

> [!NOTE]
> Using modifier-only hotkeys via `flagsChanged` was a deliberate choice to avoid Accessibility permission for hotkey detection. The `keyDown` global monitor requires Accessibility access, but `flagsChanged` does not. However, Accessibility IS needed for auto-paste (CGEvent Cmd+V injection).

### Audio — AVAudioEngine

Use `AVAudioEngine` for microphone capture. It is the right native path for low-latency audio input on macOS.

```swift
let engine = AVAudioEngine()
let inputNode = engine.inputNode
let format = inputNode.outputFormat(forBus: 0)

inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
    // accumulate PCM buffers
}

engine.prepare()
try engine.start()
```

### Transcription — OpenAI or LocalAI

Two providers behind `ITranscriptionClient`, both using the same `/v1/audio/transcriptions` endpoint shape:

| Provider | Endpoint | Pros | Cons |
|----------|----------|------|------|
| **OpenAI** | `POST /v1/audio/transcriptions` | Best accuracy, multiple models (whisper-1, gpt-4o-mini-transcribe, gpt-4o-transcribe) | Requires API key, costs money, needs internet |
| **LocalAI** | `POST /v1/audio/transcriptions` (local server) | Free, offline, private, supports whisper.cpp / faster-whisper backends | Requires LocalAI install, slower on weak hardware |

Because both providers expose the same OpenAI-compatible endpoint, `ITranscriptionClient` is a single HTTP client parameterized by base URL, auth, and model. The provider and model are selected via env var or settings UI.

### Upload Size Guard

OpenAI's speech-to-text API currently limits uploaded audio files to 25 MB. The `AudioGuard` module enforces this limit during recording. For v0, the behavior is:

- Monitor estimated encoded WAV size during recording
- Automatically stop recording before the upload would exceed 25 MB
- Send the captured audio as-is
- Show a notification: "Recording limit reached. Sending captured audio."

This same guard is applied to both providers for consistent UX.

### Injection — Ladder Strategy

Design for fallback from day one:

| Priority | Method | Mechanism | Why it might fail |
|----------|--------|-----------|-------------------|
| 1 | **Pasteboard paste** | `NSPasteboard` + synthetic `Cmd+V` | Pasteboard locked by another app |
| 2 | **Keystroke fallback** | Unicode-aware `CGEvent` text input | Some apps ignore synthetic events |

> [!WARNING]
> We do **not** use AX value-setting as the primary injection path for v0. Directly setting a field's value can overwrite the entire contents of a text control rather than insert at the current cursor position. Pasteboard paste is more consistent with user expectations for v0.

> [!IMPORTANT]
> **Pasteboard preservation:** Pasteboard-based injection must preserve and restore the user's previous pasteboard contents. After injection, the previous clipboard contents are restored after 500ms. A `changeCount` check prevents overwriting if something else modified the clipboard in the meantime. If restoration fails, injection should still proceed and the app should not crash.

> [!IMPORTANT]
> If both methods fail, the transcript is **not lost**. It is saved to `TranscriptStore` as "pending" and the user is notified. They can press **`⌘⇧Z`** at any time to re-attempt injection into the currently focused field.

### Recovery — `⌘⇧Z`

Handled by the same `HotkeyManager` (as a `keyDown` event with Command+Shift modifiers). When pressed:

1. Pop the most recent "pending" transcript from `TranscriptStore`
2. Run the injection ladder again against the currently focused element
3. If no pending transcript exists, re-inject the last successful transcript (pasteboard-style convenience)

### Focus Semantics

> [!IMPORTANT]
> Injection always targets the **currently focused field** at the time transcription completes, not the field that was focused when recording started. This is intentional: the user may switch apps while dictating, and the text should land wherever their cursor is when they're ready.

---

## Settings (v0)

| Setting | Default | Type |
|---------|---------|------|
| Dictation hotkey | `Control + Option` (hold) | Modifier combo |
| Recovery hotkey | `⌘⇧Z` (Command+Shift+Z) | Key combo |
| Transcription provider | `localai` | Enum: `localai` / `openai` |
| OpenAI API key | *(empty)* | String (secret) |
| OpenAI model | `gpt-4o-mini-transcribe` | Enum: `whisper-1` / `gpt-4o-mini-transcribe` / `gpt-4o-transcribe` |
| LocalAI endpoint | `http://localhost:3840` | URL |
| LocalAI model | `whisper-large-turbo` | String |
| Language | `en` | ISO 639-1 |
| Auto-punctuation | `on` | Boolean |
| Strip filler words | `on` | Boolean |
| Launch at login | `off` | Boolean |
| Local history | `on` | Boolean |

When launched at login, the app starts hidden and appears only in the menu bar unless the user explicitly opens the settings window.

> [!IMPORTANT]
> Secrets entered through the UI, such as the OpenAI API key, must **not** be stored in plain plist or JSON settings files. Use **Keychain Services**.

---

## Failure Modes

| Failure | User Experience |
|---------|----------------|
| Microphone permission denied | Alert explaining microphone access is required for dictation |
| No mic detected | HUD: "⚠ No microphone found" |
| Mic disconnects mid-recording | Recording stops gracefully; partial audio sent for transcription |
| Recording approaches 25 MB | Recording auto-stops. Notification: "Recording limit reached." |
| Transcription API unreachable | HUD: "⚠ Transcription failed" |
| Transcription returns empty | HUD: "⚠ No speech detected" |
| All injection methods fail | Transcript saved as pending. HUD: "📋 Copied to clipboard" |
| Excluded app is in foreground | Dictation no-ops |

---

## Acceptance Criteria

- [x] Dictation works end-to-end with Control+Option hold-to-record
- [x] LocalAI transcription works with whisper-large-turbo on localhost:3840
- [ ] OpenAI transcription works with valid API key
- [x] WAV upload path works end-to-end for both providers
- [x] Recordings exceeding 25 MB are handled gracefully (AudioGuard)
- [x] App correctly handles Microphone permission
- [x] No Accessibility permission required (modifier-only hotkeys)
- [x] Injection ladder falls through correctly when primary method fails
- [x] Injection targets focused field at transcription-complete time, not recording-start time
- [x] `Option + Z` successfully pastes pending/last transcript
- [x] Clear HUD notification for recording/transcribing/success/error states
- [ ] History panel shows recent transcripts with copy/re-inject
- [x] Menu bar icon and HUD are non-intrusive
- [ ] Settings persist across app restarts
- [x] Pasteboard contents are preserved/restored after injection
- [ ] Excluded apps are skipped with subtle notification
- [ ] OpenAI API key stored in Keychain, not plain plist

---

## Transcript State Model

Each transcript in `TranscriptStore` is a first-class object, not a boolean flag:

```json
{
  "id": "uuid",
  "createdAt": "2026-03-13T09:30:00Z",
  "text": "The transcribed and post-processed text",
  "provider": "openai",
  "model": "gpt-4o-mini-transcribe",
  "state": "success"
}
```

| State | Meaning |
|-------|---------|
| `success` | Transcribed and injected successfully |
| `pending` | Transcription succeeded but injection failed — recoverable via `⌘⇧Z`. This is the only injection-failure state; there is no separate `failed_injection`. |
| `failed_transcription` | Audio captured but the transcription API returned an error |

---

## Agent Implementation Notes

These are not blocking changes but rules the implementation must follow:

### Menu Bar Ownership

- Keep menu bar item ownership in the App layer only (`StatusBarController.swift`)
- Core must not know anything about menu bar APIs
- HUD and menu bar state should subscribe to service state, not drive it

### Pasteboard Preservation

1. Read current pasteboard contents → save to temp variable
2. Set pasteboard to transcribed text
3. Dispatch synthetic `Cmd+V`
4. Brief best-effort delay after paste dispatch before restoring
5. Restore saved pasteboard contents
6. If restoration fails: log warning, do not crash

### Unicode Text Fallback

For the typing fallback, use Unicode-aware event/text injection. Do not attempt to map every character to a hardware key code — that breaks for punctuation, non-English text, and symbols.

### Per-App Exclusion List

Before starting capture and before recovery injection, check the foreground app against the exclusion list:

1. Determine the frontmost running application
2. Compare against configured **bundle ID** (primary key). Fall back to process name only if bundle ID is unavailable.
3. If excluded: no-op with a subtle notification ("Dictation disabled for this app")

### Provider Capability Normalization

Not every provider/model supports the same response format. v0 should normalize all transcription responses to plain text output only. Do not rely on structured metadata or word-level timestamps from either provider.

### Provider API Reference

The standard OpenAI-compatible `/v1/audio/transcriptions` endpoint accepts `multipart/form-data` with a `file` field (WAV audio) and optional `model`/`language` fields. `Bearer` auth is used for OpenAI; LocalAI typically requires no auth. The macOS app calls the endpoint directly (no proxy needed).
