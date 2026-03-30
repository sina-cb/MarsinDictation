# MarsinDictation

**Lightweight AI-powered dictation for desktop and mobile.**

Press a hotkey, speak naturally, and polished text appears at your cursor. Powered by speech recognition with AI post-processing that removes filler words, fixes grammar, and applies punctuation automatically.

## Quick Start

### macOS (Apple Silicon & Intel)
Ensure you have the [Xcode Command Line Tools](https://developer.apple.com/xcode/features/) installed.
```bash
# Build, package, and permanently install MarsinDictation.app to ~/Applications
python3 devtool/deploy.py mac --install

# Or alternatively, build and test directly from source without installing:
python3 devtool/deploy.py --run
```

### Windows 11 / 10
Ensure you have the [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) and Python installed on your Windows system.
```powershell
# Build, package, and permanently install MarsinDictation.exe locally
python devtool/deploy.py windows --install

# Or alternatively, build and test directly from source without installing:
python devtool/deploy.py --run
```

> [!NOTE]
> See [`devtool/README.md`](devtool/README.md) for full deploy tool testing and debugging arguments.

## Platforms

| Platform | Activation | Status |
|----------|-----------|--------|
| **Windows** | `Ctrl+Win` (hold) / `Alt+Shift+Z` (recovery) | 🟢 v1 |
| **macOS** | `Control+Option` (hold) / `⌘⇧Z` (recovery) | 🟢 v1 |
| **iPhone / iPad** | Custom keyboard with dictation button | 📋 Planned |
| **Android** | Custom keyboard with dictation button | 📋 Planned |

## Transcription Providers

MarsinDictation uniquely supports three distinct AI transcription engines, allowing you to choose between absolute privacy, zero-setup offline execution, or maximum cloud accuracy:

1. **Embedded (Default):** Runs Whisper directly inside the native application using a bundled `.bin` model. It requires **zero setup**, zero servers, and no API keys. It automatically hardware-accelerates using Apple Silicon (on MacOS) or Vulkan API (on Windows RTX/AMD GPUs) to achieve sub-second offline transcription speeds while keeping your audio 100% private.
2. **OpenAI:** Connects to the official OpenAI cloud ecosystem (`gpt-4o-audio-preview` or `whisper-1`). Requires an API key, but enables transcription on extremely low-end machines lacking GPUs.
3. **LocalAI (Legacy):** Allows connecting MarsinDictation to an external, self-hosted LocalAI Docker container if you are running a monolithic home-server setup.

## Configuration

The application reads from a `.env` file for configuration. Copy `.env.example` to `.env` to customize your provider:

| Setting | Description | Default |
|---------|-------------|---------|
| `MARSIN_TRANSCRIPTION_PROVIDER` | Choose `embedded`, `openai`, or `localai` | `embedded` |
| `MARSIN_WHISPER_MODEL` | The Embedded ggml file to load from local appdata | `ggml-large-v3-turbo-q5_0.bin` |
| `OPENAI_API_KEY` | Required if provider is `openai` | *(empty)* |
| `OPENAI_MODEL` | The OpenAI model to use | `gpt-4o-mini-transcribe` |
| `LOCALAI_ENDPOINT` | LocalAI server base URL | `http://localhost:3850` |
| `LOCALAI_MODEL` | Name of the whisper model loaded in LocalAI | `whisper-1` |

### Using Embedded Whisper (Free, Offline, Zero-Config)

This is the default. It leverages the massive `large-v3-turbo` model natively:
1. Simply install the program. 
2. Upon your first hotkey press, it will automatically download the 547MB quantized model securely from HuggingFace.
3. You immediately get locally accelerated, hyper-accurate transcription. No servers required!

### Using OpenAI (Cloud)

If your device is heavily resource-constrained:
1. Set `MARSIN_TRANSCRIPTION_PROVIDER=openai` inside your settings UI.
2. Provide your `sk-...` API key into the secure credential store prompt when requested, or put `OPENAI_API_KEY=sk-...` inside the `.env` file for development.

### Using LocalAI (Free, Offline)

If you cannot use OpenAI on your machine due to network or policy restrictions, you can run transcription locally using [LocalAI](https://localai.io):

1. Switch to `localai` parsing: Set `MARSIN_TRANSCRIPTION_PROVIDER=localai` inside the Settings UI or your `.env`.
2. Install LocalAI via Docker: `docker run -p 3850:8080 -ti localai/localai:latest-aio-cpu`
3. Download a Whisper model to your LocalAI `models` directory.
4. Ensure `LOCALAI_ENDPOINT` points to `http://localhost:3850`.

## Key Features

- **System-Wide Dictation** — Dictate into any text field in most standard apps. Hold the hotkey to record, release to transcribe and inject.
- **AI Auto-Editing** — Filler words ("um", "uh") are stripped, grammar is corrected, and punctuation is applied automatically.
- **Recovery Hotkey** — If text injection fails, press `Alt+Shift+Z` (Windows) or `⌘⇧Z` (macOS) to paste your last dictation into any text field.
- **Triple Transcription Providers** — Embedded Whisper (zero-config, GPU-accelerated), OpenAI API (cloud), or LocalAI (external containers).
- **Privacy-First** — Audio is never retained after transcription, and zero telemetry is collected. The system securely protects keys natively via macOS Keychain. A local, offline transcription history is retained to your disk by default but can be disabled at any time.

## Project Structure

```
.agent/
├── 00_gol/          # Rules: codex, privacy, git, build & deploy
├── 01_designs/      # Design documents for each platform
├── 02_projects/     # Project plans with task checklists
└── 03_reports/      # Session reports summarizing completed work
devtool/
└── deploy.py        # Unified build/test/run tool (see devtool/README.md)
mac/                 # macOS Swift/SwiftUI implementation
windows/             # Windows .NET 8 / WPF implementation
```

Start with [`.agent/00_gol/00_codex.md`](.agent/00_gol/00_codex.md) — it is the onboarding entry point for contributors and AI agents, covering contribution rules, coding standards, and references to all other documents.

## License

[MIT License](LICENSE)

