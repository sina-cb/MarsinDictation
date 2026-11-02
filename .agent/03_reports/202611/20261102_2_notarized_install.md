# macOS 1.0.5 notarized installation — 2026-11-02

The installed `/Applications/MarsinDictation.app` is now **1.0.5 build 5**, signed
with **Developer ID Application**, notarized, and accepted by Gatekeeper. This
supersedes the earlier ad-hoc and Apple Development installations. The user requested
fully signed distribution builds for normal installation; neither development
signature is an acceptable substitute for that request.

## Artifact and validation provenance

- Artifact production commit: `09c1a0d0d5f032c776790f3418c20872810924f6`.
  [Signed-package job/run](https://github.com/sina-cb/MarsinDictation/actions/runs/41520836144/job/125536118057)
  completed successfully. Apple accepted notarization; DMG stapling, ticket validation,
  signature verification and Gatekeeper assessment succeeded. All three required
  project/SwiftWhisper/whisper.cpp MIT notices were included **before signing**.
- Later validation commit: `238d990c2db80a3197d722d1ede51141a3cbd287`.
  [Test job/run](https://github.com/sina-cb/MarsinDictation/actions/runs/41521687756/job/125539885269)
  completed successfully, including real local model/API tests, deployment regressions
  and the universal app build. Its separate signed-package job was still queued when
  the verified source-equivalent package was installed. After installation, its redundant
  manual packaging run was canceled to avoid another equivalent build; the completed
  successful test-job evidence remains. The separate PR validation was left active.
- `git diff --name-only 09c1a0d..238d990` listed only
  `mac/Tests/LocalApiTests.swift`. Those changes align test client and cooperative
  completion waits with the documented API deadline. **All production source,
  dependencies, app metadata, entitlements, packaging and workflow inputs are unchanged.**
  The source-equivalent signed artifact was authorized for installation using this
  explicit dual-commit proof. This does **not** claim every job passed in one run:
  the earlier run's test job failed because its test-only client deadline was too short.

## Local verification and installation

The downloaded DMG passed strict signature checks, `stapler validate`, and Gatekeeper
assessment with `source=Notarized Developer ID`. It was mounted read-only without UI.
Before replacement, its nested app passed strict/deep signature verification and
Gatekeeper execute assessment with the same notarized source. The app had a trusted
Developer ID Application chain, secure signing timestamp, hardened runtime, universal
`x86_64 arm64` executable, and version **1.0.5/build 5**. No signed app resources were
modified after verification.

The current app was staged, verified again, and replaced only after stopping its exact
installed process. The replacement was launched once by the installed path. Installed
signature verification and Gatekeeper assessment passed. The read-only image was
subsequently detached. User settings, Keychain, transcript history and model cache were
preserved. No OS permission reset, UI clicks, private-key extraction or local keychain
access-control change occurred.

Observed installed process: **PID 50935**. GET /health returned **200**, `ready:true`,
`service:"marsin-dictation"`, `apiVersion:1`, `backend:"embedded-whisper"`,
`version:"1.0.5"`, model basename `ggml-base.en.bin` and language `en`. The repository's
public hello/world WAV transcribed locally; no private audio or transcript was used.

The app's actual startup permission line reported:
**Accessibility granted — auto-paste will work.** No text was injected into a user app;
this proves current Accessibility trust, not a manual end-to-end paste test. Signing,
notarization and Accessibility remain separate checks.

Authorized cleanup completed: nine superseded app/stage items were moved to Trash.
The targeted installed-app inventory contains only the active `/Applications` 1.0.5
app. One verified notarized **1.0.4/build 4** distribution DMG is retained privately
for rollback, alongside the final 1.0.5 DMG. Both retained images passed strict
signature, stapled-ticket and Gatekeeper checks again after cleanup. No user data,
credentials or preferences were removed. Trust checks used the normal unsandboxed
system context; sandbox-restricted trust checks are not used as installation evidence.

[Merge request](https://github.com/sina-cb/MarsinDictation/pull/2).
No tag, release or merge was created by this installation.
