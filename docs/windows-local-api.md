# Windows local transcription API

Windows 1.0.3 includes API version 1 in the normal desktop application and installer.
Launch MarsinDictation normally from Start or the desktop shortcut. While the tray app
is running it listens only at `http://127.0.0.1:6976`. Quitting the tray app stops it.
This is not a Windows service. macOS does not implement this endpoint.

## Requests and responses

Use a native HTTP client with that exact numeric host and port. No authentication is
required: other local programs/users can call this service. It is not reachable from
another computer or a phone. Browser `Origin` headers, non-`none` `Sec-Fetch-Site`
headers and a different Host are rejected. No CORS permission is returned.

`GET /health` returns 200 when the embedded model is loaded:

```json
{"service":"marsin-dictation","apiVersion":1,"version":"1.0.3.0","backend":"embedded-whisper","model":"ggml-large-v3-turbo-q5_0.bin","language":"en","ready":true,"reason":null}
```

Before loading finishes or after loading fails, health returns 503 with `ready:false`
and `reason:"model_loading_or_failed"`. If the model was absent at startup, the
reason is `model_missing`. Health reports model readiness, not inference availability:
it remains ready while transcription is busy. Model/language are startup snapshots;
restart the app after changing those settings or adding a missing model.

`POST /transcribe` accepts the WAV bytes directly in the body:

- `Content-Type: audio/wav` (optional MIME parameters are accepted).
- A known `Content-Length`; chunked requests are rejected.
- RIFF/WAVE, PCM format 1, 16-bit signed samples, mono, 16,000 Hz.
- At most 4,194,304 bytes including the header; nonempty audio up to 120 seconds.
- Consistent RIFF and chunk lengths, frame size and byte rate. No duplicate format
  or data chunks; format must precede data. Padded ancillary RIFF chunks are allowed.

Convert m4a, webm or other formats to this WAV format before sending. A successful
200 response has this shape (text varies):

```json
{"text":"Hello world.","backend":"embedded-whisper","model":"ggml-large-v3-turbo-q5_0.bin","language":"en","version":"1.0.3.0"}
```

PowerShell example using an existing normalized WAV:

```powershell
Invoke-RestMethod http://127.0.0.1:6976/health
Invoke-RestMethod -Uri http://127.0.0.1:6976/transcribe -Method Post `
  -ContentType audio/wav -InFile .\speech.wav -TimeoutSec 135
```

Errors contain `{"error":"code"}` and never include exception messages or paths:

| HTTP | Error code | Meaning |
|------|------------|---------|
| 400 | `pcm16_mono_16000_wav_required` | Invalid WAV, sample format, chunks or duration |
| 400 | `incomplete_audio` | Body ended before its declared length |
| 403 | `local_client_required` | Remote, browser or incorrect Host request |
| 404 | `not_found` | Unknown route (including non-GET `/health`) |
| 405 | `post_required` | `/transcribe` requires POST |
| 408 | `transcription_timeout_or_shutdown` | Upload/inference cancellation or shutdown |
| 411 | `content_length_required` | Unbounded/chunked upload |
| 413 | `audio_too_large` | Declared body exceeds 4 MiB |
| 415 | `audio_wav_required` | Incorrect/missing Content-Type |
| 422 | `no_speech_recognized` | Inference returned no recognized speech |
| 429 | `transcription_busy` | API upload or shared embedded inference is occupied |
| 503 | `embedded_model_not_ready` | Missing/unloaded model |
| 503 | `embedded_transcription_failed` | Embedded processing failed |

HTTP.sys may reject malformed HTTP before application routing, using its own response.
Upload reading has a 10-second deadline. The admitted request has a two-minute
cancellation deadline, including upload time. Native inference cancellation is
cooperative. Shutdown/disconnection can terminate the connection before error JSON
arrives; clients must handle transport failure as well as HTTP errors.

Only one API request is admitted at once. Extra API requests receive 429; there is
no API inference queue. With the embedded desktop provider, hotkey transcription
shares the same model and gate: API calls return 429 if desktop inference owns it;
desktop inference waits if the API owns it. Retry 429 after a short delay. Health
remains responsive during upload/inference. Use the response status, not health
alone, to decide whether an individual request succeeded.

## Local processing and recovery

The API always uses embedded Whisper, even if desktop dictation uses OpenAI or
LocalAI. It never falls back to cloud, injects text, changes the clipboard, stores a
transcript in desktop history, accepts filesystem paths, downloads a model or
retains uploaded audio after processing. Audio stays in transient process memory.
The model is found beside the installed executable first, then in the configured
model directory. Metadata exposes only its basename. API responses disable caching.

If health cannot connect, check that the tray app is running. Check
`%LOCALAPPDATA%\MarsinDictation\logs\app.log` for listener/model startup messages.
Another listener on port 6976 disables this API while desktop dictation continues;
identify that listener, resolve the collision and restart MarsinDictation. Do not
add a URL ACL, firewall opening or a LAN binding. If health stays 503, check the
configured model file/language and restart after correcting them. There is no
automatic model-load retry after startup failure.

## Official Windows build and update

Use the standard Windows installer for new installations and updates. It bundles
the self-contained x64 .NET runtime, native Whisper assets and default model:

```powershell
python devtool/deploy.py windows --package
# Output: tmp\installers\MarsinDictation_Setup_Windows.exe
# Build the same installer and open its UAC wizard:
python devtool/deploy.py windows --install
```

Prerequisites: Python, .NET 8 SDK and Inno Setup 6 compiler (`iscc` on PATH,
standard Program Files location, or `ISCC_PATH` pointing to `ISCC.exe`). The model
is downloaded to `tmp` during packaging if it is not already cached. Packaging runs
offline automated tests, publishes Release and derives installer version from the
Windows app project. Packaging/build/test do not stop a running installed app.

Close dependent local clients before updating. Run the generated installer and
approve its normal Windows UAC prompt. The installer can request closing files
in use, preserves AppData settings/history/models and never restarts the app.
After it finishes, open MarsinDictation from Start/desktop as your normal user and
check health/version. Embedded API use requires no provider key or `.env` copy.
No installer launches the desktop app from an elevated process. Keep a prior full
installer for recovery; reinstall it normally if a full update must be reverted.

`devtool/install_local_api_update.ps1` and the old 1.0.1 four-file payload are
historical recovery tools, not the supported full release/update path. Do not apply
that patch or its rollback over a different release.
The recovery helper enforces this scope for both apply and rollback: only installed
versions 1.0.0.0 and 1.0.1.0 are accepted; a newer or unknown version is rejected
before process inspection/stopping, backup creation or file copying.

Default deploy tests exclude `LocalEmbedded`, `Hosted` and `GPU_Benchmark` categories.
Run the real installed-model/API test explicitly; it fails if its existing AppData
model or repository sample is unavailable, rather than reporting a skipped success:

```powershell
dotnet test windows/MarsinDictation.Tests -c Release --filter FullyQualifiedName~InstalledEmbeddedModel_TranscribesKnownAudio_ThroughRealApi
```

This test loads the existing model, sends known audio through real loopback HTTP,
checks hello/world and verifies shared-client shutdown behavior. It does not prove
an installer was applied, microphone capture worked or another app received text.
