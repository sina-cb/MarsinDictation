# Git Requirements — MarsinDictation

This document defines the version control rules for MarsinDictation.

---

## Branch Strategy

All development work happens in feature branches, not on `main`.

| Branch | Purpose |
|--------|---------|
| `main` | Stable, tested, releasable. Every commit builds and passes tests. |
| `dev/<feature_name>` | Active development for a specific feature or platform milestone. |

### Workflow

1. **Create a feature branch** from `main`:
   ```
   git checkout -b dev/win_v0 main
   ```

2. **Commit freely** on the feature branch — small, frequent commits are fine. These are working history.

3. **When the feature is complete and tested**, squash merge into `main`:
   ```
   git checkout main
   git merge --squash dev/win_v0
   git commit -m "feat(win): implement v0 dictation app"
   git push origin main
   ```

4. **Delete the feature branch** after merge:
   ```
   git branch -d dev/win_v0
   git push origin --delete dev/win_v0
   ```

### Why squash merge?

- `main` stays clean — one commit per completed feature, easy to bisect and review.
- Feature branches keep messy WIP history where it belongs — out of `main`.
- Each `main` commit represents a tested, working milestone.

### Parallel work

Multiple agents or contributors can work on separate `dev/` branches simultaneously without conflict:

```
dev/win_v0      ← Agent A: Windows v0 implementation
dev/mac_v0      ← Agent B: macOS v0 implementation
dev/deploy      ← Agent C: deploy.py scaffolding
```

Each branch is independent and merges into `main` when its work is done and validated. If two branches touch the same files, conflicts are resolved at merge time.

### Rules

- `main` is protected. No direct commits — squash merge from `dev/` branches only.
- Feature branches should be focused. One platform milestone or one logical feature per branch.
- Do not let feature branches live longer than necessary. Merge when done, delete after.
- If a feature branch falls behind `main`, rebase or merge `main` into it before merging back.

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
