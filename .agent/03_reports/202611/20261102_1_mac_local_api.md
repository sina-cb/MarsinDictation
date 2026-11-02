# macOS local API 1.0.5 — 2026-11-02

macOS 1.0.5 build 5 was built, installed at `/Applications/MarsinDictation.app`, and
launched once after the user's explicit update authorization and Astra review. The
installed API is ready and transcribed the repository hello/world fixture locally.
No microphone or text injection was used for validation. Human final acceptance remains pending.

## Implementation

Loopback `127.0.0.1:6976` GET /health and raw WAV POST /transcribe implement Windows
API v1 fields/errors. Limits: 16 connections, 16 KiB headers, 4 MiB body, 120 seconds
PCM, 10-second upload/header reads, two-minute admitted request deadline. Strict
Host/Origin protections; no API downloader, cloud provider, microphone, clipboard,
injection or history dependency. Audio/text are transient and not logged/stored.

Weak shared model registry and per-model inference gate preserve hotkey behavior:
API rejects busy inference; desktop waits. Shutdown/deadline cancel cooperatively,
retaining the gate until native completion. Registration latch avoids stop/completion
races. RIFF ancillary chunks normalize safely; PCM uses explicit little-endian bytes.

## Astra review fixes

1. API_TEST_AUDIO (repository hello/world by default) is independent of MODEL_TEST_AUDIO,
   which CI uses for its separate synthetic testing/dictation sentence.
2. The client calls the pinned whisper.cpp C API directly, checking a nullable native
   context once rather than SwiftWhisper's trapping nonfailable initializer. A bounded
   GGML metadata/mel-table/allowed-ftype check rejects detected truncated/unsupported
   prefixes before native assertions. Locked cancellation flag is retained through
   native return; language pointer and native context stay alive; cleanup finishes
   before continuation/gate release. Nonzero native status never reads stale segments.
3. Health combines startup availability and loaded readiness, matching POST. A missing
   startup model stays503 even if desktop preparation later loads the pooled client.
4. Local builder creates ignored Local.xcconfig only if absent and preserves an existing
   personal file without reading it. Two focused stub-tool tests prove both paths.

The legacy native loader is NOT hardened against arbitrary corrupt tensor payloads.
Exploratory synthetic malformed tensors exposed native assertions. Those cases are not
claimed recovered. The final isolated probe proves detected truncated/unsupported
metadata and controlled temporary-file disappearance (native NULL) are handled, with
host survival and API503. It never modifies the user's model cache.

## Final proof

- CI-equivalent `MODEL_TEST_REAL_MODEL='<existing base.en cache>' MODEL_TEST_AUDIO='<generated testing/dictation WAV>' python3 devtool/test_mac_models.py`:
  **15 tests, zero skips/failures**, 20.58s, plus isolated CorruptModelProbe PASS.
  Synthetic speech generated with say/afconvert; no microphone or model download.
  Log: `tmp/mac-api-final-review-tests.log`.
- Real API/shared-gate/native-cancellation suite: **9 tests, zero skips/failures**, 15.72s.
  Log: `tmp/mac-api-native-real-tests.log`.
- Real cached-model tests cover hello/world HTTP, both gate ownership directions,
  native 50ms timeout -> cancellation -> gate release -> successful next request.
  Real socket/fake inference tests cover deadline/disconnect ownership, 25 fast
  completions, deterministic stop before registration, missing-model snapshot,
  collision, raw411/413/incomplete400/read408, invalid WAV/headers, no-speech422,
  failure503 and busy429.
- `python3 -m unittest discover -s devtool -p test_deploy_mac_local.py -v`: **2 tests pass**.
- `XCODEGEN='<cached XcodeGen>' sh devtool/build_mac_local.sh`: final universal Release
  **BUILD SUCCEEDED**, three MIT notices, local ad-hoc strict/deep signature verify pass.
  Plist1.0.5/build5; lipo x86_64 arm64; no developer .env. Log: `tmp/mac-api-build.log`.
- Before stopping1.0.4, a complete private mode0700 rollback was made with ditto preserving
  resources/xattrs/ACL. Executable, Info.plist and CodeResources matched exactly. The
  old installed signature was already invalid; it was preserved without re-signing.
  The original installed app was also moved into the private rollback folder.
- Exact old installed PID was terminated gracefully; reviewed1.0.5 was staged, signature/
  version checked, renamed into place and launched once by its exact installed path.
- Installed app PID/version/signature verified. GET /health returned200 readytrue,
  service marsin-dictation, apiVersion1, backend embedded-whisper, model ggml-base.en.bin,
  language en, version1.0.5. POST authorized FirstHello.wav returned hello/world.
- `git diff --check`: clean. No user settings/history/model data or OS permissions changed.

Local artifact: `tmp/mac-api-release/Build/Products/Release/MarsinDictation.app`.
Private rollback: `tmp/rollback-mac-1.0.4-20261102/` (untracked, never publish).
Instructions/limits: `docs/mac-local-api.md`.

Intel compiled but not executed on this Apple Silicon host. Hotkey/microphone/injection,
permission dialogs and UI were not exercised. Artifact is ad-hoc signed, not notarized.
No tag, release or merge was performed. The feature branch is based on current main;
merge-request publication is separate from acceptance and release.
