# Git Requirements — MarsinDictation

This document defines the version control rules for MarsinDictation.

---

## Branch Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Stable, releasable code. Every commit on main should build and pass tests. |
| `dev` | Active development. Features and fixes land here first. |
| `feature/<name>` | Short-lived branches for individual features or fixes. Merged into `dev`. |

- `main` is protected. No direct commits — merge from `dev` only when the build is green and acceptance criteria are met.
- Feature branches should be small and focused. Avoid long-lived branches.

---

## Commit Messages

Use conventional commit format:

```
<type>(<scope>): <short description>

<optional body>
```

Types:
- `feat` — new feature
- `fix` — bug fix
- `refactor` — code restructuring with no behavior change
- `docs` — documentation only
- `test` — adding or updating tests
- `chore` — build, tooling, or dependency updates
- `ci` — CI/CD configuration

Scope is the platform or module, e.g. `win`, `mac`, `ios`, `android`, `core`, `deploy`.

Examples:
```
feat(win): add WASAPI audio capture
fix(win): restore clipboard after injection
docs: update Windows v0 design with upload guard
chore(deploy): add Windows build target to deploy.py
```

---

## Versioning

Use **Git tags** for release versioning. This is the simplest approach that works well with CI/CD and is well-proven across projects.

Format: `v<major>.<minor>.<patch>[-<platform>]`

Examples:
- `v0.1.0` — first internal milestone (all platforms share the tag if released together)
- `v0.1.0-win` — Windows-specific release if platforms ship independently
- `v0.2.0` — second milestone

Rules:
- Tags are created only by Sina or at Sina's explicit instruction.
- The agent must **never** create tags, push tags, or publish releases unless explicitly asked.
- Tags should point to commits on `main`.

> [!NOTE]
> Git tags are preferred over alternative versioning mechanisms (changelog files, version.json, etc.) because they are native to Git, show up in `git log`, work with `git describe`, and integrate naturally with CI/CD pipelines. If a more structured release process is needed later (e.g., auto-generated changelogs, GitHub Releases), tags remain the foundation.

---

## Agent Git Rules

- The agent must **not** commit, push, tag, or create releases unless explicitly instructed by Sina.
- The agent may stage changes and describe what would be committed, but must wait for approval.
- The agent should keep the working tree clean — no uncommitted temp files, debug artifacts, or stray changes.
- If the agent discovers uncommitted changes from a previous session, it should mention them rather than silently committing or discarding.

---

## .gitignore

The repository `.gitignore` must cover:
- Build outputs (`bin/`, `obj/`, `.pio/`, `build/`)
- IDE files (`.vs/`, `.vscode/`, `.idea/`, `*.suo`, `*.user`)
- OS files (`.DS_Store`, `Thumbs.db`)
- Package manager outputs (`node_modules/`, `packages/`)
- Secrets and local config (`*.env`, `secrets/`)
- Deployment artifacts and logs (`tmp/`, `logs/`)
- Agent workspace files (`.gemini/`)
