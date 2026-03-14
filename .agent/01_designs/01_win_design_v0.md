# MarsinDictation — Windows v0 Design

> This document defines the v0 desktop implementation for Windows. It intentionally prioritizes speed, reliability, and low operational complexity over cross-platform code sharing.

---

## Vision

A tiny Windows tray app that does one thing well:

**hotkey → record → transcribe → inject text**

The user presses a hotkey, speaks naturally, presses the hotkey again, and polished text appears at the user's cursor in most standard Windows text inputs, with recovery if direct injection fails.

---

## Non-Goals (v0)

- ~~Hold-to-talk with low-level keyboard hook~~ *(implemented — Ctrl+Win hold-to-record)*
- App-specific formatting profiles
- Local embedded Python runtime
- Offline model bundle
- Command grammar ("make this formal", "summarize")
- Code-mode / email-mode / tone transforms
- Cross-platform shared runtime code

---

## Requirements & Environment Setup

### Prerequisites

| Dependency | Version | Purpose |
|-----------|---------|---------|
| .NET SDK | 8.0+ | Build and run the application |
| WPF | .NET 8 built-in | UI framework (WPF, not WinUI 3) |
| H.NotifyIcon.Wpf | Latest | System tray icon |
| Visual Studio 2022 or `dotnet` CLI | Latest | Development toolchain |
| Windows 10 | 1809+ | Minimum OS version |
| LocalAI *(optional)* | Latest | Local transcription server (whisper.cpp backend) |

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
> **Whisper.net / whisper.cpp in-process** is a last-resort fallback only. It requires bundling native binaries, adds build complexity, and changes the architecture from "HTTP client" to "embedded native inference." Do not pursue this path without explicit approval. If LocalAI does not meet local transcription needs, escalate before implementing Whisper.net.

### Environment Variables

```
MARSIN_TRANSCRIPTION_PROVIDER=openai|localai
OPENAI_API_KEY=sk-...                          # required if provider=openai
OPENAI_MODEL=gpt-4o-mini-transcribe            # or whisper-1 / gpt-4o-transcribe

LOCALAI_ENDPOINT=http://localhost:8080         # required if provider=localai
LOCALAI_MODEL=whisper-1
```

### Build & Run

```powershell
cd windows
dotnet restore
dotnet build
dotnet run --project MarsinDictation.App
```

---

## UX

### Primary Hotkey — Hold-to-Record

**`Ctrl + Shift`** (hold) — record while held, stop when released

> [!IMPORTANT]
> **Hard requirement: 2-key combo only.** The primary dictation hotkey must be exactly two physical keys for speed and ergonomics.

> [!NOTE]
> Uses a `WH_KEYBOARD_LL` low-level keyboard hook to track modifier state. Recording starts when both keys are held and stops when either is released. If any non-modifier key is pressed while both are held (e.g., Ctrl+Shift+C), the recording is cancelled — this preserves all standard Ctrl+Shift+X shortcuts.

### ~~Toggle Hotkey~~ (skipped)

~~`Ctrl + Shift + Space` — toggle recording on/off~~

> [!NOTE]
> Skipped for v0. The hold-to-record via Ctrl+Shift is sufficient. Toggle mode added complexity (debounce conflicts, RegisterHotKey unreliability) without enough benefit for the initial version.

### Recovery Hotkey ✅

**`Alt + Shift + Z`** — paste the last transcription

If text injection fails (elevated app, locked text field, no focused cursor), the transcript is **not lost**. The user can switch to any text field and press `Alt + Shift + Z` to inject the most recent result.

### UI Elements

| Element | Description | Status |
|---------|-------------|--------|
| **System tray icon** | Persistent icon with right-click menu (Settings, History, Open Data, Clean Data, Quit) | ✅ |
| **Recording overlay** | Small floating indicator — passive ghost window (`WS_EX_NOACTIVATE`) | ✅ |
| **Settings window** | Compact window for hotkey, language, provider, and preferences | 🔮 Future |
| **Transcript history** | Scrollable panel showing recent transcriptions with copy/re-inject | 🔮 Future |
| **Per-app exclusion list** | Allows disabling dictation in specific apps | 🔮 Future |

---

## Architecture

### Process Model

Single process: WPF shell with background dictation orchestration inside `App.xaml.cs`. System tray icon via **H.NotifyIcon.Wpf**. The `DictationService.cs` defines the state machine, while `App.xaml.cs` directly orchestrates the recording → transcription → injection pipeline.

### Module Structure

```
windows/
├── MarsinDictation.sln
├── MarsinDictation.App/                    # WinUI 3 application shell
│   ├── App.xaml / App.xaml.cs
│   ├── MainWindow.xaml                     # Settings UI
│   ├── Tray/
│   │   └── TrayController.cs              # H.NotifyIcon.WinUI tray icon & context menu
│   └── Overlay/
│       └── RecordingOverlay.xaml           # Floating recording indicator
│
├── MarsinDictation.Core/                   # Core logic library
│   ├── Hotkey/
│   │   └── HotkeyManager.cs               # RegisterHotKey: both dictation + recovery hotkeys
│   ├── Audio/
│   │   ├── AudioCapture.cs                 # WASAPI mic capture
│   │   ├── WavEncoder.cs                   # PCM → WAV encoding
│   │   └── AudioGuard.cs                   # 25 MB upload limit enforcement
│   ├── Transcription/
│   │   ├── ITranscriptionClient.cs         # Abstraction interface
│   │   ├── OpenAITranscriptionClient.cs    # OpenAI /v1/audio/transcriptions
│   │   └── LocalAITranscriptionClient.cs   # LocalAI /v1/audio/transcriptions
│   ├── Processing/
│   │   └── TextPostProcessor.cs            # Filler removal, punctuation, cleanup
│   ├── Injection/
│   │   ├── ITextInjector.cs                # Abstraction interface
│   │   ├── ClipboardInjector.cs            # Clipboard + Ctrl+V (primary)
│   │   └── SendInputInjector.cs            # SendInput keystroke fallback
│   ├── History/
│   │   └── TranscriptStore.cs              # Transcript storage with state tracking
│   └── DictationService.cs                 # Orchestrator: capture → transcribe → inject
│
└── MarsinDictation.Tests/
    ├── HotkeyTests.cs
    ├── InjectionTests.cs
    └── TranscriptionTests.cs
```

---

## Flow

```
┌──────────────────────────────────────────────────────────┐
│  1. Check foreground process against exclusion list      │
│     → If excluded: no-op with subtle notification        │
│  2. User presses Ctrl + Shift (both held, then released) │
│  3. HotkeyManager receives WM_HOTKEY                     │
│  4. DictationService.StartCapture()                      │
│  5. AudioCapture begins WASAPI recording                 │
│  6. RecordingOverlay appears (red / pulsing)              │
│  7. AudioGuard monitors estimated WAV size               │
│     → Auto-stops if approaching 25 MB                    │
│  8. User speaks...                                       │
│  9. User presses Ctrl + Shift again                      │
│     (or AudioGuard auto-stops at limit)                   │
│ 10. DictationService.StopCapture()                       │
│ 11. WavEncoder produces WAV buffer                       │
│ 12. ITranscriptionClient.TranscribeAsync(wav)            │
│     ├─ OpenAI:  POST /v1/audio/transcriptions            │
│     └─ LocalAI: POST /v1/audio/transcriptions            │
│ 13. TextPostProcessor.Process(rawText)                   │
│     ├─ Strip filler words ("um", "uh", "like")           │
│     ├─ Fix punctuation & capitalization                  │
│     └─ Return cleaned text                               │
│ 14. Injection targets the CURRENTLY FOCUSED field        │
│     (not the field focused when recording started)       │
│ 15. Injection (internal buffer — never touches clipboard):│
│     ├─ Text stored in internal TranscriptStore buffer    │
│     ├─ Try: SendInputInjector (Unicode keystrokes)       │
│     └─ If UIPI blocks: store as "pending" for recovery   │
│ 16. If ALL injection fails:                              │
│     ├─ Store in TranscriptStore as "pending"             │
│     └─ Toast: "Text saved. Press Alt+Shift+Z to paste."  │
│ 17. TranscriptStore.Save(transcript)                     │
└──────────────────────────────────────────────────────────┘
```

---

## Implementation Choices

### Hotkey — Single `HotkeyManager` with `RegisterHotKey`

Use a hybrid approach for v0. The dictation hotkey (Ctrl+Shift) uses a `WH_KEYBOARD_LL` low-level keyboard hook since `RegisterHotKey` cannot cleanly handle modifier-only combos. The recovery hotkey (Alt+Shift+Z) uses standard `RegisterHotKey`.

A single `HotkeyManager` manages both mechanisms:

```csharp
// Dictation: WH_KEYBOARD_LL hook (2-key modifier-only combo)
// Tracks Ctrl+Shift state, fires on release without intervening keys
SetWindowsHookEx(WH_KEYBOARD_LL, LowLevelKeyboardCallback, ...);

// Recovery: standard RegisterHotKey
RegisterHotKey(hwnd, RECOVERY_HOTKEY_ID, MOD_ALT | MOD_SHIFT, 0x5A /* Z */);
```

> [!IMPORTANT]
> **Cleanup:** Call `UnregisterHotKey(hwnd, id)` for both IDs on app shutdown. This is part of app lifetime handling.

### Audio — WASAPI

Use WASAPI capture. Microsoft documents WASAPI as the Windows Core Audio API for capture and rendering, and it is the right native lane for low-latency mic access.

### Transcription — OpenAI or LocalAI

Two providers behind `ITranscriptionClient`, both using the same `/v1/audio/transcriptions` endpoint shape:

| Provider | Endpoint | Pros | Cons |
|----------|----------|------|------|
| **OpenAI** | `POST /v1/audio/transcriptions` | Best accuracy, multiple models (`whisper-1`, `gpt-4o-mini-transcribe`, `gpt-4o-transcribe`) | Requires API key, costs money, needs internet |
| **LocalAI** | `POST /v1/audio/transcriptions` (local server) | Free, offline, private, supports whisper.cpp / faster-whisper backends | Requires LocalAI install, slower on weak hardware |

Because both providers expose the same OpenAI-compatible endpoint, `ITranscriptionClient` is a single HTTP client parameterized by base URL, auth, and model. The provider and model are selected via env var or settings UI.

### Upload Size Guard 🔮

OpenAI's speech-to-text API currently limits uploaded audio files to **25 MB**. The `AudioGuard` module will enforce this limit during recording. The planned behavior is:

- Monitor estimated encoded WAV size during recording
- Automatically stop recording before the upload would exceed 25 MB
- Send the captured audio as-is
- Show a toast: "Recording limit reached. Sending captured audio."

This same guard applies to both providers for consistent UX.

> **Status:** Not yet implemented. See [Future Work](#future-work).

### Injection — SendInput + Clipboard Fallback ✅

Injection uses `SendInput` with Unicode keystrokes (`KEYEVENTF_UNICODE`) to type text directly into the focused field. If `SendInput` fails (e.g., UIPI blocks injection to an elevated app), the text is copied to the clipboard as a fallback and the user is notified.

| Priority | Method | Mechanism | Why it might fail |
|----------|--------|-----------|-------------------|
| 1 | **SendInput** | Unicode-aware simulated keystrokes (`KEYEVENTF_UNICODE`) | UIPI blocks injection to elevated apps |
| 2 | **Clipboard fallback** | `Clipboard.SetText()` + toast notification | User must manually Ctrl+V |

> [!NOTE]
> **Design deviation:** The original design specified "never touches the clipboard." The current implementation copies text to clipboard on every injection as a convenience backup. This is a deliberate trade-off for reliability — if `SendInput` silently fails in certain apps, the user still has the text on clipboard.

> [!WARNING]
> We do **not** use `UIAutomation.ValuePattern.SetValue()` for v0. It **overwrites the entire text field** rather than inserting at the cursor position.

> [!IMPORTANT]
> If injection fails (e.g., UIPI blocks input to an elevated app), the transcript is **not lost**. It is saved to `TranscriptStore` as "pending" and the user is notified. They can press **`Alt + Shift + Z`** at any time to re-attempt injection into the currently focused field.

### Recovery — `Alt + Shift + Z`

Handled by the same `HotkeyManager` (second registered ID). When pressed:
1. Pop the most recent "pending" transcript from `TranscriptStore`
2. Run the injection ladder again against the currently focused element
3. If no pending transcript exists, re-inject the last successful transcript (clipboard-style convenience)

### Focus Semantics

> [!IMPORTANT]
> **Injection always targets the currently focused field at the time transcription completes**, not the field that was focused when recording started. This is intentional: the user may switch apps while dictating, and the text should land wherever their cursor is when they're ready.

---

## Settings (v0)

| Setting | Default | Type | Status |
|---------|---------|------|--------|
| Dictation hotkey (hold) | `Ctrl + Shift` | 2-key, hold-to-record | ✅ |
| Recovery hotkey | `Alt + Shift + Z` | Key combo | ✅ |
| Transcription provider | `openai` | Enum: `openai` / `localai` | 🚧 `.env` only |
| OpenAI API key | *(empty)* | String (secret) | 🚧 `.env` only |
| OpenAI model | `gpt-4o-mini-transcribe` | Enum: `whisper-1` / `gpt-4o-mini-transcribe` / `gpt-4o-transcribe` | ✅ |
| LocalAI endpoint | `http://localhost:8080` | URL | 🚧 `.env` only |
| LocalAI model | `whisper-1` | String | 🚧 `.env` only |
| Language | `en` | ISO 639-1 | 🔮 Future |
| Auto-punctuation | `on` | Boolean | 🔮 Future |
| Strip filler words | `on` | Boolean | 🔮 Future |
| Launch at startup | `off` | Boolean | 🔮 Future |
| Local history | `on` | Boolean | ✅ Sharded JSONL |

> [!IMPORTANT]
> Secrets entered through the UI, such as the OpenAI API key, must **not** be stored in plain JSON settings files. Use a Windows-protected secret storage mechanism (DPAPI-backed encryption or `ProtectedData` API). Currently, API keys are read from `.env` files.

---

## Failure Modes

| Failure | User Experience |
|---------|----------------|
| No mic detected | Toast: "No microphone found. Check your audio settings." |
| Mic disconnects mid-recording | Recording stops gracefully; partial audio sent for transcription |
| Recording approaches 25 MB | Recording auto-stops. Toast: "Recording limit reached. Sending captured audio." |
| Transcription API unreachable | Toast: "Transcription failed. Check your internet/API settings." |
| Transcription returns empty | Toast: "No speech detected. Try again." |
| All injection methods fail | Transcript saved as pending. Toast: "Press Alt+Shift+Z to paste." |
| Elevated app blocks injection | Falls through ladder; same pending/recovery behavior |
| Excluded app is in foreground | Dictation no-ops with subtle notification |

---

## Acceptance Criteria

- [x] Dictation works end-to-end in: **Notepad, Chrome textarea, VS Code**
- [x] OpenAI transcription works with valid API key
- [x] LocalAI transcription works (same client, configurable endpoint)
- [x] WAV upload path works end-to-end for both providers
- [ ] Recordings exceeding 25 MB are handled gracefully *(🔮 AudioGuard)*
- [x] Injection falls through to clipboard when SendInput fails
- [x] Injection targets focused field at transcription-complete time, not recording-start time
- [x] `Alt + Shift + Z` successfully re-injects the last transcript
- [x] Both hotkeys are unregistered on app shutdown
- [ ] App survives mic disconnect and reconnect *(🔮 untested)*
- [x] Clear error toast if transcription fails
- [ ] History panel shows recent transcripts with copy/re-inject *(🔮 Future)*
- [x] Tray icon and overlay are non-intrusive (passive ghost window)
- [x] Settings persist across app restarts (via `.env`)
- [ ] Excluded apps are skipped with subtle notification *(🔮 Future)*
- [ ] OpenAI API key stored via DPAPI, not plain JSON *(🔮 currently `.env`)*

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
| `pending` | Transcription succeeded but injection failed — recoverable via `Alt+Shift+Z`. This is the only injection-failure state; there is no separate `failed_injection`. |
| `failed_transcription` | Audio captured but the transcription API returned an error |

---

## Agent Implementation Notes

These are not blocking changes but rules the implementation must follow:

### Tray Ownership

- Keep tray icon ownership in the **App layer only** (`TrayController.cs`)
- **Core must not know** anything about tray APIs
- Overlay and tray state should **subscribe to service state**, not drive it

### Injection Flow (Current)

```
1. Transcription completes → text stored in TranscriptStore
2. SendInput types text directly via KEYEVENTF_UNICODE keystrokes
3. Clipboard.SetText(text) — backup copy on every injection
4. If SendInput fails → mark as "pending", toast: "Copied to clipboard (Ctrl+V)"
5. Recovery hotkey re-attempts SendInput from _lastTranscription
```

### SendInput Unicode Mode

For the typing fallback, use Unicode-aware input (`KEYEVENTF_UNICODE` flag with `wScan` set to the character value). Do not attempt to map every character to a virtual key code — that breaks for punctuation, non-English text, and symbols.

### Provider Capability Normalization

Not every provider/model supports the same response format. v0 normalizes all transcription responses to **plain text output** only. Do not rely on structured metadata or word-level timestamps from either provider.

### Prior Internal Reference

The existing MarsinHome mobile app uses this exact API shape as a working reference. Its GOL server `transcribe.js` route converts base64 audio → `multipart/form-data` → `POST /v1/audio/transcriptions` with `Bearer` auth. The Windows app calls the endpoint directly (no proxy needed).

---

## Future Work

Features designed but not yet implemented. These are tracked here as the canonical backlog.

### Rapid Back-to-Back Recordings

Users should be able to hold → speak → release → hold → speak → release in rapid succession without conflicts. Requirements:

- A new recording must **never block on** a previous transcription still in flight
- Each recording session should be assigned a unique ID and queued independently
- Transcription results should be injected in **order of recording start time**, not completion time
- If a transcription completes while another is being injected, it should queue behind it
- The StatusWindow overlay should reflect the **most recent active state** (recording takes priority over transcribing)

Implementation approach:
- Use a `ConcurrentQueue<RecordingSession>` or `Channel<T>` to decouple recording from transcription
- Each session carries its own WAV data and timestamp
- A background consumer processes the queue sequentially for injection

### AudioGuard (25 MB Upload Limit)

Monitor `AudioRecorder.CurrentSize` during capture and auto-stop before exceeding 25 MB. Show toast: "Recording limit reached."

### TextPostProcessor (Filler Word Removal)

Strip filler words ("um", "uh", "like"), fix punctuation and capitalization. Low priority — OpenAI models already produce clean output.

### Per-App Exclusion List

Before starting capture **and** before recovery injection, check the foreground process against an exclusion list:
- Use `GetForegroundWindow()` → `GetWindowThreadProcessId()` → process name
- If excluded: no-op with subtle notification ("Dictation disabled for this app")

### Settings UI Window

Replace the `MainWindow.xaml` placeholder with a real settings panel:
- Provider selection (OpenAI / LocalAI)
- API key input (stored via DPAPI)
- Model selection
- Language preference
- Launch at startup toggle

### Transcript History Panel

Scrollable panel showing recent transcriptions with copy and re-inject actions. Data is already stored in sharded JSONL files.

### Usage Metrics

Track and display usage statistics in a JSONL metrics ledger:
- Total words transcribed (lifetime and per-session)
- Number of recordings made
- Average recording duration
- Transcription success/failure rate
- Provider breakdown (OpenAI vs LocalAI usage)
- Daily/weekly/monthly summaries

Metrics should be stored locally in `%LOCALAPPDATA%/MarsinDictation/metrics/` and optionally surfaced in the Settings or History UI. See [Metrics Design](../.agent/01_designs/04_metrics.md) for the JSONL ledger format.

### DictationService Refactor

Currently `App.xaml.cs` directly orchestrates recording → transcription → injection. The `DictationService.cs` state machine is defined but not used at runtime. Consider refactoring the orchestration logic from `App.xaml.cs` into `DictationService` for cleaner separation of concerns.
