# Legacy patch rollback safety review — 2026-10-25

User requested three Astra medium reviews after installing Windows 1.0.3, with
fixes limited to P0/P1 or concrete security/safety issues. The API and runtime
reviews found no such blocker. Release review identified one concrete safety
defect: the legacy four-file patch checked installed-version compatibility only
during apply, allowing an old rollback to partially downgrade a full 1.0.3 install.

Branch `codex/legacy-api-rollback-guard` starts at reviewed main `15c087c`.
Moved the existing version guard ahead of the apply-only block so both apply and
rollback accept only 1.0.0.0/1.0.1.0. Newer/unknown versions fail before privilege
checks, process inventory/stopping, backup creation or copying. Supported legacy
recovery and existing identity/race checks remain intact.

`devtool/test_local_api_update.ps1` now executes the actual rollback preflight with
simulated filesystem reads and traps for process/file effects. 1.0.0.0/1.0.1.0
reach the privilege boundary; 1.0.3.0/2.0.0.0/unknown fail at the compatibility guard.
Together with the prior selection/race cases, **20/20 passed**:

`pwsh -NoProfile -ExecutionPolicy Bypass -File devtool/test_local_api_update.ps1`

Log: `tmp/rollback_guard_review/updater-tests.log`. Only simulated preflight was
executed: no real rollback/install, process stop or installed file modification.
Retained helper at `tmp/releases/MarsinDictation-1.0.1-local-api/` was updated to the
exact guarded source; both SHA256:
`C92779BF241F3615773F3F635434B679A40E1AECF32E47D398A28112015F261C`.
Previous helper preserved at `tmp/rollback_guard_review/retained-helper-before.ps1`.
Recovery payload/backups and full 1.0.3 installer remain untouched. These helper,
test and documentation changes are not installer inputs; no installer rebuild.

Fresh independent Astra runtime evidence confirms **installed 1.0.3.0** App/Core
match the published manifest hashes. Root-authorized normal launch PID 82768 had a
non-elevated token, health 200/ready, loopback-only listener, and one real local WAV
transcription 200 in 1051ms with hello/world checks. 27 API boundary tests also
passed without skips. Evidence: `tmp/astra_runtime_review/{launch.json,runtime.json,api-tests.trx}`.
No installer wizard, microphone or text injection validation is claimed.

Pending at checkpoint: narrow Astra release re-review, then coordinator-approved
merge/push. No iPhone/MagicVJ changes or app restart by the safety-fix worker.
