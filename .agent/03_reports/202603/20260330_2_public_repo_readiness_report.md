# Public Repo Readiness Report: MarsinDictation

**Date**: 2026-03-30
**Status**: Not ready for a public announcement yet
**Overall Judgment**: The repository does not appear to contain live committed secrets, but it is not yet announcement-ready because the public trust, logging/privacy posture, licensing, and documentation surfaces are still inconsistent with the code.

## 1. Executive Summary

I do **not** recommend announcing this repository publicly yet.

My current judgment is:

- **Safe enough to make public?** Probably yes, after one more manual check before flipping visibility.
- **Ready for an active public announcement?** No.

The main reason is not an obvious leaked key in the repo. The main reason is that the repository currently makes several public-facing claims that are either incomplete, contradicted by the Windows implementation, or not packaged well enough for first-time public scrutiny.

The highest-risk remaining issues are:

1. **Windows logs user transcription text to disk by default**, which conflicts with the repo's privacy rules and should be converted into a protected debug-only mechanism.
2. **The repo claims MIT licensing in `README.md`, but there is no tracked `LICENSE` file.**
3. **The public docs are inconsistent** enough that early users will hit trust and onboarding friction immediately.
4. **The repo still exposes internal working-doc material** under `.agent/`, but this can be kept public if it is documented intentionally and scrubbed of personal/internal references.

## 2. Scope and Method

This audit covered:

- tracked file inventory
- current git state
- tracked-file and history scans for common secret/key patterns
- review of `README.md`, `.gitignore`, `.env.example`, platform docs, and key code paths
- spot checks of Windows and macOS secret handling and privacy behavior
- attempted Windows test execution

What I checked specifically:

- `git ls-files` inventory of tracked content
- `.env` tracking/ignore behavior
- heuristic scans for real key patterns such as `sk-...`, GitHub PATs, AWS-style keys, and private-key headers
- git history scans for those same patterns
- Windows key-storage code paths
- Windows transcript/log retention code paths
- public-facing repository hygiene items such as license/community readiness

## 3. Secret and Sensitive Data Audit

### 3.1 Result: No live committed secrets were found

I did **not** find evidence of live committed credentials in tracked files or reachable git history using heuristic scans for:

- OpenAI-style keys
- GitHub personal access tokens
- AWS access keys
- private key headers such as `BEGIN PRIVATE KEY`

I also confirmed:

- `.env` is ignored by `.gitignore` at `.gitignore:43`
- `.env` is not tracked (`git ls-files .env` returned nothing)
- `git check-ignore -v .env` resolves to `.gitignore:43`
- `.env.example` is a template with an empty `OPENAI_API_KEY` field at `.env.example:22`

### 3.2 Important caveat

This is still a **heuristic audit**, not a guarantee. It significantly lowers the chance of an accidental secret leak, but it is not a substitute for GitHub secret scanning after publication.

### 3.3 Sensitive but non-secret material is still present

While I did not find live keys, I **did** find public-facing material that should be scrubbed before an announcement:

- ~~`.agent/01_designs/06_mac_silence_while_talking.md:6` contains a hardcoded personal file URI~~ (Fixed)
- ~~`.agent/00_gol/00_codex.md:21` and `.agent/00_gol/00_codex.md:84` reference the owner by name ("Sina")~~ (Fixed: Replaced with Sina/User)
- `.agent` docs reference other internal or adjacent project/tool names such as `MarsinHome`, `MarsinLED`, and `ZeroG`

None of that is a credential leak, but it does make the repo look like an internal working directory that was exposed before cleanup.

## 4. Remaining Blocking Findings

### 4.1 Windows logs transcribed text to disk by default

This directly conflicts with the repository's own privacy rules.

The privacy rules say:

- `.agent/00_gol/01_privacy.md:16-18` says transcribed text should not be logged by default and release builds must not log user-transcribed text

The Windows app currently logs actual user text:

- `windows/MarsinDictation.Core/Transcription/OpenAITranscriptionClient.cs:96` logs `Transcription result: "{Text}"`
- `windows/MarsinDictation.App/App.xaml.cs:273-275` logs `📝 Transcription: "{Text}"`
- `windows/MarsinDictation.App/App.xaml.cs:350` logs recovery text
- `windows/MarsinDictation.App/App.xaml.cs:52-62` configures a file logger writing to `%LOCALAPPDATA%\MarsinDictation\logs\app.log`

This is not a GitHub leak, but it is a **privacy posture mismatch** that will matter immediately in a public announcement.

Recommended fix:

- Default behavior in all builds: **never log transcript text**
- Keep non-sensitive operational logs only:
  - provider
  - model
  - byte counts
  - latency
  - success/failure
- If you want transcript-body logging for development, gate it behind **both**:
  - a compile-time debug guard such as `#if DEBUG`
  - a second explicit runtime opt-in such as `MARSIN_ENABLE_SENSITIVE_LOGS=1`
- Keep that runtime flag undocumented for normal users or place it behind a developer-only setting
- Ensure release builds cannot enable sensitive transcript logging accidentally

Best practical pattern:

1. `#if DEBUG` enables the possibility of sensitive logging code existing
2. a runtime flag decides whether it is actually active for that debug session
3. release builds compile the sensitive logging branch out entirely

### 4.2 Licensing is incomplete

The repo says:

- `README.md:108-110` -> `License` / `MIT`

But there is **no tracked `LICENSE` file** in the repository.

That is a public-release blocker. If you announce an open-source repo without an actual license file, people do not have clear permission to use, modify, or redistribute it, regardless of what the README says.

Best license choice for this repo:

- **Recommended default: MIT**

Why MIT is the best fit here:

- it matches the current `README.md`
- it is short, familiar, and low-friction
- it is well-suited for a small developer-facing desktop utility where broad adoption matters more than restrictive reciprocity

When to prefer Apache-2.0 instead:

- if you specifically want an explicit patent grant and the extra terms that come with it

Practical recommendation:

- If your goal is the simplest permissive public release, add **MIT**
- If you care strongly about explicit patent language, choose **Apache-2.0**
- Do not leave the repo in its current state where `README.md` says MIT but no `LICENSE` exists

### 4.3 Public documentation is inconsistent enough to hurt launch trust

I found multiple examples:

- `README.md:13` tells users to run `python3 devtool/deploy.py macos --install`
  - the actual tool exposes `mac`, not `macos` (`devtool/deploy.py:8-13`, `devtool/deploy.py:864`)
- `devtool/README.md:21` still says the macOS command is a stub
  - but `devtool/deploy.py:664` clearly implements `deploy_mac(args)`
- `mac/README.md:100` says the default provider is `localai`
  - but `mac/Core/SettingsManager.swift:57` sets the default provider to `embedded`
- `README.md:56` says the default embedded model is `ggml-large-v3-turbo-q5_0.bin`
  - but `.env.example:15` says `ggml-base.en.bin`
  - and `mac/Core/SettingsManager.swift:62` also defaults to `ggml-base.en.bin`

These are exactly the kinds of inconsistencies that generate low-confidence announcement replies like "the README doesn't match the code."

Suggested doc fixes:

- change the root README mac command from `macos` to `mac`
- make `README.md`, `devtool/README.md`, and `mac/README.md` agree on whether `devtool/deploy.py mac` is implemented and supported
- align the default provider across docs and code
- align the default embedded model across docs, `.env.example`, and code
- clarify transcript retention and local-history behavior in plain language
- keep privacy claims narrow and exact:
  - no telemetry
  - no retained audio after transcription
  - local transcript history if enabled
  - secure key storage only where actually implemented

### 4.4 The `.agent` surface should be intentional, not accidental

The `.agent` directory does **not** need to be removed. It can stay public if it is presented intentionally as part of the development workflow.

Right now the problem is not that `.agent` exists. The problem is that it reads like internal process material that was exposed without framing.

The public README explicitly tells contributors to start inside `.agent/`:

- `README.md:92-106`

That directory contains:

- agent operating rules
- project plans
- working reports
- stale or overconfident audit claims

Example:

- `.agent/03_reports/202603/20260316_gap_analysis_mac_v0_report.md:202` already recommends adding a `LICENSE` file before public release
- but that recommendation still has not been completed

Recommended fix:

- add `.agent/README.md` explaining that `.agent/` contains design notes, project plans, implementation reports, and agent-oriented development workflow material
- remove personal file URIs such as the hardcoded `/Users/...` link
- scrub owner-specific/internal references where they add no public value
- keep `.agent` linked from the top-level README only as a secondary developer/documentation area, not the primary first-run onboarding path

## 5. Non-Blocking but Important Issues

### 5.1 Transcript retention is only partially disclosed

The repo does not retain audio after transcription, which is good.

However, on Windows it **does** retain transcribed text locally:

- `windows/MarsinDictation.Core/History/TranscriptStore.cs:7-8` stores transcript JSONL shards under `%LOCALAPPDATA%\MarsinDictation\transcripts`
- `windows/MarsinDictation.App/App.xaml.cs:382-410` includes transcript history and log files in "Clean User Data"

That is not inherently bad. In fact, it is consistent with the internal privacy rules. But the top-level privacy message in `README.md:90` is too compressed relative to the actual behavior and would benefit from clearer wording before public launch.

### 5.2 Community-health files are thin

Based on GitHub's public repository community profile guidance, the repo would benefit from:

- `LICENSE`
- `SECURITY.md`
- `CONTRIBUTING.md`
- optionally `CODE_OF_CONDUCT.md`

Right now the repo has a README, but not the rest of the expected public-project surface.

### 5.3 Fresh test validation could not be completed in this audit

I attempted to run:

```powershell
dotnet test windows\MarsinDictation.sln -c Release --no-restore
```

The run failed in this environment because access to `%LOCALAPPDATA%\Microsoft SDKs` was denied under the current sandbox, and the elevated rerun was not approved.

That means I cannot honestly claim a fresh end-to-end Windows validation result from this audit.

This is not proof the tests fail on the machine normally. It is a validation gap in the audit.

## 6. Public Visibility vs Public Announcement

This repo is closer to:

- **safe to publish quietly**, after a final scrub

than it is to:

- **ready to be actively promoted**

That distinction matters.

### My recommendation

- **Public GitHub visibility**: reasonable after a final scrub and one more manual pass
- **Public announcement**: hold until the blocking issues above are fixed

If you announce now, the likely criticism will not be "you leaked a secret." It will be:

- your README is inconsistent
- your Windows logging/privacy story is overstated
- your license is incomplete
- your repo still contains internal process material

## 7. Best Way to Announce It

### 7.1 Best first announcement channel

My recommendation is:

1. **GitHub release**
2. **Show HN**
3. Short follow-up posts on X / LinkedIn / relevant Reddit communities

### 7.2 Why this is the best fit

This is an inference from the current repo shape and audience fit:

- the project is code-forward and developer-legible
- the strongest differentiators are technical:
  - native desktop
  - embedded Whisper
  - offline/privacy angle
  - Windows + macOS support
- the repo is not yet polished enough for a marketing-first launch page

Because of that, **Show HN is a better first announcement than Product Hunt** right now.

If you go to Product Hunt first, people will evaluate packaging, onboarding polish, install clarity, and marketing surface area more aggressively than the repo currently supports.

### 7.3 Recommended announcement sequence

1. Fix the blockers in this report
2. Push the cleaned repo
3. Let GitHub secret scanning inspect the public repo
4. Publish a tagged GitHub release with:
   - screenshots
   - a short GIF/video
   - install instructions
   - known limitations
5. Post a `Show HN` submission focused on the technical hook
6. Cross-post a short demo thread elsewhere after the GitHub release and HN post are live

### 7.4 Suggested positioning

Lead with what is concrete and defendable:

- native offline dictation for Windows and macOS
- embedded Whisper support
- system-wide hotkey workflow
- no telemetry

Avoid leading with claims that are not yet fully true across platforms, especially:

- broad privacy claims that ignore transcript/log retention details
- "private by default" wording if transcript text can still be logged in normal Windows runs

### 7.5 Suggested headline direction

Examples:

- `Show HN: MarsinDictation — offline desktop dictation with embedded Whisper for Windows and macOS`
- `Show HN: MarsinDictation — native system-wide dictation with local Whisper, no server required`

## 8. External Guidance Worth Using Before Publication

These are the most relevant references for the next step:

- GitHub community profile guidance:
  - https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories?apiVersion=2022-11-28
- GitHub secret scanning alerts:
  - https://docs.github.com/en/code-security/secret-scanning/managing-alerts-from-secret-scanning/about-alerts
- GitHub push protection:
  - https://docs.github.com/en/code-security/concepts/secret-security/about-push-protection
- Hacker News guidelines:
  - https://news.ycombinator.com/newsguidelines.html

Useful current takeaways from those sources:

- GitHub's public-repo community profile expects files such as `README`, `LICENSE`, `CONTRIBUTING`, `CODE_OF_CONDUCT`, and `SECURITY`
- Secret scanning alerts run automatically on public repositories
- Push protection for users on GitHub.com is enabled by default when pushing to public repositories

## 9. Final Recommendation

### Decision

**Do not announce yet.**

### Why

The repo appears **unlikely to leak an active committed secret** based on the current scans.

But it is still **too inconsistent and too internally exposed** to make a strong first public impression. The Windows logging/privacy behavior and the public documentation do not yet match the intended public positioning closely enough for a launch.

### What would change my recommendation to "announce now"

At minimum:

1. add a real `LICENSE` file
2. stop logging transcribed text in Windows normal/release paths and move any sensitive logging behind a protected debug-only flag
3. fix the broken/inconsistent docs
4. add `.agent/README.md` and scrub personal/internal references from `.agent`
5. complete one clean validation pass and capture the result

Once those are done, this becomes a credible candidate for a technical public launch, with `Show HN` as the strongest first announcement channel.

## 10. Agent TODOs

Use this as the execution checklist for the cleanup pass before making the repo public and before announcing it.

- [x] Add a root `LICENSE` file
- [x] Use **MIT** unless you intentionally want **Apache-2.0** for the explicit patent grant
- [x] Make `README.md` and the actual `LICENSE` file agree exactly
- [x] Remove transcript-body logging from normal Windows execution paths
- [x] Keep only non-sensitive operational logging in normal Windows logs
- [x] Add a protected sensitive-logging path for development only:
  - `#if DEBUG`
  - plus runtime opt-in such as `MARSIN_ENABLE_SENSITIVE_LOGS=1`
- [x] Ensure release builds cannot emit transcript text to logs even if a runtime flag is present
- [x] Review Windows recovery-path logging and remove transcript text there too
- [x] Fix the root README mac command from `macos` to `mac`
- [x] Make `README.md`, `devtool/README.md`, and `mac/README.md` consistent about macOS build/install support
- [x] Align the documented default provider with the actual code default
- [x] Align the documented default embedded model with the actual code default
- [x] Tighten privacy wording in `README.md` so it accurately describes:
  - no telemetry
  - no retained audio after transcription
  - local transcript history behavior
  - sensitive logging disabled by default
- [x] Add `.agent/README.md` explaining what `.agent/` is and why it is kept in the public repo
- [x] Remove the hardcoded personal `/Users/...` file URI from `.agent/01_designs/06_mac_silence_while_talking.md`
- [x] Replace owner-specific/internal references in `.agent` where they are not useful to public contributors
- [x] ~~Reconsider whether the root README should send first-time contributors into `.agent/` immediately~~ (Vetoed: User prefers advanced docs clearly bounded inside the root README).
- [ ] Run one clean validation pass after the cleanup and record the result in a new report
- [ ] After the cleanup, make the repo public quietly first and let GitHub secret scanning inspect it before doing any active announcement
