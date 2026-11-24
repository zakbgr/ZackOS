# ZackOS Testing Strategy

Constraint: development happens without access to the target machine. Anything that can be proven off-machine is tested automatically; anything that can't is verified by a documented manual run on the ThinkPad, with results reported back.

## Test levels

| Level | What | Where | When |
|---|---|---|---|
| 1. Static | `shellcheck`, `shfmt`, markdown lint, `taplo`/TOML validity for the palette | CI and local | Every push |
| 2. Config validation | Parse each config with its own tool where one exists (for example `hyprland --verify-config`, `kitty --debug-config`, `zsh -n`, `nvim --headless` load check, JSON/CSS validity for Waybar) | CI container where the tool is installable, otherwise local on the ThinkPad | Every push or per phase |
| 3. Generation | Rendered theme files equal committed files; palette contains all 7 required keys and valid hex | CI | Every push |
| 4. Unit | Bash library functions (backup, symlink, manifest) via `bats` | CI | Every push |
| 5. Integration | Full `plan`/`install`/`rollback` in a **fake `$HOME`** inside a `fedora:44` container | CI | Every push to `main` and PRs |
| 6. Manual on-device | Real login to the session, keybindings, brightness keys, suspend, external monitor | ThinkPad | End of each phase |

## Key test cases for the installer

- Fresh `$HOME`: install creates expected links, nothing else.
- Pre-existing config: backup created, checksum recorded, rollback restores byte-identical files.
- Run install twice: second run reports no changes.
- Interrupted run (kill mid-install): state is consistent and rollback works.
- `--dry-run` changes nothing (verified by hashing the fake `$HOME` before and after).
- Preflight: refuses to run as root, on a wrong Fedora version, or with missing prerequisites.
- Dangling symlink and file-vs-directory conflicts are handled, not clobbered.

## On-device test protocol

For each phase, the repo provides a short checklist. You run it and paste the output (commands, logs from `~/.local/state/zackos/logs/`). Results are recorded in the phase's pull request. Until then the phase is documented as "untested on device".

## Limits to be honest about

- CI containers have no GPU or compositor. Level 6 cannot be automated.
- Hyprland may not be installable in CI if packaged only in COPR; config validation might then be on-device only.
- Visual consistency is judged by screenshots stored under `docs/screenshots/`.

## Definition of done for a change

Static checks pass, relevant automated tests exist and pass, docs updated, on-device checklist run if the change affects the live session.
