# ZackOS Architecture

Status: Phase 1 design, updated in Phase 2. Implemented so far: the design system, the generated theme fragments and the shared shell library (`lib/`). Everything else is still planned.

## 1. Goals and non-goals

**Goals:** maintainable, reproducible, safe, consistent look and feel, keyboard-first.

**Non-goals (for now):** supporting other distros or Fedora versions, replacing the user's existing desktop, shipping system-level changes, custom kernels or bootloader work.

## 2. Core principles

1. **User-level first.** Configs live under `~/.config`, `~/.local`. System changes (packages, session file) are limited to a small, listed set, and always shown before they happen.
2. **Additive.** ZackOS adds a session; it does not remove or replace the current desktop.
3. **Explicit.** Every action is printed and logged. A `--dry-run` mode is mandatory for every script.
4. **Reversible.** Anything overwritten is backed up first and can be restored.
5. **Single source of truth.** One palette file and one package manifest drive everything else.
6. **Small dependency surface.** Plain Bash plus tools already on Fedora. No Ansible, Stow or Python required to install.

## 3. Proposed repository structure

```
ZackOS/
├── README.md
├── ARCHITECTURE.md
├── ROADMAP.md
├── CONTRIBUTING.md
├── docs/
│   ├── TESTING.md
│   ├── FEDORA-COMPATIBILITY.md
│   ├── DESIGN-SYSTEM.md
│   └── decisions/            # ADRs: one short file per major decision
├── design/
│   ├── palette.toml          # single source of truth (colors, fonts, geometry, effects)
│   ├── targets.toml          # template -> generated file mapping
│   └── templates/            # one template per themed file type
├── modules/                  # one directory per component
│   ├── kitty/
│   │   ├── module.conf       # metadata: name, packages, targets, deps
│   │   └── files/            # files as they appear under $HOME
│   ├── zsh/
│   ├── fastfetch/
│   ├── hypr/
│   ├── waybar/
│   ├── rofi/
│   ├── nvim/
│   └── dolphin/
├── packages/
│   └── fedora44.txt          # package manifest: name, source (fedora|copr:x), purpose
├── lib/                      # shared shell library
│   ├── log.sh                #   logging, exit codes, dry-run helpers
│   ├── detect.sh             #   read-only desktop / display manager / Fedora detection
│   ├── preflight.sh          #   preflight checks
│   ├── backup.sh             #   backup, verify, restore (never deletes)
│   └── palette.sh            #   GENERATED from palette.toml
├── bin/
│   └── zackos                # single CLI entry point (Phase 7)
├── scripts/
│   ├── render-theme.py       # palette -> generated files (--check, --report)
│   └── detect-env            # read-only environment report
├── tests/                    # python unit tests, shell tests, run.sh
├── LICENSE                   # GPL-3.0-or-later
├── THIRD_PARTY_NOTICES.md    # asset and font licenses
└── .github/workflows/        # CI: runs tests/run.sh
```

`modules/` currently holds only generated theme fragments. Directories for later phases (`packages/`, `bin/`) appear when needed. CI was brought forward from Phase 8 because the generated-files check is part of the design-system guarantee.

## 4. Configuration management

**Modules.** Each component is a self-contained module with a `module.conf` declaring: required packages, files it deploys and where, other modules it depends on, and optional post-install checks. A module never edits another module's files.

**Deployment method: symlinks into the repo, with a manifest.** Files under `modules/<name>/files/` are symlinked to their target path (for example `modules/kitty/files/.config/kitty/kitty.conf` → `~/.config/kitty/kitty.conf`). Reasons: editing the live config edits the repo, so changes are easy to commit, and removal is deleting a link. Trade-off: the repo checkout must stay in place; documented and checked by `zackos doctor`.

**Theming pipeline.** `design/palette.toml` is rendered by `scripts/render-theme.py` into per-app fragments (Kitty, Waybar CSS, Rofi rasi, Hyprland variables, Neovim, and `lib/palette.sh`). Generated files are committed so installation needs no build step, and CI fails if they are stale (ADR 0003). Details: [docs/DESIGN-SYSTEM.md](docs/DESIGN-SYSTEM.md).

**User-local overrides.** Each module supports an untracked `local.*` include (for example `~/.config/kitty/local.conf`) so machine-specific tweaks never conflict with updates.

**Packages.** One manifest, `packages/fedora44.txt`, lists each package and its source (official Fedora repo or a named COPR). Third-party repositories are never enabled silently; the installer prints the exact `dnf` commands and asks first.

## 5. Installation principles

Every install-related script must:

1. Start with preflight checks: Fedora version, architecture, not running as root, required tools present, network if needed. Fail early with a clear message.
2. Support `--dry-run` (default for first run) and `--yes` to skip prompts.
3. Be idempotent: running twice leaves the same state and reports "already done".
4. Print and log each action before doing it.
5. Use `set -euo pipefail` and an `ERR` trap that logs the failing command and points to the log.
6. Back up before overwriting (section 6).
7. Never use `sudo` implicitly. Anything needing root is isolated in a clearly named step that shows the command and asks.
8. Never perform destructive operations: no partitioning, no bootloader changes, no removal of other desktop environments, no `rm -rf` outside ZackOS's own state directory.

Install stages are separate commands, so each can be run and verified on its own:

```
zackos doctor           # read-only: report system state and problems
zackos plan <module>    # show exactly what would change
zackos install <module> # apply, with backup
zackos status           # what is installed, what is linked
zackos rollback         # undo the last (or a chosen) operation
zackos uninstall <module>
```

## 6. Backup and rollback architecture

State lives in `~/.local/state/zackos/`:

```
~/.local/state/zackos/
├── logs/<timestamp>-<command>.log
├── backups/<timestamp>/
│   ├── manifest.tsv          # original path, backup path, type, checksum
│   └── files/...             # preserved originals
└── installed.tsv             # module, version, linked paths, install time
```

**Before every change** to an existing path, the original is moved or copied into a new timestamped backup directory and recorded in `manifest.tsv` with a checksum. A path that does not exist beforehand is recorded as "absent", so rollback knows to remove what we created.

**Rollback** reads a backup manifest and reverses it: remove ZackOS symlinks, restore preserved originals, re-verify checksums. Rollback is itself logged and itself backs up anything it would overwrite.

**Packages** are handled separately: `zackos` records what it installed via `dnf`. Rollback of packages is advisory: it prints the `dnf remove` command and the `dnf history` transaction ID, and does not remove packages on its own.

**Session safety:** your current desktop session stays available at the login screen. If the Hyprland session fails, log out and pick the other session; nothing else is affected.

**Backups are never deleted automatically.** Pruning is an explicit user command.

## 6b. Desktop independence

ZackOS adds a session; it never requires or replaces GNOME, KDE or any other desktop (ADR 0004). `lib/detect.sh` reports the Fedora version, desktop (`XDG_CURRENT_DESKTOP`), session type, display manager (from the `display-manager.service` link) and installed session files. Modules use it to adapt or skip. Unknown display managers produce a warning with manual steps rather than a guess. Modules may be marked optional in `module.conf`; optional modules (Dolphin) are installed only on request.

## 7. Session and component roles

| Component | Role | Notes |
|---|---|---|
| Hyprland | Compositor and window management | From the `lionheartp/Hyprland` COPR, stable package only (ADR 0001) |
| Waybar | Status bar | Styled from palette |
| Rofi | Launcher | Wayland support must be verified on F44 |
| Kitty | Terminal | |
| Zsh | Shell | Prompt and plugins kept minimal, no framework unless justified by ADR |
| Dolphin | File manager | **Optional.** Pulls in KDE libraries on a GNOME install |
| Neovim | Terminal editor | Minimal config first |
| Fastfetch | System info | Themed to palette |

Each is evaluated in its own phase; adding or dropping one requires a short ADR in `docs/decisions/`.

## 8. Logging and error handling

A shared `lib/log.sh` provides `log_info`, `log_warn`, `log_error`, `log_step`. Output goes to the terminal (colored via palette) and to a log file. Exit codes are consistent: `0` success, `1` generic failure, `2` preflight failed, `3` user declined, `4` backup failed (nothing was changed).

## 9. Testing, compatibility

See [docs/TESTING.md](docs/TESTING.md) and [docs/FEDORA-COMPATIBILITY.md](docs/FEDORA-COMPATIBILITY.md).

## 10. Decisions

Resolved on 2026-11-24 (Phase 2 approval):

1. Desktop: stay desktop-independent, auto-detect, Dolphin optional. [ADR 0004](docs/decisions/0004-desktop-independence.md)
2. Hyprland: `lionheartp/Hyprland` COPR, no source build. [ADR 0001](docs/decisions/0001-hyprland-source.md)
3. License: GPL-3.0-or-later. [ADR 0002](docs/decisions/0002-license-gpl-3.0-or-later.md)
4. Generated theme files are committed. [ADR 0003](docs/decisions/0003-committed-generated-theme-files.md)

Open:

- Approve or change the proposed additions in `design/palette.toml` (status colors, 16-color terminal palette, fonts, geometry, effects).
- Which edition (GNOME or KDE) is installed: run `bash scripts/detect-env` and paste the output. Not blocking, since the design is desktop-independent.
