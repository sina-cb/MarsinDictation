# MarsinDictation

**Lightweight AI-powered dictation for desktop and mobile.**

Press a hotkey, speak naturally, and polished text appears at your cursor. Powered by speech recognition with AI post-processing that removes filler words, fixes grammar, and applies punctuation automatically.

## Platforms

| Platform | Activation | Status |
|----------|-----------|--------|
| **Windows** | `Ctrl + Alt + Space` (toggle) | 🔨 Design Complete |
| **macOS** | `Control + Option + Space` (toggle) | 🔨 Design Complete |
| **iPhone / iPad** | Custom keyboard with dictation button | 📋 Planned |
| **Android** | Custom keyboard with dictation button | 📋 Planned |

## Key Features

- **System-Wide Dictation** — Dictate into any text field in most standard apps. Toggle the hotkey, speak, toggle again — text appears at your cursor.
- **AI Auto-Editing** — Filler words ("um", "uh") are stripped, grammar is corrected, and punctuation is applied automatically.
- **Recovery Hotkey** — If text injection fails, press `Alt+Shift+Z` (Windows) or `Option+Shift+Z` (macOS) to paste your last dictation into any text field.
- **Dual Transcription Providers** — OpenAI API for best accuracy, or LocalAI for free offline private transcription.
- **Privacy-First** — Audio is never retained after transcription. API keys use platform-secure storage (DPAPI / Keychain). No telemetry.

## Project Structure

This project uses an `.agent/` directory for all governance, design, and project tracking:

```
.agent/
├── 00_gol/          # Rules: codex, privacy, git, build & deploy
├── 01_designs/      # Design documents for each platform
├── 02_projects/     # Project plans with task checklists
└── 03_reports/      # Session reports summarizing completed work
```

Start with [`.agent/00_gol/00_codex.md`](.agent/00_gol/00_codex.md) — it is the onboarding entry point for contributors and AI agents, covering contribution rules, coding standards, and references to all other documents.

## License

MIT
