# Windows API integration checkpoint — 2026-10-25

## Scope and ownership

User authorized Windows API review/integration, Sol 6.1 implementation/review/runtime
verification, and final merge/push to main. iPhone work is deferred. No MagicVJ
source/process/lighting changes. Lead worker owns edits/git/artifacts; independent
reviewer and runtime verifier report to the coordinating chat.

## Reconciliation and preserved work

- Started at `codex/local-dictation-api` / `1424d58`, API implementation `34abf73`.
- Fetched live `origin/main=9a49b9a` (23 newer commits) and merged it into
  `codex/windows-api-integration` in `ac14be7`, with no conflicts or discarded history.
- Existing dirty updater/report/test changes were backed up under
  `tmp/windows_api_integration/pre_reconcile/`. A concurrent user-authorized worker
  committed those related changes in `937c804`; root identified their provenance.
  They are preserved. No force-push or history rewrite.
- Final main integration must follow repository squash-merge convention after
  independent review and verification. No tag or GitHub release publication requested.

## Review findings and fixes

- Windows HTTP.sys pending body reads did not honor cancellation once started.
  Explicitly bound the read wait, abort/observe any pending read and release admission.
  Raw TCP tests prove a one-byte stalled upload returns 408 at its deadline, a later
  complete upload succeeds, and synchronous shutdown completes within five seconds.
- Embedded inference swallowed cancellation as failed transcription. Propagate
  cancellation and check the token after native iteration and after the API callback,
  preventing cancelled partial transcripts from appearing as success.
- API Dispose is idempotent; shutdown cancels and drains active inference.
- Ordinary deploy tests now exclude model-dependent, hosted and GPU benchmark tests;
  the explicit real-model test still fails if the installed fixture is missing.
- Windows app/installer version is 1.0.3. Installer derives version from the project.
  Build/test/package do not stop the running installed app. `--install` opens the
  same full Inno installer used by `--package`; removed blind mirror-copy/elevated
  cmd copying and automatic `.env` overwriting. Installer does not relaunch the app.
- UAC launch failures/cancellation fail the deploy command, including terminating
  PowerShell errors. Mocked orchestration tests cover version/launch/error behavior.
- Full API/status/limits/startup/security/recovery/update guide:
  `docs/windows-local-api.md`. README/devtool README link to it.

## Current validation evidence

All generated logs/receipts stay under `tmp/windows_api_integration/`:

- `dotnet test windows/MarsinDictation.Tests -c Release --filter
  'Category!=LocalEmbedded&Category!=Hosted&Category!=GPU_Benchmark'`: **70 passed,
  zero failed/skipped**. `tests/offline.trx`, `offline.log`. The normal package path
  independently reran the same 70 tests successfully.
- `dotnet test windows/MarsinDictation.Tests -c Release --filter
  FullyQualifiedName~InstalledEmbeddedModel_TranscribesKnownAudio_ThroughRealApi`:
  **1 passed, zero failed/skipped**, including actual local model/HTTP hello-world,
  in-flight native cancellation and subsequent shared-client inference/disposal.
  `tests/embedded-final.trx`, `embedded-final.log`. No hosted invocation.
- `python -m unittest discover -s devtool -p test_deploy_windows.py`: **2 passed**,
  `packaging-tests.log`; these simulate orchestration without changing real processes.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File devtool/test_local_api_update.ps1`:
  **15 passed**, `updater.log`; pure process-selection/race checks, no real stop/copy.
- `python devtool/deploy.py windows --package`: Release app/test builds and offline
  tests passed; self-contained publish and Inno compiler completed successfully.
- Exact published Core plus native/runtime assets copied into `candidate-runtime/`;
  only App.dll replaced by a temporary headless harness in `runtime-harness/`.
  Separate ephemeral port, existing model/sample: process 58680 exited 0, runtime
  **8.0.32**, health **200**, transcription **200**, hello/world checks true.
  `candidate-runtime/proof.json`; no transcript content in the receipt.
  This proves the published Core/runtime combination, not WPF/installer installation.

## Installed versus built

Independent verifier found an already-running normal-user Program Files app PID
76792, version **1.0.1.0**, limited/non-elevated token. Existing patch DLL hashes
matched its approved payload. Health 200/ready and real sample transcription 200
passed in 1068ms with hello/world checks. Evidence:
`tmp/installed_verification_20261025_050744_561/installed-api-receipt.json`.

This older patch was installed/launched by another user-authorized chat before
these checks. This integration did not update, launch or stop it. MagicVJ may be
actively consuming its API. Version 1.0.3 is built/tested separately and must not be
reported as installed. Full installer application/UAC/tray/hotkey/microphone/text
injection validation remains unperformed for 1.0.3; no passing claim is made.

Compiler discovered read-only at the existing Antigravity IDE bundled Inno Setup
6.4.1 path; valid Martijn Laan Authenticode signature. No compiler installation or
download was necessary. Set `ISCC_PATH` to use a nonstandard existing compiler.

## Built full installer

`tmp/installers/MarsinDictation_Setup_Windows.exe`: **568,158,139 bytes**, file/product
version **1.0.3**, SHA256
`F9AD7FA50DFF8F0D7F1431FF496D2006D5694A4801AC5902584C50B79FA6F256`.
Adjacent `MarsinDictation_Setup_Windows.manifest.json` records hashes and built-only
status. App DLL SHA256
`7BD24E46A811524BFA6F163CE33319D6C741337EEF49CBFB19E5D179D95DA2C3`;
Core DLL SHA256
`87C3C769F8E1B9743FC9A87F2FB6B0260DA28D31640710A837DA916C4B44529E`.
App assembly version 1.0.3.0; Core retains its separate default assembly version
1.0.0.0. Build informational metadata records `937c804` plus the then-uncommitted
reviewed integration source; final integration commit is recorded in Git history.

Independent runtime verifier inspected all 494 publish files and confirmed byte
equality with the tested stage except its deliberate harness App.dll replacement.
Sample equals the repository fixture. Native Vulkan log identifies RTX4090;
runtimeconfig/deps and runtime DLLs match .NET 8.0.32 assets. No redundant model
execution or installed app restart was necessary for that independent audit.

## Remaining at this checkpoint

Record independent verifier/reviewer final signoff, then squash merge/push main
after coordinator go-ahead.
Do not install/restart over the active 1.0.1 app. Keep old patch/backups as recovery
artifacts; supported future updates use the full installer and normal-user launch.
