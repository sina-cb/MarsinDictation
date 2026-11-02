# macOS local transcription API

MarsinDictation 1.0.5 (build 5) implements the Windows API version 1 contract at
`http://127.0.0.1:6976`. Start the normal menu bar app; quitting it stops the API.
The service is reachable by local programs/users without authentication, never over LAN.

Use the exact numeric host and a native client. Browser Origin, non-none Sec-Fetch-Site,
incorrect Host and malformed/duplicate headers are rejected. No CORS is enabled.

```sh
curl --fail-with-body http://127.0.0.1:6976/health
curl --fail-with-body --max-time 135 -H 'Content-Type: audio/wav' \
  --data-binary @speech.wav http://127.0.0.1:6976/transcribe
```

Health contains `service:"marsin-dictation"`, `apiVersion:1`, `version:"1.0.5"`,
`backend:"embedded-whisper"`, the model basename, startup language, `ready` and `reason`.
Ready returns 200; unavailable returns 503 with `model_missing` or
`model_loading_or_failed`. Busy inference still reports ready. Success returns
`{text,backend,model,language,version}`. Errors, WAV contract and status codes match
[the Windows reference](windows-local-api.md#requests-and-responses).

Upload raw RIFF/WAVE PCM format 1, mono, signed 16-bit, 16000 Hz, with known
Content-Length (no chunked encoding). Maximum 4 MiB including headers and 120 seconds
of nonempty audio. Consistent chunk sizes, frame size and byte rate are required;
padded ancillary chunks are accepted and normalized before inference. No paths or
compressed formats are accepted. Requests have 16 KiB header and 16 concurrent socket
limits; excess sockets close. Malformed HTTP may return `400 invalid_request`.
Upload and header reads have a 10-second absolute deadline. Admitted upload/inference
has a two-minute deadline. Clients must handle disconnects as well as error JSON.

The API loads only a model already present at startup, from the app bundle or
`~/Library/Application Support/MarsinDictation/models`. It never invokes the downloader,
cloud providers, microphone, clipboard, injection or transcript history. Uploaded audio
is transient memory only; API results are never stored or logged. Ordinary embedded
dictation retains its existing first-launch download/retry behavior. If the startup
model was missing, the API remains unavailable even if dictation later downloads it:
restart the app after preparation. Model/language metadata are startup snapshots;
settings changes continue to apply to ordinary dictation on its next use.

API admission is one request with no queue (429 when busy). Embedded hotkey inference
shares the exact model and gate; API returns 429 if hotkeys own it, and hotkeys wait
if API owns it. Different configured model files have separate contexts. Health remains
responsive during model load and inference. Deadline/shutdown cancels cooperatively;
native inference can finish later, retaining its gate/audio until it exits. Late text
is discarded. Peer disconnects may leave work running until completion/deadline; the gate
remains held throughout. Quitting closes listener/sockets immediately without unloading active work.
A port collision disables this listener while desktop dictation continues; resolve the
other listener and restart. Missing models, detected invalid/truncated metadata, or native NULL load failures return 503,
with no API retry/download. The pinned legacy native loader is not hardened against arbitrary
corrupt tensor payloads; other model corruption can still abort the process. Use trusted model
files, and replace a suspected corrupt file before restarting. No firewall or URL ACL changes are required.

## Build and update

Build a local development .app without installing or running it:

```sh
# Requires Xcode tools and XcodeGen on PATH (or XCODEGEN=/absolute/path/to/xcodegen).
sh devtool/build_mac_local.sh
# tmp/mac-api-release/Build/Products/Release/MarsinDictation.app
```

The script regenerates the project, builds universal arm64/x86_64 Release, copies
project/SwiftWhisper/whisper.cpp MIT licenses into Resources/Licenses, and ad-hoc signs
locally. It uses no signing identity credentials or notarization, includes no developer
.env, and downloads no speech model. Swift dependencies may resolve from their pinned
upstream revisions when not cached. This is a local development artifact, not a notarized
installer. Keep the licenses with the .app when copying it.

For a normal installed-app update, use a Developer ID Application signed,
notarized distribution artifact and require Gatekeeper acceptance. Do not replace
a requested fully signed installation with this ad-hoc development build.
Use `python3 devtool/deploy.py mac --package` with distribution credentials, or the
signed CI artifact for the exact authorized branch/commit. Follow the
[verified update procedure](../mac/README.md#updating): check the DMG ticket/signature
and mounted app's identity/signature/version/Gatekeeper status before replacement,
keep one private rollback, quit clients/app, and replace only the app bundle.
Preserve settings, Keychain, history, and models; remove only superseded app copies
after validating the installed app and health/version. `mac --clean` deletes user
data and must never be used for this cleanup.

Only when the user explicitly requests a development installation may the ad-hoc
artifact above replace the app. Its build process itself neither installs nor
stops/restarts an app. Accessibility may need granting again after identity changes;
it is separate from signing/notarization. The local upload API requires neither
microphone nor Accessibility permission.

## Validation

`python3 devtool/test_mac_models.py` runs local fixture model tests and socket API tests.
To include real existing-model/API/shared-gate evidence without downloads:

```sh
MODEL_TEST_REAL_MODEL='/path/to/ggml-base.en.bin' \
API_TEST_AUDIO="$PWD/windows/MarsinDictation.Tests/TestData/FirstHello.wav" \
  swift test --package-path mac --scratch-path tmp/swift-tests --filter LocalApiTests
```

The API fixture defaults to the repository hello/world sample (override with API_TEST_AUDIO),
independently of MODEL_TEST_AUDIO used by CI. The existing fixture test checks hello/world; the separate legacy model test expects
its synthetic testing/dictation sentence. No microphone, paste, permission dialogs,
installed-app lifecycle or UI behavior is exercised by these tests.
