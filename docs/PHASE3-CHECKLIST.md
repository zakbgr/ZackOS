# Phase 3 Implementation Checklist

Scope approved 2026-11-25. Boxes are ticked only when the item is implemented **and** its tests pass; the evidence is in the pull request or CI run.

Status: items 1-8 are implemented and pass the local suite (`bash tests/run.sh`, see docs/TESTING.md). Item 9 is written but **has not been executed**: it needs GitHub Actions (`fedora:44` containers), and the development sandbox cannot pull that image. Isolation is therefore **not** claimed complete. Item 10 is open until the CI results are in.

## In scope
- [x] 1. Design docs and ADRs 0005, 0006
- [x] 2. Dry-run default; exit code 5 (locked)
- [x] 3. Package manifest, validator, selection, dnf wrapper
- [x] 4. Isolation generator, audit, closure check, locked enable/disable
- [x] 5. Privileged-step runner with individual confirmation and journal
- [x] 6. Module plan, deploy, rollback (conflicts skipped, never overwritten)
- [x] 7. Kitty, Zsh, Fastfetch modules (no `.zshrc` edits, no login-shell change)
- [x] 8. `bin/zackos`: doctor, plan, status, install, rollback, packages, repo; GPU report
- [ ] 9. Fedora 44 CI scenarios (below)
- [ ] 10. Final docs, honest isolation status

## Fedora 44 CI scenarios (isolation is NOT complete until all pass)
- [ ] Same package in Fedora and COPR: Fedora wins, with a negative control proving the test detects shadowing
- [ ] COPR package requiring another COPR package
- [ ] Forbidden installs refused (`*-git`, a COPR package that `Provides` a protected name)
- [ ] Normal `dnf5 upgrade`
- [ ] Version conflict and downgrade
- [ ] `dnf5 history` list/undo available as advised
- [ ] Override section with a colon-containing repo ID is honored
- [ ] PackageKit honors the override (best effort in CI; on-device procedure documented)
- [ ] Kitty, Zsh and Fastfetch configs accepted by the real Fedora 44 packages

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
