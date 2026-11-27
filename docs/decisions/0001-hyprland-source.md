# ADR 0001: Hyprland comes from the `lionheartp/Hyprland` COPR

- Status: accepted by the project owner on 2026-11-24, with the conditions below
- Phase: decision recorded in Phase 2; first use in Phase 5 (no install script exists yet)

## Context

Hyprland is not in Fedora's official repositories for Fedora 43/44. Building Hyprland and its library stack from source was rejected. The owner chose the `lionheartp/Hyprland` COPR.

## Evidence gathered (2026-11-24, from the public COPR API; not from the ThinkPad)

- The project has `fedora-44-x86_64` among its chroots (also 44 aarch64, 45, rawhide).
- Newest builds were succeeded builds dated 2026-11-24. Builds for Fedora 44 x86_64 were present in every recent entry.
- Stable `hyprland` 0.57.2 (built 2026-11-09), `hyprutils` 0.14.4, `aquamarine` 0.16.0, `hyprlock` 0.9.7, `hypridle` 0.1.8 and `xdg-desktop-portal-hyprland` 1.5.0 all have succeeded builds for Fedora 44 x86_64.
- The maintainer answered Fedora 44 build requests in March 2026 and was still replying in a Fedora Discussion thread in July 2026.
- 54 packages are in the project.

## Not verified

- **Upstream installation guidance.** The Hyprland wiki page could not be read from this environment, so it is not confirmed that upstream recommends this COPR. Please read https://wiki.hypr.land/Getting-Started/Installation/ and tell me if it says anything different.
- Anything on the ThinkPad. Commands for you to run are in `docs/FEDORA-COMPATIBILITY.md`.

## Risks accepted

- A single-maintainer COPR is unofficial: no Fedora package review, and it can lag or stop.
- Fedora 44 reports of `xdg-desktop-portal` startup problems with Hyprland remain a known issue (workaround: start via `uwsm`, which the COPR also packages).
- A `hyprutils` 0.13.1-2 regression (slower animations) was reported in July 2026, which shows that updates can regress.

## Decision and conditions

1. Use only the COPR packages ZackOS needs, from the **stable** `hyprland` package. Never the `*-git` packages.
2. Never mix Hyprland-ecosystem packages from another COPR.
3. The COPR also ships `kitty` and `waybar-git`. ZackOS takes `kitty` and `waybar` from Fedora's official repos unless a later ADR says otherwise. The installer will restrict the COPR repo to an explicit package allowlist (DNF5 repo option `includepkgs`, **to be verified**) so it cannot replace official packages.
4. The COPR is enabled only by an explicit, user-approved step in Phase 5; the installer prints the exact commands and asks first.
5. If the F44 chroot or the stable packages disappear, the installer stops and reports. It does not switch to another repository on its own.
6. Pin the tested `hyprland` version in `packages/fedora44.txt` once Phase 5 starts.

> Renumbering note (2026-11-27): "Phase 4" in this record meant the Hyprland phase, which is now Phase 5 (Phase 4 became the terminal experience). See ROADMAP.md.
