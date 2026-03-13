# Codex Rules - MarsinDictation

## Purpose

This file is the compact operating contract for AI coding agents working on MarsinDictation.

MarsinDictation is a small public open-source dictation project. The code and docs should stay clear, maintainable, honest, and ready for public review.

This file defines contribution behavior, not architecture. Architecture and platform details belong in the design docs.

MarsinDictation should be developed with an agent-driven agent-first workflow. The agent should actively look for ways to test and validate changes without human intervention. This means, when the agent is handing off the work back to the human agent, the agent should have already validated the changes and provided proof of validation.

---

## Source Of Truth

Use this order:

1. Sina's direct instructions
2. `00_gol/` rules such as privacy and git requirements
3. Relevant design and project docs
4. Current code
5. Tests

If docs and code disagree, do not guess. Prefer the documented direction when it is clear. Otherwise make the smallest safe change and call out the mismatch.

---

## Core Priorities

Optimize for these in order:

1. Reliability
2. Simplicity
3. Clarity
4. User trust
5. Easy validation

Prefer small, direct, boring solutions over clever or speculative ones.
Prefer implementations that help the agent prove behavior with tests, focused checks, or reproducible validation steps.

---

## Working Rules

- Understand the local context before changing code.
- Solve the requested problem directly.
- Change the minimum required surface area.
- Do not add unrelated refactors or broad cleanup unless asked.
- Preserve existing behavior unless the task intentionally changes it.
- Keep behavior honest. Do not claim support that does not exist.
- Follow platform-native conventions instead of forcing one platform's patterns onto another.
- Keep files, classes, and functions focused.
- Use explicit names. Avoid vague names like `Helper`, `Util`, `Thing`, or `Misc`.
- Avoid hidden side effects.
- Prefer code that is easy to test, debug, and review.
- When choosing between reasonable designs, prefer the one that reduces human verification work.

---

## Validation

- Run relevant builds, tests, or focused checks when practical.
- Add or update tests for meaningful logic changes.
- Never present guessed behavior as completed work.
- Separate clearly what was implemented, tested, manually verified, and still unverified.
- Before handoff, the agent should already have tested and validated the changed code when practical.
- Handoff must include proof such as test results, build results, or other concrete validation evidence. Confidence or guesswork is not enough.

If something is hard to test directly, isolate the boundary and test the logic around it.

---

## Repository Hygiene

- Treat the repository as public.
- Keep code and docs readable, concise, and technically honest.
- Do not leave behind dead scaffolding, misleading comments, random temp files, or machine-specific assumptions.
- Never put secrets in the repo.
- Update nearby docs when behavior changes.
- Do not commit, push, tag, or publish releases unless Sina explicitly asks.

---

## Reference Docs

Read the relevant documents before making changes:

- `00_gol/01_privacy.md` for privacy and security rules
- `00_gol/02_git.md` for git workflow and versioning rules
- `00_gol/03_build_and_deploy.md` for build and deploy workflow
- `01_designs/` for intended architecture and platform behavior
- `02_projects/` for current project scope and task tracking

---

## Final Rule

Keep the project small, sharp, and easy to validate. Build it so both humans and agents can understand it, change it safely, and verify that it still works.
