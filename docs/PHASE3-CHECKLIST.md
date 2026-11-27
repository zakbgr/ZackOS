# Phase 3 Implementation Checklist

Scope approved 2026-11-25. Boxes are ticked only when the item is implemented **and** its tests pass; the evidence is in the pull request or CI run.

Status: items 1-8 are implemented and pass the local suite (`bash tests/run.sh`, see docs/TESTING.md). Item 9 ran on GitHub Actions in `fedora:44` containers (the sandbox cannot pull that image): isolation job 25 pass / 0 fail / 1 skip, real-packages job 19 pass / 0 fail / 0 skip, run https://github.com/zakbgr/ZackOS/actions/runs/45981701855. PackageKit was not testable there, so isolation is **not** claimed complete. The CI runs exposed and fixed three bugs: the `\t` queryformat, `cmp` and `diff` assumed present.

## In scope
- [x] 1. Design docs and ADRs 0005, 0006
- [x] 2. Dry-run default; exit code 5 (locked)
- [x] 3. Package manifest, validator, selection, dnf wrapper
- [x] 4. Isolation generator, audit, closure check, locked enable/disable
- [x] 5. Privileged-step runner with individual confirmation and journal
- [x] 6. Module plan, deploy, rollback (conflicts skipped, never overwritten)
- [x] 7. Kitty, Zsh, Fastfetch modules (no `.zshrc` edits, no login-shell change)
- [x] 8. `bin/zackos`: doctor, plan, status, install, rollback, packages, repo; GPU report
- [x] 9. Fedora 44 CI scenarios written and run (PackageKit skipped, see below)
- [x] 10. Final docs, honest isolation status

## Fedora 44 CI scenarios (isolation is NOT complete until all pass)
- [x] Same package in Fedora and COPR: Fedora wins, with a negative control proving the test detects shadowing
- [x] COPR package requiring another COPR package
- [x] Forbidden installs refused (`*-git`, explicit versions, non-allowlisted names; the `Provides` case is NOT tested)
- [x] Normal `dnf5 upgrade`
- [x] Version conflict and downgrade
- [x] `dnf5 history` list/undo available as advised
- [x] Override section with a colon-containing repo ID is honored
- [ ] PackageKit honors the override: NOT TESTED (needs systemd/D-Bus; on-device check deferred until COPR is approved)
- [x] Kitty, Zsh and Fastfetch configs accepted by the real Fedora 44 packages

## Explicitly NOT done in Phase 3
- COPR enabled, any COPR package installed, override written to `/etc`
- Waybar, Rofi, Hyprland configuration, session registration, GDM changes
- Login shell change, `.zshrc` edits, overwriting any existing config
- Hyprland hyprlang-to-Lua migration; the Hyprland theme fragment is untouched
- Any privileged operation executed by ZackOS on the owner's machine without the owner running it

## Required before Phase 4
- [ ] Complete COPR dependency allowlist presented, every package justified
- [ ] Exact Hyprland version and supported configuration syntax verified
- [ ] Plain and UWSM session files verified for Fedora 44
- [ ] On-device results for the isolation scenarios and PackageKit
- [ ] Owner approval to unlock COPR operations
