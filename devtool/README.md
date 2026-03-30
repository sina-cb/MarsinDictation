# devtool

Developer tooling for MarsinDictation — build, test, and run from one script.

## Quick Start

```bash
python devtool/deploy.py              # Auto-detect OS → build + test + run
python devtool/deploy.py --run        # Run only (auto-rebuilds if source is dirty)
python devtool/deploy.py --run --hold # Run + tail live logs in terminal
python devtool/deploy.py --build      # Build + test only
python devtool/deploy.py --test       # Build + run all tests
python devtool/deploy.py --test --filter UserVoice --verbose  # Run one test with evidence
```

## Commands

| Command | Description |
|---------|-------------|
| `windows` | Build and run the Windows app (auto-detected on Windows) |
| `mac` | Build and run the macOS app via deploy.py |
| `iphone` | Build the iOS keyboard extension (stub) |
| `android` | Build the Android IME (stub) |
| `kill` | Kill any running MarsinDictation processes |
| `clean` | Clean all build artifacts |

If no command is given, the OS is auto-detected.

## Helper Scripts

| Script | Description |
|--------|-------------|
| `build_icon.ps1` | A PowerShell script that converts a `256x256` PNG icon into a multi-resolution `.ico` file (16x16, 32x32, 48x48, 64x64, 128x128, 256x256) using High-Quality Bicubic interpolation. This ensures crisp rendering in the Windows taskbar, system tray, and desktop shortcut. Called automatically by `deploy.py` during builds. |

## Modes

| Flag | Behavior |
|------|----------|
| *(none)* | Build → test → run |
| `--build` | Build → test (don't run) |
| `--run` | Run only — auto-rebuilds if any source file is newer than the output DLL |
| `--test` | Build → run all tests with evidence output |

## Options

| Flag | Description |
|------|-------------|
| `--hold` | Keep terminal open and tail app logs (`%LOCALAPPDATA%/MarsinDictation/logs/app.log`) |
| `--filter EXPR` | Filter which tests to run (dotnet test `--filter` expression, use with `--test`) |
| `--verbose` | Show full evidence output for all tests |
| `--release` | Build in Release configuration (default: Debug) |
| `--dry-run` | Show what would be executed without running anything |

## Log Tailing (`--hold`)

When using `--run --hold`, the terminal stays open and tails the app's log file in real-time with colorized output:

- **INF** logs — white (normal)
- **WRN** logs — yellow
- **ERR/CRT** logs — red
- **DBG** logs — dim

Log file: `%LOCALAPPDATA%/MarsinDictation/logs/app.log` (truncated on each launch).

Press **Ctrl+C** to stop both the app and log tailing.

## Dirty Detection (`--run`)

When using `--run`, the script compares the newest source file modification time (`.cs`, `.xaml`, `.csproj`) against the compiled output DLL. If any source file is newer → auto-rebuild. If the binary is up-to-date → skip straight to run.

## See Also

- [Build & Deploy Governance](../.agent/00_gol/03_build_and_deploy.md) — full build/deploy design and platform matrix
- [Utilities Design](../.agent/01_designs/03_utils.md) — `util/` directory conventions
- [Project README](../README.md) — project overview and platform status
