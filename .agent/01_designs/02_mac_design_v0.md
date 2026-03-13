# MarsinDictation — macOS v0 Design

> This document defines the v0 desktop implementation for macOS. It intentionally prioritizes speed, reliability, and low operational complexity over cross-platform code sharing.

---

## Vision

A small macOS menu bar app that does one thing well:

**hotkey → record → transcribe → inject text**

The user presses a hotkey, speaks naturally, presses the hotkey again, and polished text appears at the user's cursor in most standard macOS text inputs, with recovery if direct injection fails.

---

## Non-Goals (v0)

- Hold-to-talk with low-level keyboard hook
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
| **Microphone** | Audio capture for dictation | `AVCaptureDevice.requestAccess(for: .audio)` or equivalent AVFoundation permission flow |
| **Accessibility** | Global hotkey monitoring and synthetic input into other apps | `AXIsProcessTrustedWithOptions` + user-guided System Settings flow |

> [!IMPORTANT]
> Without Accessibility permission, the app cannot reliably monitor global hotkeys or inject text into other applications. The app must guide the user through enabling this in System Settings → Privacy & Security → Accessibility.

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
MARSIN_TRANSCRIPTION_PROVIDER=openai|localai
OPENAI_API_KEY=sk-...                          # required if provider=openai
OPENAI_MODEL=gpt-4o-mini-transcribe            # or whisper-1 / gpt-4o-transcribe

LOCALAI_ENDPOINT=http://localhost:8080         # required if provider=localai
LOCALAI_MODEL=whisper-1
```

### Build & Run

```bash
cd mac
open MarsinDictation.xcodeproj
# or
xcodebuild -scheme MarsinDictation -configuration Debug build
```

---

## UX

### Default Hotkey

**`Control + Option + Space`** — toggle dictation on/off

> [!NOTE]
> Toggle mode avoids extra complexity around key-up tracking and makes the v0 interaction consistent with Windows.

### Recovery Hotkey

**`Option + Shift + Z`** — paste the last transcription

If text injection fails (unsupported app, locked text field, no focused cursor), the transcript is **not lost**. The user can switch to any text field and press `Option + Shift + Z` to inject the most recent result. This also provides a general "paste last dictation" shortcut for workflows where the user dictates first and decides where to put it afterward.

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
├── MarsinDictation.xcodeproj
├── MarsinDictationApp/                       # Application shell
│   ├── AppDelegate.swift                     # App lifecycle, permission guidance
│   ├── StatusBarController.swift             # Menu bar icon & dropdown
│   ├── SettingsView.swift                    # Preferences window
│   └── RecordingHUD.swift                    # Floating recording indicator
│
├── Core/                                     # Core logic framework
│   ├── Hotkey/
│   │   └── HotkeyManager.swift               # Both dictation + recovery hotkeys
│   ├── Audio/
│   │   ├── AudioCapture.swift                # AVAudioEngine mic capture
│   │   ├── WavEncoder.swift                  # PCM → WAV encoding
│   │   └── AudioGuard.swift                  # 25 MB upload limit enforcement
│   ├── Transcription/
│   │   ├── ITranscriptionClient.swift        # Abstraction protocol
│   │   ├── OpenAITranscriptionClient.swift   # OpenAI /v1/audio/transcriptions
│   │   └── LocalAITranscriptionClient.swift  # LocalAI /v1/audio/transcriptions
│   ├── Processing/
│   │   └── TextPostProcessor.swift           # Filler removal, punctuation, cleanup
│   ├── Injection/
│   │   ├── ITextInjector.swift               # Abstraction protocol
│   │   ├── PasteboardInjector.swift          # NSPasteboard + Cmd+V (primary)
│   │   └── KeystrokeInjector.swift           # CGEvent Unicode text fallback
│   ├── History/
│   │   └── TranscriptStore.swift             # Transcript storage with state tracking
│   └── DictationService.swift                # Orchestrator: capture → transcribe → inject
│
├── Tests/
│   └── CoreTests/
│       ├── HotkeyTests.swift
│       ├── InjectionTests.swift
│       └── TranscriptionTests.swift
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
│  2. User presses Control + Option + Space                │
│  3. HotkeyManager receives hotkey event                  │
│  4. DictationService.startCapture()                      │
│  5. AudioCapture begins AVAudioEngine recording          │
│  6. RecordingHUD appears (red / pulsing)                 │
│  7. AudioGuard monitors estimated WAV size               │
│     → Auto-stops if approaching 25 MB                    │
│  8. User speaks...                                       │
│  9. User presses Control + Option + Space again          │
│     (or AudioGuard auto-stops at limit)                  │
│ 10. DictationService.stopCapture()                       │
│ 11. WavEncoder produces WAV buffer                       │
│ 12. ITranscriptionClient.transcribe(wav)                 │
│     ├─ OpenAI:  POST /v1/audio/transcriptions            │
│     └─ LocalAI: POST /v1/audio/transcriptions            │
│ 13. TextPostProcessor.process(rawText)                   │
│     ├─ Strip filler words ("um", "uh", "like")           │
│     ├─ Fix punctuation & capitalization                  │
│     └─ Return cleaned text                               │
│ 14. Injection targets the CURRENTLY FOCUSED field        │
│     (not the field focused when recording started)       │
│ 15. Injection ladder (with pasteboard preservation):     │
│     ├─ Backup user's pasteboard contents                 │
│     ├─ Try: PasteboardInjector (Cmd+V)                   │
│     ├─ Restore previous pasteboard (best-effort)         │
│     └─ Fallback: KeystrokeInjector (Unicode text events) │
│ 16. If ALL injection fails:                              │
│     ├─ Store in TranscriptStore as "pending"             │
│     └─ Notification: "Text saved. Press ⌥⇧Z to paste."  │
│ 17. TranscriptStore.save(transcript)                     │
└──────────────────────────────────────────────────────────┘
```

---

## Implementation Choices

### Hotkey — Single HotkeyManager

Use a single `HotkeyManager` for v0 that handles both hotkey IDs and routes by action. The implementation may use a global event monitor / event tap approach, but the rest of the app should depend only on the manager abstraction.

> [!IMPORTANT]
> The app must detect missing Accessibility trust and guide the user to enable it before attempting features that rely on global hotkeys or synthetic input.

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
> **Pasteboard preservation:** Pasteboard-based injection must preserve and restore the user's previous pasteboard contents on a best-effort basis. If the pasteboard is unavailable or restoration fails, injection should still proceed and the app should not crash.

> [!IMPORTANT]
> If both methods fail, the transcript is **not lost**. It is saved to `TranscriptStore` as "pending" and the user is notified. They can press **`Option + Shift + Z`** at any time to re-attempt injection into the currently focused field.

### Recovery — `Option + Shift + Z`

Handled by the same `HotkeyManager` (second registered action). When pressed:

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
| Dictation hotkey | `Control + Option + Space` | Key combo |
| Recovery hotkey | `Option + Shift + Z` | Key combo |
| Transcription provider | `openai` | Enum: `openai` / `localai` |
| OpenAI API key | *(empty)* | String (secret) |
| OpenAI model | `gpt-4o-mini-transcribe` | Enum: `whisper-1` / `gpt-4o-mini-transcribe` / `gpt-4o-transcribe` |
| LocalAI endpoint | `http://localhost:8080` | URL |
| LocalAI model | `whisper-1` | String |
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
| Accessibility not granted | Alert with button to open System Settings → Privacy & Security → Accessibility |
| Microphone permission denied | Alert explaining microphone access is required for dictation |
| No mic detected | Notification: "No microphone found. Check your audio settings." |
| Mic disconnects mid-recording | Recording stops gracefully; partial audio sent for transcription |
| Recording approaches 25 MB | Recording auto-stops. Notification: "Recording limit reached. Sending captured audio." |
| Transcription API unreachable | Notification: "Transcription failed. Check your provider connection/settings." |
| Transcription returns empty | Notification: "No speech detected. Try again." |
| All injection methods fail | Transcript saved as pending. Notification: "Press ⌥⇧Z to paste." |
| Excluded app is in foreground | Dictation no-ops with subtle notification |

---

## Acceptance Criteria

- [ ] Dictation works end-to-end in: **Notes, TextEdit, browser textareas, Slack, VS Code**
- [ ] OpenAI transcription works with valid API key
- [ ] LocalAI transcription works with local LocalAI server running
- [ ] WAV upload path works end-to-end for both providers
- [ ] Recordings exceeding 25 MB are handled gracefully
- [ ] App correctly handles Microphone and Accessibility permissions
- [ ] Injection ladder falls through correctly when primary method fails
- [ ] Injection targets focused field at transcription-complete time, not recording-start time
- [ ] `Option + Shift + Z` successfully pastes pending/last transcript
- [ ] Clear error notification if transcription fails
- [ ] History panel shows recent transcripts with copy/re-inject
- [ ] Menu bar icon and HUD are non-intrusive
- [ ] Settings persist across app restarts
- [ ] Pasteboard contents are preserved/restored after injection
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
| `pending` | Transcription succeeded but injection failed — recoverable via `Option+Shift+Z`. This is the only injection-failure state; there is no separate `failed_injection`. |
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

### Prior Internal Reference

The existing MarsinHome mobile app uses this exact API shape as a working reference. Its GOL server `transcribe.js` route converts base64 audio → `multipart/form-data` → `POST /v1/audio/transcriptions` with Bearer auth. The macOS app will call the endpoint directly (no proxy needed). See `MarsinHome/central_server/src/routes/transcribe.js` for the working implementation.
