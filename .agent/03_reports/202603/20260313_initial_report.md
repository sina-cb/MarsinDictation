# Report: Initial Setup — 2026-03-13

## Summary

Established the MarsinDictation repository structure, governance documents, and v0 design documents for Windows and macOS.

## Work Completed

### Repository Setup
- Created `.gitignore` with standard exclusions
- Created `README.md` with project overview

### Design Documents
- **Aspirational Design** — long-term cross-platform target architecture
- **Windows v0 Design** — detailed implementation spec including hotkey management, WASAPI audio capture, dual transcription providers (OpenAI + LocalAI), injection ladder with clipboard preservation, recovery hotkey, transcript state model, and acceptance criteria
- **macOS v0 Design** — parallel spec using Swift, CGEvent tap, AVAudioEngine

### Governance Documents
- **Codex** — agent onboarding rules, contribution philosophy, coding standards
- **Privacy & Security** — audio data handling, API key storage, microphone access
- **Git Requirements** — branching, commit format, tag-based versioning
- **Build & Deploy** — unified `deploy.py` design for all platforms

### Key Design Decisions
- LocalAI over Ollama for local transcription (OpenAI-compatible endpoint)
- Whisper.net/whisper.cpp designated as last-resort requiring approval
- Clipboard preservation as explicit requirement for injection
- DPAPI for API key storage on Windows
- 25 MB upload guard with auto-stop behavior
- Three-state transcript model: `success`, `pending`, `failed_transcription`

## What Was Not Done
- No code has been written yet — all work was design and documentation
- `deploy/deploy.py` does not exist yet (placeholder design only)
- iOS and Android designs are not started

## Next Steps
- Begin Windows app scaffolding (Phase 1 of project plan)
- Implement core infrastructure: solution structure, tray icon, hotkey manager
