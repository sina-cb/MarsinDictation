# Privacy & Security Rules — MarsinDictation

This document defines the privacy and security requirements for MarsinDictation.

MarsinDictation captures microphone audio and communicates with transcription APIs. These are high-risk surfaces and must be treated accordingly across all platforms.

---

## Audio Data

- **Never log audio content** — raw audio buffers, base64-encoded audio, and WAV file contents must never appear in logs, debug output, or telemetry.
- **Never retain audio after transcription is complete** — audio buffers are transient working data only. Once transcription finishes or fails, temporary audio should be discarded.
- **Never transmit audio to an endpoint the user did not explicitly configure** — no analytics, no telemetry, no surprise network calls, and no fallback uploads.

---

## Transcribed Text

- **Do not log transcribed text by default** — user dictation is private.
- If temporary debug logging of transcribed text is ever required during development, it must be deliberate, short-lived, clearly marked as sensitive, and removed before release.
- Transcript history is stored **locally only** and never transmitted externally.
- Release builds must not log user-transcribed text.

---

## API Keys and Secrets

- **Never store API keys in plain text** — use platform-appropriate secure storage:
  - **Windows:** DPAPI-backed encryption via `ProtectedData` API
  - **macOS/iOS:** Keychain Services
  - **Android:** EncryptedSharedPreferences or Android Keystore
- **Never commit API keys** to version control, test fixtures, example configs, or documentation.
- Settings files (JSON, plist, etc.) must not contain raw secret values. Secrets are stored separately and referenced by key.

---

## Microphone Access

- Microphone access must be **explicitly requested** with clear user-facing justification on platforms that require it (macOS, iOS, Android).
- The app must handle microphone permission denial gracefully — never crash, always inform the user.
- Audio recording must stop immediately when the user triggers stop.

---

## Network Communication

- The app communicates only with endpoints the user has explicitly configured:
  - OpenAI API (`api.openai.com`)
  - LocalAI server (user-specified local URL)
- No telemetry, crash reporting, analytics, or background network calls are allowed unless the user explicitly opts in.
- All API communication should use HTTPS where applicable.

---

## Local Data

- Transcript history is stored locally in a user-accessible location.
- No transcript data is synced, uploaded, or shared without explicit user action.
- The user should be able to clear all stored transcripts at any time.

---

## Plain Language Rule

When handling user data, assume the default answer is:

- do not log it
- do not keep it longer than needed
- do not send it anywhere unexpected
- do not hide what the app is doing

---

## Default Posture

If in doubt about whether something is a privacy concern, **treat it as one**.

Prefer the conservative path: do not log, do not transmit, do not retain.
