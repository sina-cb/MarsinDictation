# Windows local transcription API — 2026-10-25

## Latest installed proof — 05:02 PDT

The user successfully applied the main-install update at04:56:10. Backup `tmp/releases/MarsinDictation-1.0.1-local-api/backups/local_api_backup_20261025_045604/` preserves original1.0.0.0 plus the successful `files_updated` receipt. All four installed files independently match the approved1.0.1.0 payload hashes. A repeated Apply failed because the app was closed and the old preflight required one process; that repeat performed no backup/stop/copy. No further reinstall is needed.

The user then normally launched installed executable PID76792 at05:01:29PDT. Agent did not launch a duplicate or stop any process. Tool token was verified medium/non-admin. Fresh GET6976/health200 reports version1.0.1.0, embedded-whisper and readytrue. One POST of normalized known `FirstHello.wav` returned200 in1387ms with hello/world assertions true and matching local backend/version. No hosted request/microphone recording/engine mutation. Receipt `tmp/installed_local_api_verification.json` omits transcript content.

Updater follow-up now supports closed apps, discovers the current exact installed executable without a historical fixed PID, preserves optional explicit identity guards, refuses unknown/multiple installed identities and rechecks before stop/copy. All four installed hash matches return `already_current` before any backup/stop/copy. `devtool/test_local_api_update.ps1` covers15 selection/identity/race cases without real process/file mutation; all15 pass. Packaged helper/README are updated without changing approved native payload. Actual medium-token packaged `-Apply` returned `already_current`, filesChangedfalse/processesChangedfalse, preserving the successful original backup/receipt. Astra independently approved final source/package equality, all four unchanged payload hashes, tests and README. No updater rerun is needed for this installation.

## Initial implementation and prepared-package proof (historical)

User requested a minimal API for MagicVJ to reuse MarsinDictation's local model and an update for the main installation. Implemented on `codex/local-dictation-api`, without provider keys, model downloads, secrets/config changes, commits to main, or a remote push. Installation is prepared for the user; it has **not** been applied.

## Implemented contract

Loopback `http://127.0.0.1:6976`: `GET /health` reports local embedded readiness/version/model/language; `POST /transcribe` accepts uploaded PCM16/16kHz mono WAV, known Content-Length <=4 MiB and <=120s data. Response `{text,backend,model,language,version}`. No filepath input, desktop injection, audio retention, cloud fallback or CORS. Reject browser Origin/cross-site/Host mismatch. Bounded one-request admission and shared embedded model/inference gate with desktop hotkey. Port collision does not prevent desktop use. API always selects embedded even if desktop provider is cloud.

Changed source: `windows/MarsinDictation.Core/Api/LocalTranscriptionApi.cs`, `Core/Transcription/WhisperTranscriptionClient.cs`, `App/App.xaml.cs`, `App/MarsinDictation.App.csproj` (1.0.1), `Tests/LocalTranscriptionApiTests.cs`; README and `devtool/install_local_api_update.ps1` document/package the update.

## Proof

- Release app build: zero errors/warnings.
- New API targeted tests: **25/25**; real HTTP guards, fake error/busy behavior, malformed/oversize/media/browser input, nonfatal collision and real existing local GGML model inference. Exact verbose log `tmp/local_api_targeted_final.log`.
- Existing non-native regression tests: **43/43**, `tmp/local_api_existing_regression.log`. Hosted OpenAI and unrelated GPU benchmark excluded deliberately.
- UI shutdown regression: real inference initiated under observed caller synchronization context, synchronous Dispose completes with **zero** posted caller-context continuations; disposed model cannot reload/transcribe. ConfigureAwait alone was insufficient because Whisper.net's iterator captured caller context internally; native inference now enters on the thread pool.
- Retained installed distribution compatibility: copied installed apphost/runtimeconfig/deps/runtime/native files into a temporary headless harness directory, replaced candidate Core, referenced existing appdata model without copying it. `tmp/local_api_compat_stage/proof.json`: runtime **8.0.25**, health **200**, transcription **200**, expected hello/world true, process59548 exited0. Installed Vulkan runtime found RTX4090. Harness did not start WPF/hotkeys or modify the installed app.
- Packaged Core bytes equal the compatibility-tested Core. Updater PowerShell parser: zero errors; plan-only invocation succeeds.

Initial broad test attempt overlapped two native model fixtures and crashed in native model initialization. A subsequent overlapping attempt produced two no-speech failures. Native initialization is now serialized and the new native fixture collection does not overlap other collections; the final targeted and non-native runs above are the reliable current proof. No broad passing-suite claim is made.

## Prepared main-install update

Fixed package: `tmp/releases/MarsinDictation-1.0.1-local-api/`, containing portable updater, README, four payload DLL/PDB files and targeted SHA256 manifest. The package excludes models, environment/settings/history, runtime/native files and credentials. It patches **only** `MarsinDictation.App.dll`, `MarsinDictation.Core.dll` and their two matching PDBs under `C:\Program Files\MarsinDictation`; existing executable bootstrap/runtime/deps remain in place.

Current installed app remains PID45576, executable `C:\Program Files\MarsinDictation\MarsinDictation.App.exe`, start UTC `2026-10-15T20:46:56.4803376Z`, installed App.dll version1.0.0.0. Local API is not installed/listening. Current token is non-elevated and Program Files Users ACL permits ReadAndExecute only. User must run the reviewed updater in an Administrator PowerShell through normal Windows UAC; it does not self-elevate, alter ACLs, or bypass UAC.

Updater validates payload manifest, preserves a four-file backup, verifies exact existing PID/path/start time, attempts graceful close before stopping that identified app, then copies only the four files. It **never launches the app from the elevated shell**: the user closes Administrator PowerShell and starts the existing app normally from Start/desktop. Backup `manifest.json` plus `update_receipt.json` record file state and `launchRequired:true`, without invented process/health results; README supplies rollback commands. Rollback permits zero processes for a startup-crash case, otherwise requires exact current identity, and likewise requires normal user launch afterward. No update/rollback was executed. Astra approved API source, runtime compatibility and payload consistency, then independently approved the final manual-normal-launch helper/README delta: zero process launch calls, exact source/package helper equality, unchanged backup/hash/identity guards and honest file-only receipts.

Remaining: user-run UAC update, fresh installed version/health/real WAV check, MagicVJ broker integration/runtime restart and physical phone validation. No remote publication or automated review consumer was started.
