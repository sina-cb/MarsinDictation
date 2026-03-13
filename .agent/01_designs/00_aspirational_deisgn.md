# NOTE: This document describes the aspirational cross-platform target architecture for MarsinDictation, not the recommended v0 implementation.

# MarsinDictation — Repository Structure & Technology Design

## Overview

MarsinDictation is a multi-platform AI-powered dictation tool that provides system-wide speech-to-text via a global hotkey (desktop) or a custom keyboard extension (mobile). This document defines the monorepo layout, per-platform technology choices, and the shared component strategy.

---

## Language & Technology Decisions

Each platform requires deep OS-level integration (keyboard hooks, accessibility APIs, input method services). The language for each platform is chosen to maximize **native API access** and **first-class platform support**:

| Platform | Language | Framework / API | Rationale |
|----------|----------|-----------------|-----------|
| **Windows** | C# (.NET 8 / WinUI 3) | `SetWindowsHookEx`, `SendInput`, WASAPI | First-class Win32 interop via P/Invoke. WinUI 3 for modern system tray + settings UI. Richest ecosystem for Windows background services. |
| **macOS** | Swift | `CGEvent` / Accessibility APIs, `AVAudioEngine`, `NSSpeechRecognizer` | Only Swift/ObjC can access macOS Accessibility and Input Monitoring permissions. Required for global hotkey capture and text injection. |
| **iPhone / iPad** | Swift | Custom Keyboard Extension (`UIInputViewController`), `AVAudioSession`, Speech framework | Apple requires keyboard extensions in Swift/ObjC. Containing app handles mic access and speech-to-text, passing results back to the extension. |
| **Android** | Kotlin | `InputMethodService`, `SpeechRecognizer`, `MediaRecorder` | Kotlin is Google's preferred language. `InputMethodService` is the only way to create a system keyboard. Full mic + speech API access. |
| **Shared / Common** | Python | Whisper API client, text post-processing, config schemas | Cross-platform glue for AI pipeline, prompt engineering, config validation. Can be embedded or called as a local service. |

> [!IMPORTANT]
> The shared Python layer handles the AI post-processing pipeline (filler removal, grammar correction, tone adjustment, context-aware formatting). Each native client captures audio and injects text, but delegates AI processing to the shared engine — either locally or via API.

---

## Repository Structure

```
MarsinDictation/
├── README.md
├── .gitignore
├── LICENSE
│
├── common/                          # Shared cross-platform code
│   ├── ai/                          # AI post-processing pipeline
│   │   ├── __init__.py
│   │   ├── processor.py             # Main text processor (filler removal, grammar, punctuation)
│   │   ├── context.py               # Context-aware formatting (email vs chat vs code)
│   │   ├── commands.py              # Voice command parser ("make formal", "summarize")
│   │   └── whisper_client.py        # Speech-to-text API client (OpenAI Whisper / local)
│   ├── config/                      # Shared configuration
│   │   ├── schema.py                # Config schema definitions & validation
│   │   ├── defaults.yaml            # Default settings (languages, tone, hotkeys)
│   │   └── dictionary.py            # Custom dictionary & snippets manager
│   ├── proto/                       # Protocol definitions (if using gRPC/IPC)
│   │   └── dictation.proto
│   └── tests/
│       ├── test_processor.py
│       ├── test_context.py
│       └── test_commands.py
│
├── windows/                         # Windows application (C# / .NET 8)
│   ├── MarsinDictation.sln
│   ├── src/
│   │   ├── MarsinDictation/         # Main WinUI 3 app
│   │   │   ├── App.xaml
│   │   │   ├── App.xaml.cs
│   │   │   ├── MainWindow.xaml      # Settings / status UI
│   │   │   └── MarsinDictation.csproj
│   │   ├── MarsinDictation.Core/    # Core logic library
│   │   │   ├── Hotkey/
│   │   │   │   ├── GlobalHotkeyHook.cs    # SetWindowsHookEx for Ctrl+Win
│   │   │   │   └── HotkeyManager.cs
│   │   │   ├── Audio/
│   │   │   │   ├── AudioCapture.cs        # WASAPI mic capture
│   │   │   │   └── AudioBuffer.cs
│   │   │   ├── TextInjection/
│   │   │   │   ├── InputSimulator.cs      # SendInput wrapper
│   │   │   │   └── ClipboardInjector.cs   # Fallback: clipboard paste
│   │   │   ├── AI/
│   │   │   │   └── AIPipelineBridge.cs    # Bridge to common/ai (HTTP or embedded)
│   │   │   └── Services/
│   │   │       ├── DictationService.cs    # Orchestrates capture → transcribe → inject
│   │   │       └── TrayService.cs         # System tray icon & menu
│   │   └── MarsinDictation.Tests/
│   │       ├── HotkeyTests.cs
│   │       └── TextInjectionTests.cs
│   └── installer/
│       └── setup.iss                # Inno Setup or MSIX packaging
│
├── mac/                             # macOS application (Swift)
│   ├── MarsinDictation.xcodeproj
│   ├── Sources/
│   │   ├── App/
│   │   │   ├── AppDelegate.swift
│   │   │   ├── StatusBarController.swift  # Menu bar icon & controls
│   │   │   └── SettingsView.swift
│   │   ├── Core/
│   │   │   ├── Hotkey/
│   │   │   │   ├── GlobalHotkey.swift     # CGEvent tap for ⌃+⌘
│   │   │   │   └── HotkeyManager.swift
│   │   │   ├── Audio/
│   │   │   │   ├── AudioCapture.swift     # AVAudioEngine mic capture
│   │   │   │   └── AudioBuffer.swift
│   │   │   ├── TextInjection/
│   │   │   │   ├── AccessibilityInjector.swift  # AXUIElement text insertion
│   │   │   │   └── CGEventInjector.swift        # CGEvent keystroke simulation
│   │   │   └── AI/
│   │   │       └── AIPipelineBridge.swift  # Bridge to common/ai
│   │   └── Services/
│   │       └── DictationService.swift
│   ├── Tests/
│   │   └── CoreTests/
│   └── MarsinDictation.entitlements       # Accessibility, mic permissions
│
├── iphone/                          # iOS app + keyboard extension (Swift)
│   ├── MarsinDictation.xcodeproj
│   ├── App/                         # Containing app (has mic access)
│   │   ├── AppDelegate.swift
│   │   ├── ContentView.swift         # Settings, dictionary, onboarding
│   │   ├── AudioService.swift        # Records audio, sends to AI pipeline
│   │   └── Info.plist
│   ├── Keyboard/                    # Custom Keyboard Extension
│   │   ├── KeyboardViewController.swift   # UIInputViewController subclass
│   │   ├── DictationButton.swift          # Push-to-talk button UI
│   │   ├── EmojiPicker.swift              # Quick emoji access
│   │   ├── KeyboardLayout.swift           # Minimal layout: dictate + emoji
│   │   ├── Info.plist
│   │   └── Keyboard.entitlements          # RequestsOpenAccess for network
│   ├── Shared/                      # Shared between app & extension
│   │   ├── TranscriptionBridge.swift      # App ↔ Extension IPC (App Groups)
│   │   └── SettingsStore.swift            # UserDefaults (shared App Group)
│   └── Tests/
│
├── android/                         # Android app + IME (Kotlin)
│   ├── build.gradle.kts
│   ├── app/
│   │   ├── src/main/
│   │   │   ├── java/com/marsin/dictation/
│   │   │   │   ├── MainActivity.kt        # Settings, onboarding
│   │   │   │   ├── ime/
│   │   │   │   │   ├── MarsinIME.kt       # InputMethodService subclass
│   │   │   │   │   ├── DictationButton.kt # Push-to-talk button
│   │   │   │   │   └── EmojiView.kt       # Quick emoji picker
│   │   │   │   ├── audio/
│   │   │   │   │   └── AudioCapture.kt    # MediaRecorder / AudioRecord
│   │   │   │   ├── ai/
│   │   │   │   │   └── AIPipelineBridge.kt
│   │   │   │   └── settings/
│   │   │   │       └── SettingsRepository.kt
│   │   │   ├── res/
│   │   │   │   ├── layout/
│   │   │   │   │   ├── keyboard_view.xml
│   │   │   │   │   └── activity_main.xml
│   │   │   │   ├── xml/
│   │   │   │   │   └── method.xml         # IME service declaration
│   │   │   │   └── values/
│   │   │   └── AndroidManifest.xml
│   │   └── src/test/
│   └── gradle/
│
├── docs/                            # Project-wide documentation
│   ├── architecture.md              # High-level architecture diagram
│   ├── ai-pipeline.md               # AI processing pipeline details
│   ├── privacy.md                   # Privacy policy & data handling
│   └── contributing.md
│
└── scripts/                         # Dev tooling & CI
    ├── lint.py                      # Cross-project linting
    ├── build_all.sh                 # Build all platforms
    └── ci/
        ├── windows.yml
        ├── mac.yml
        ├── iphone.yml
        └── android.yml
```

---

## Platform Details

### 1. Windows (C# / .NET 8 + WinUI 3)

**Activation:** `Ctrl + Win` (push-to-talk, configurable)

**How it works:**
1. A background service installs a low-level keyboard hook via `SetWindowsHookEx(WH_KEYBOARD_LL, ...)` to intercept `Ctrl + Win`.
2. On key-down: begins streaming mic audio via WASAPI to the AI pipeline.
3. On key-up: finalizes audio, sends to Whisper for transcription, runs AI post-processing.
4. Injects the resulting text into the active window using `SendInput` (simulated keystrokes) or clipboard-paste fallback.
5. A system tray icon provides quick access to settings, language selection, and status.

**Key dependencies:** .NET 8, WinUI 3, Windows App SDK, Windows Input Simulator (NuGet).

---

### 2. macOS (Swift)

**Activation:** `⌃ Control + ⌘ Command` (push-to-talk, configurable)

**How it works:**
1. Registers a `CGEvent` tap to capture the global hotkey. Requires Accessibility permission.
2. On key-down: starts `AVAudioEngine` capture.
3. On key-up: sends audio to AI pipeline, receives processed text.
4. Injects text via Accessibility API (`AXUIElement`) or `CGEvent` keystroke simulation.
5. Lives in the menu bar with a status icon and dropdown for settings.

**Key permissions:** Accessibility (Input Monitoring), Microphone.

---

### 3. iPhone / iPad (Swift — Keyboard Extension)

**Activation:** Tap the **dictation button** on the custom keyboard.

**How it works:**
1. User installs the app and enables the "MarsinDictation" keyboard in Settings → Keyboards.
2. The keyboard extension presents a minimal UI: a large **push-to-talk button** and an **emoji picker**.
3. When the dictation button is pressed, the extension signals the containing app (via App Groups IPC) to begin audio recording (keyboard extensions cannot access the mic directly).
4. The containing app captures audio, sends it to the AI pipeline, and returns processed text.
5. The keyboard extension inserts the text via `UIInputViewController.textDocumentProxy`.

**Key constraints:**
- Keyboard extensions have no mic access — the containing app must handle audio.
- "Full Access" (RequestsOpenAccess) is needed for network calls.
- App Groups enable data sharing between the extension and containing app.

---

### 4. Android (Kotlin — Input Method Service)

**Activation:** Tap the **dictation button** on the custom keyboard.

**How it works:**
1. User installs the app and enables "MarsinDictation" as an input method in Settings → Language & Input.
2. The IME (`InputMethodService`) presents a minimal keyboard UI: a **push-to-talk button** and **emoji picker**.
3. On button press, the IME uses `AudioRecord` or Android's `SpeechRecognizer` to capture speech.
4. Audio is sent to the AI pipeline, and processed text is committed via `getCurrentInputConnection().commitText()`.

**Key permissions:** `RECORD_AUDIO`, `INTERNET`.

---

## Shared Components (`common/`)

The `common/` directory contains platform-independent logic written in Python:

| Module | Purpose |
|--------|---------|
| `ai/processor.py` | Core text post-processing: filler removal, grammar correction, punctuation, formatting |
| `ai/context.py` | Context-aware formatting engine (email, chat, code, etc.) |
| `ai/commands.py` | Voice command parser for "make formal", "summarize", etc. |
| `ai/whisper_client.py` | Abstracted speech-to-text client (supports OpenAI API, local Whisper, or custom endpoint) |
| `config/schema.py` | Shared config schema (languages, tone, hotkeys, dictionary) validated with Pydantic |
| `config/dictionary.py` | Custom dictionary & snippet manager (shared vocabulary across platforms) |

**Integration options:**
- **HTTP microservice** — The common Python engine runs as a local FastAPI server; native clients call it via HTTP.
- **Embedded Python** — On desktop, Python can be embedded (e.g., Python.NET on Windows, PythonKit on macOS).
- **API-only** — For mobile, the AI pipeline runs server-side and clients call a cloud endpoint.

---

## Development Priorities

| Phase | Scope | Milestone |
|-------|-------|-----------|
| **Phase 1** | Windows app + common AI pipeline | End-to-end dictation with `Ctrl + Win` |
| **Phase 2** | macOS app | Feature parity with Windows |
| **Phase 3** | iPhone keyboard extension | Dictation button keyboard |
| **Phase 4** | Android IME | Dictation button keyboard |

---

## Build & CI

Each platform has its own build system:

| Platform | Build Tool | CI |
|----------|-----------|-----|
| Windows | `dotnet build` | GitHub Actions (`windows.yml`) |
| macOS | `xcodebuild` | GitHub Actions (`mac.yml`) |
| iPhone | `xcodebuild` | GitHub Actions (`iphone.yml`) |
| Android | `gradle` | GitHub Actions (`android.yml`) |
| Common | `pytest` / `pip` | Runs on all CI pipelines |
