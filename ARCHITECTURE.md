# ZackOS Architecture

Status: Phase 1 proposal. Nothing here is implemented yet.

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
│   └── decisions/            # ADRs: one short file per major decision
├── design/
│   └── palette.toml          # single source of truth for colors (Phase 2)
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
├── lib/                      # shared shell library (logging, backup, symlink, checks)
├── bin/
│   └── zackos                # single CLI entry point (Phase 7)
├── scripts/
│   ├── render-theme          # palette → per-app generated configs (Phase 2)
│   └── check-*               # validation scripts used locally and in CI
├── tests/
└── .github/workflows/        # CI (lint, validation)
```

Only the documentation files exist today. Directories appear in the phase that needs them.

## 4. Configuration management

**Modules.** Each component is a self-contained module with a `module.conf` declaring: required packages, files it deploys and where, other modules it depends on, and optional post-install checks. A module never edits another module's files.

**Deployment method: symlinks into the repo, with a manifest.** Files under `modules/<name>/files/` are symlinked to their target path (for example `modules/kitty/files/.config/kitty/kitty.conf` → `~/.config/kitty/kitty.conf`). Reasons: editing the live config edits the repo, so changes are easy to commit, and removal is deleting a link. Trade-off: the repo checkout must stay in place; documented and checked by `zackos doctor`.

**Theming pipeline.** `design/palette.toml` is rendered by `scripts/render-theme` into per-app color fragments (Kitty, Waybar CSS, Rofi rasi, Hyprland variables, Neovim). Generated files are committed so installation needs no build step. CI fails if generated files are out of date.

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

## 7. Session and component roles

| Component | Role | Notes |
|---|---|---|
| Hyprland | Compositor and window management | Needs third-party packaging on Fedora 44 |
| Waybar | Status bar | Styled from palette |
| Rofi | Launcher | Wayland support must be verified on F44 |
| Kitty | Terminal | |
| Zsh | Shell | Prompt and plugins kept minimal, no framework unless justified by ADR |
| Dolphin | File manager | Pulls in KDE dependencies on a GNOME install; evaluate vs. alternatives |
| Neovim | Terminal editor | Minimal config first |
| Fastfetch | System info | Themed to palette |

Each is evaluated in its own phase; adding or dropping one requires a short ADR in `docs/decisions/`.

## 8. Logging and error handling

A shared `lib/log.sh` provides `log_info`, `log_warn`, `log_error`, `log_step`. Output goes to the terminal (colored via palette) and to a log file. Exit codes are consistent: `0` success, `1` generic failure, `2` preflight failed, `3` user declined, `4` backup failed (nothing was changed).

## 9. Testing, compatibility

See [docs/TESTING.md](docs/TESTING.md) and [docs/FEDORA-COMPATIBILITY.md](docs/FEDORA-COMPATIBILITY.md).

## 10. Open decisions (need your input before Phase 2)

1. Which Fedora 44 edition is installed: Workstation (GNOME) or KDE Plasma? This affects Dolphin dependencies and the login session setup.
2. Which Hyprland source to trust: a COPR, or building from source.
3. License choice.
4. Whether generated theme files are committed (proposed) or built at install time.
