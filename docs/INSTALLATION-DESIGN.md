# Installation and Rollback Design (Fedora 44)

Status: Phase 3 design. Implemented parts are marked; Hyprland, Waybar, Rofi and session registration are **out of scope** for Phase 3.

## 1. Principles

- **Dry-run is the default.** Nothing changes unless `--apply` is passed.
- **Detect before changing.** Every command first classifies packages and config targets and prints a plan.
- **User-level by default.** Privileged operations are a short fixed list, each confirmed individually.
- **Never overwrite.** Existing configs are skipped, reported, and left alone. There is no replace option in Phase 3.
- **GNOME stays.** ZackOS never touches GNOME, GDM configuration, the default session, or the login shell.
- **Fedora 44, x86_64 only.**

## 2. Commands (`bin/zackos`)

| Command | Changes the system? | Notes |
|---|---|---|
| `doctor` | No | Environment, GPU report, package states, config conflicts, repository audit |
| `plan [module...]` | No | What `install` would do |
| `status` | No | Installed modules, link health |
| `install <module...> [--apply]` | User files only | Symlinks into `$HOME`, with backup session |
| `rollback [session] [--apply]` | User files only | Restores a backup session; nothing is deleted |
| `packages [plan|install] [--group G] [--apply]` | `install --apply` runs `sudo dnf5 install` after confirmation | Fedora, approved, selected groups only |
| `repo show-override` / `repo audit` | No | Prints the generated override; audits installed packages |
| `repo enable` / `repo disable` | **Locked** | Prints the command plan; refuses to execute (exit 5) |

## 3. Package installation flow

1. Preflight: not root, Fedora 44, x86_64, `dnf5` and `rpm` present.
2. Select packages from the manifest (default group `core-terminal`).
3. Classify each: not installed, from Fedora, from a COPR, unknown source.
4. Print the plan. Stop here in dry-run.
5. With `--apply`: show the exact `sudo dnf5 install ...` command and its undo advice; require the answer `yes` typed for this step; run it; append to the journal.

A package already installed from a COPR that the manifest says must come from Fedora is reported as a conflict and the step refuses to proceed.

## 4. Module deployment flow

A module is `modules/<name>/module.conf` plus `modules/<name>/files/<path relative to $HOME>`.

For every file the target is classified:

| State | Meaning | Action |
|---|---|---|
| `absent` | Nothing at the target | Create a symlink to the repository file |
| `ours` | Already a symlink to that file | Nothing |
| `identical` | Regular file with identical content | Skip, report |
| `conflict` | Different file, other symlink, directory in the way, or a symlinked parent | Skip, report, leave untouched |

On `install --apply`: one backup session is started, each target is recorded in it (including "absent", so rollback can undo), parent directories are created, links are made, and `installed.tsv` is appended.

**Rollback:** `backup_restore` verifies checksums first, then moves whatever is at each recorded path into the new session's `displaced/` folder and restores the original. Nothing is deleted. Parent directories created during install are left in place (they are empty and harmless).

## 5. Privileged operations

Defined in `lib/priv.sh` (ADR 0006): each step shows the command and its undo, requires an exact `yes` typed for that step (no global yes flag), runs through `sudo`, and is appended to `~/.local/state/zackos/priv-journal.tsv`. Dry-run prints the same information and runs nothing.

## 6. Out of scope for Phase 3 (designed, not executed)

- Enabling the `lionheartp/Hyprland` COPR and writing the isolation override to `/etc`.
- Installing Hyprland, UWSM or any COPR package.
- Registering sessions in GDM, or any display-manager change.

Before Phase 5 these require: the verified allowlist (PACKAGE-POLICY section 4), the verified Hyprland version and its configuration syntax, verified session files for plain and UWSM sessions, and the owner's approval.

## 7. Intel UHD 620 (ThinkPad T480s)

The hardware is taken as stated by the owner and is not assumed beyond that. `doctor` reports the GPU it detects (from `lspci` or `/sys/class/drm`) and whether TLP is present. Documented upstream guidance used later: disabling blur and similar effects reduces power use, and with TLP a higher `INTEL_GPU_MIN_FREQ_ON_AC/BAT` reduces stutter on Intel iGPUs. Defaults for blur and animation are decided from on-device results in Phase 5.

## 8. Portals and sessions (later phases)

The Hyprland session will need `xdg-desktop-portal-hyprland` and a file-chooser portal, per-desktop portal selection (`portals.conf`, to be checked against the Fedora 44 man page), and session environment import. Reports exist of portal startup problems on Fedora 44 that were fixed by launching through UWSM, so both plain and UWSM sessions are investigated, and either is provided only if its packages and session files are verified for Fedora 44.
