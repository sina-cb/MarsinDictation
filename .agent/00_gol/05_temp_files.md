# Temporary Files Spec — MarsinDictation

> All temporary, transient, or disposable files go in `ROOT/tmp/`. This directory is gitignored and never committed.

See also: [`00_codex.md`](00_codex.md) → Repository Hygiene

---

## Purpose

The `tmp/` directory is the single designated location for anything that is:

- generated during development or testing
- not source code
- not meant to be committed
- expected to be deleted or recreated at any time

This keeps the repo clean and avoids accidental commits of machine-specific, session-specific, or sensitive artifacts.

---

## What Goes in `tmp/`

| Category | Examples |
|----------|----------|
| **Logs** | App runtime logs, deploy logs, test run logs |
| **Audio** | Recorded WAV files, temp audio chunks during dictation |
| **Transcripts** | Raw API responses, intermediate transcription results |
| **One-off scripts** | Debugging scripts, quick test harnesses, scratch files |
| **Build diagnostics** | Profiling output, heap dumps, crash reports |
| **Test artifacts** | TRX files, coverage reports, temp test databases |
| **Agent scratch files** | Agent-generated temp analysis, intermediate outputs |

---

## What Does NOT Go in `tmp/`

| Category | Where It Goes Instead |
|----------|-----------------------|
| Design docs | `.agent/01_designs/` |
| Governance specs | `.agent/00_gol/` |
| Source code | `windows/`, `devtool/`, etc. |
| Secrets / keys | `.env` (gitignored) |
| User data (production) | `%APPDATA%/MarsinDictation/` |
| Build output | `windows/**/bin/`, `windows/**/obj/` (gitignored) |

---

## Rules

### 1. `tmp/` is Always Gitignored

The entire `tmp/` directory is listed in `.gitignore`. Nothing inside it should ever appear in a commit.

### 2. No Assumptions About Contents

Any file in `tmp/` may be deleted at any time. Code must not depend on `tmp/` files being present at startup. If a subdirectory is needed, create it at runtime.

### 3. Subdirectory Convention

Use descriptive subdirectories to keep `tmp/` organized:

```
tmp/
  logs/          ← runtime and deploy logs
  audio/         ← temp WAV captures
  transcripts/   ← raw API responses
  test/          ← test runner artifacts (TRX, coverage)
  scratch/       ← one-off scripts, debug output
```

### 4. Agents Must Use `tmp/` for Scratch Work

When an AI agent needs to create a temporary script, dump debug output, or generate intermediate analysis, it must write to `tmp/` — never to the project source tree.

### 5. The App Should Use `tmp/` for Dev-Mode Artifacts

During development, the app may write logs and temp audio to `tmp/`. In production, the app writes to `%APPDATA%/MarsinDictation/` (see privacy spec).

---

## Cleanup

- `tmp/` can be safely deleted at any time: `rm -rf tmp/`
- `deploy.py clean` should clear build artifacts but does **not** touch `tmp/` — that's the developer's choice
- Tests that use temp files should use system temp (e.g., `Path.GetTempPath()`) rather than `tmp/`, so they clean up via `IDisposable`

---

## Cross-References

- [`00_codex.md`](00_codex.md) → "Do not leave behind dead scaffolding, misleading comments, random temp files, or machine-specific assumptions"
- [`01_privacy.md`](01_privacy.md) → Audio and transcript data handling rules
- [`03_build_and_deploy.md`](03_build_and_deploy.md) → Build output locations
- [`04_agent_driven_test.md`](04_agent_driven_test.md) → Test artifacts and TRX files
