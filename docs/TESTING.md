# ZackOS Testing Strategy

Constraint: development happens without access to the target machine. Anything that can be proven off-machine is tested automatically; anything that can't is verified by a documented manual run on the ThinkPad, with results reported back.

## Running the tests now

```
bash tests/run.sh
```

This runs: the generated-files sync check, the package manifest check, 21 Python unit tests, the shell tests (log, detect, preflight, backup, pkg, repo, priv, modules, module content, CLI) and shellcheck if installed. Everything runs in temporary directories with a fake root, so it never touches your real `$HOME` or system. It needs only `bash`, `python3` (3.11+) and standard coreutils. `shellcheck` is optional.

In Phase 2 these ran in a generic Linux sandbox (not Fedora, not the ThinkPad) and passed. They have **not** been run on your machine yet; please run them and report the output.

## Phase 3 status (actual results)

Local run in the development sandbox (generic Linux, not Fedora, not the ThinkPad), last run: `ALL CHECKS PASSED`.

| Suite | Assertions |
|---|---|
| backup | 33 |
| cli (bin/zackos end to end, fake dnf5/rpm/sudo/lspci) | 60 |
| detect | 38 |
| log | 14 |
| module-content (real kitty/zsh/fastfetch modules, zsh syntax and sourcing, jq JSON check) | 23 |
| modules (engine: conflicts, ownership, idempotency, interrupted install) | 65 |
| pkg | 48 |
| preflight | 13 |
| priv | 27 |
| repo | 45 |
| Python (render-theme) | 21 tests |

Generated files: 8 up to date. Package manifest: valid (10 packages). shellcheck: clean.

**Not yet executed:** the Fedora 44 scenarios in `tests/dnf5/` (workflow `.github/workflows/fedora44.yml`). They test real dnf5 and are the only evidence that counts for repository isolation; fake binaries prove the ZackOS logic, not DNF5 behavior. Until those jobs have run green, isolation is not complete. Scenarios that cannot be proven in a container (PackageKit, which needs systemd/D-Bus, and anything needing the real COPR) are reported as SKIP, never as pass. The CI scripts refuse to run outside a disposable `fedora:44` container.

## Test levels

| Level | What | Where | When |
|---|---|---|---|
| 1. Static | `shellcheck` (in place); `shfmt`, markdown lint (planned); TOML validity is enforced by the generator | CI and local | Every push |
| 2. Config validation | Parse each config with its own tool where one exists (for example `hyprland --verify-config`, `kitty --debug-config`, `zsh -n`, `nvim --headless` load check, JSON/CSS validity for Waybar) | CI container where the tool is installable, otherwise local on the ThinkPad | Every push or per phase |
| 3. Generation | Rendered theme files equal committed files; palette contains all 7 required keys and valid hex | CI | Every push |
| 4. Unit | Bash library functions (log, detect, preflight, backup) using the small harness in `tests/shell/harness.sh` (no framework needed); Python tests with `unittest` | CI and local | Every push |
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
