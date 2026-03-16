# MarsinDictation

**Lightweight AI-powered dictation for desktop and mobile.**

Press a hotkey, speak naturally, and polished text appears at your cursor. Powered by speech recognition with AI post-processing that removes filler words, fixes grammar, and applies punctuation automatically.

## Quick Start

```bash
python devtool/deploy.py              # Auto-detect OS → build, test, run
python devtool/deploy.py --run        # Run only (auto-rebuilds if source changed)
python devtool/deploy.py --build      # Build + test only
```

See [`devtool/README.md`](devtool/README.md) for full deploy tool docs.

## Platforms

| Platform | Activation | Status |
|----------|-----------|--------|
| **Windows** | `Ctrl+Win` (hold) / `Alt+Shift+Z` (recovery) | 🟢 v0 |
| **macOS** | `Control+Option` (hold) / `⌘⇧Z` (recovery) | 🟢 v0 |
| **iPhone / iPad** | Custom keyboard with dictation button | 📋 Planned |
| **Android** | Custom keyboard with dictation button | 📋 Planned |

## Configuration

The application reads from a `.env` file for configuration. Copy `.env.example` to `.env` to customize your provider:

| Setting | Description | Default |
|---------|-------------|---------|
| `MARSIN_TRANSCRIPTION_PROVIDER` | Choose `localai` or `openai` | `localai` |
| `OPENAI_API_KEY` | Required if provider is `openai` | *(empty)* |
| `OPENAI_MODEL` | The OpenAI model to use | `gpt-4o-mini-transcribe` |
| `LOCALAI_ENDPOINT` | LocalAI server base URL | `http://localhost:3840` |
| `LOCALAI_MODEL` | Name of the whisper model loaded in LocalAI | `whisper-large-turbo` |

### Using LocalAI (Free, Offline)

If you cannot use OpenAI on your machine due to network or policy restrictions, you can run transcription locally using [LocalAI](https://localai.io):

1. Switch to `localai` parsing: Set `MARSIN_TRANSCRIPTION_PROVIDER=localai` in your `.env`.
2. Install LocalAI: `curl -Lo local-ai https://github.com/mudler/LocalAI/releases/latest/download/local-ai-darwin-arm64 && chmod +x local-ai` (assuming Apple Silicon). Alternatively, use Docker: `docker run -p 8080:8080 -ti localai/localai:latest-aio-cpu`
3. Download a Whisper model to your LocalAI `models` directory (e.g., `whisper-1`).
4. Start LocalAI: `./local-ai --models-path ./models`
5. Ensure `LOCALAI_ENDPOINT` points to `http://localhost:8080`.

## Key Features

- **System-Wide Dictation** — Dictate into any text field in most standard apps. Hold the hotkey to record, release to transcribe and inject.
- **AI Auto-Editing** — Filler words ("um", "uh") are stripped, grammar is corrected, and punctuation is applied automatically.
- **Recovery Hotkey** — If text injection fails, press `Alt+Shift+Z` (Windows) or `⌘⇧Z` (macOS) to paste your last dictation into any text field.
- **Dual Transcription Providers** — OpenAI API for best accuracy, or LocalAI for free offline private transcription.
- **Privacy-First** — Audio is never retained after transcription. API keys use platform-secure storage (DPAPI / Keychain). No telemetry.

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

MIT

