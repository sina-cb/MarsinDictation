# Windows local transcription API — 2026-10-25

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

Updater validates payload manifest, preserves a four-file backup, verifies exact existing PID/path/start time, attempts graceful close before stopping that identified app, copies only the four files and restarts the same exe. Backup `manifest.json` plus `update_receipt.json` record prior/new state; README supplies rollback commands. Rollback permits zero processes for a startup-crash case, otherwise requires exact current identity. No update/rollback was executed. Astra independently approved API source, runtime compatibility and the final portable helper/package: all four payload hashes/bytes match publish, packaged helper matches source, and packaged Core matches the compatibility-tested Core.

Remaining: user-run UAC update, fresh installed version/health/real WAV check, MagicVJ broker integration/runtime restart and physical phone validation. No remote publication or automated review consumer was started.
