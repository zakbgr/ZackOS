# Contributing to ZackOS

ZackOS is a personal project run as proper open source. These rules keep it safe and maintainable.

## Workflow

1. Open an issue or a short note describing the change.
2. Branch from `main`: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`.
3. Make small, logical commits.
4. Open a pull request. CI must pass.
5. Never rewrite published history or delete shared branches.

## Commit messages

Conventional style: `type(scope): summary`, imperative mood, 72 characters or fewer.

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`.
Example: `feat(kitty): add themed config module`.

The body explains why, not what.

## Rules for scripts

Every script that can change the system must:

- Use `#!/usr/bin/env bash` and `set -euo pipefail`.
- Pass `shellcheck` and `shfmt` checks.
- Support `--dry-run`, and default to it where practical.
- Be idempotent.
- Log through `lib/log.sh`.
- Back up anything it overwrites through `lib/backup.sh`.
- Avoid `sudo` unless the step is isolated, named and documented.
- Never run destructive commands (partitioning, bootloader changes, recursive deletes outside ZackOS state, removal of other desktops).

## Rules for configuration

- Every source file carries `SPDX-License-Identifier: GPL-3.0-or-later` (generated files get it automatically).
- Never edit a generated file. Change `design/palette.toml` or a template, run `python3 scripts/render-theme.py`, and commit the sources and the regenerated files together. CI fails otherwise.
- Third-party assets need an entry in `THIRD_PARTY_NOTICES.md` before they are committed.
- Colors come from `design/palette.toml`. Do not hard-code hex values in module files.
- Keep modules independent. Declare dependencies in `module.conf`.
- Machine-specific values go in untracked local override files.
- Document every keybinding in the keybinding table.

## Dependencies

Adding a package needs a reason in the pull request and an entry in the package manifest. Prefer packages from Fedora's official repositories. Third-party repositories (COPR, etc.) require an ADR in `docs/decisions/`.

## Testing

Read [docs/TESTING.md](docs/TESTING.md). Run `bash tests/run.sh` before every push. A change is not done until its tests exist and pass.

## Claims about testing

State exactly what you ran and where. "Tested on Fedora 44 ThinkPad T480s" means actual results from that machine. Do not write that something works unless it was run.

## Documentation

Update docs in the same pull request as the change. Major decisions get an ADR (`docs/decisions/NNNN-title.md`: context, decision, consequences).
