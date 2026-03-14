# Utilities Design — MarsinDictation

> `util/` is the home for standalone dev scripts and tools that don't belong in the main codebase or `devtool/deploy.py`.

See also: [`00_codex.md`](../00_gol/00_codex.md) → Repository Structure, [`05_temp_files.md`](../00_gol/05_temp_files.md) → Temp Files

---

## Purpose

The `util/` directory collects small, self-contained scripts needed during development but not part of the shipping product. These are tools that agents and developers use for setup, testing, debugging, and data preparation.

| Property | Rule |
|----------|------|
| Location | `ROOT/util/` |
| Language | Typically Python (cross-platform, already required for `deploy.py`) |
| Dependencies | Auto-install via `pip` if missing (scripts must be self-bootstrapping) |
| Committed | Yes — utilities are version-controlled (unlike `tmp/` output) |
| Output | Utilities should write results to `tmp/` or to an explicitly specified path |

---

## Utilities

### `util/record.py` — Audio Recorder

Records audio from the default microphone and saves a WAV file. Used to capture test audio for transcription pipeline tests.

**Usage:**
```bash
# Record until ENTER is pressed
python util/record.py windows/MarsinDictation.Tests/TestData/test_audio.wav

# Record for a fixed duration
python util/record.py tmp/test.wav --duration 3

# Custom sample rate
python util/record.py tmp/test.wav --rate 44100
```

**Format:** WAV, 16-bit PCM, mono, 16 kHz (default)

**Dependencies:** `sounddevice`, `numpy` (auto-installed on first run)

**Why this exists:** The `deploy.py --record` mode launches the full WPF app and relies on signal file handshakes that proved unreliable across `dotnet run` process boundaries. This standalone Python script is a simpler, more reliable alternative for capturing test audio.

---

## Adding New Utilities

When adding a new utility:

1. Create `util/<name>.py` with a `main()` entry point
2. Add `argparse` for CLI args and `--help` support
3. Auto-install any pip dependencies if missing
4. Add documentation below in this file
5. Keep it self-contained — no imports from the main C# codebase
