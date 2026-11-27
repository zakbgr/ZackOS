# Fedora 44 Compatibility Notes

Compiled in Phase 1 from public sources (Fedora release notes, COPR pages, community reports), **not from your machine**. Items marked **VERIFY** must be confirmed on the ThinkPad with `dnf info <pkg>` or by `zackos doctor` once it exists.

## `lionheartp/Hyprland` COPR (checked 2026-11-24 via the public COPR API)

Result: **supports Fedora 44 x86_64 and is actively maintained.** The project lists a `fedora-44-x86_64` chroot. Recent builds, including stable `hyprland` 0.57.2, `hyprutils`, `aquamarine`, `hyprlock`, `hypridle` and `xdg-desktop-portal-hyprland`, succeeded for it, and builds were landing on the day of the check. Full evidence, risks and conditions: [ADR 0001](decisions/0001-hyprland-source.md).

Still unverified: that upstream's own Fedora guidance names this COPR (the wiki could not be fetched here), and everything on your machine. Read-only checks you can run on the ThinkPad (they do not enable anything):

```
# 1. The COPR still lists a Fedora 44 x86_64 chroot
curl -s 'https://copr.fedorainfracloud.org/api_3/project?ownername=lionheartp&projectname=Hyprland' | grep -o 'fedora-44-x86_64' | head -1

# 2. Latest successful builds and their dates
curl -s 'https://copr.fedorainfracloud.org/api_3/build/list?ownername=lionheartp&projectname=Hyprland&status=succeeded&limit=5&order_type=DESC'

# 3. Your Fedora release and architecture
cat /etc/fedora-release; uname -m

# 4. Which of the planned packages Fedora already offers officially
dnf info kitty zsh neovim fastfetch waybar rofi dolphin 2>&1 | grep -E '^(Name|Version|Repository)|No match'
```

Please paste the output back.

## Confirmed from public sources

1. **Hyprland is not in Fedora's official repositories for F43/F44.** It was available in F42 and then orphaned; on F44 it comes from a COPR or a source build. Several third-party COPRs exist (for example `ashbuk/Hyprland-Fedora`, `lionheartp/Hyprland`).
2. **The long-standing `solopasha/hyprland` COPR appears abandoned** and does not list Fedora 44 builds. Do not depend on it.
3. **COPR packages are unofficial**: no Fedora review, maintainers can disappear, and library version mismatches between COPRs can break `dnf upgrade`. Mixing packages from two Hyprland COPRs is a known source of dependency conflicts.
4. **Hyprland 0.55 introduced a Lua-based config layer that needs Lua 5.5**, while Fedora ships Lua 5.4. COPR builds work around this by vendoring libraries. Config syntax may change between Hyprland releases, so ZackOS must pin a tested version.
5. **`xdg-desktop-portal-hyprland` has reported startup problems on Fedora 44** shortly after release, attributed to a portal autostart issue. Screen sharing and file dialogs depend on this. Workarounds were discussed (`dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP` on session start). **VERIFY** current status before Phase 4.
6. **Fedora 44 is Wayland-first**: GNOME 50 ships without an X.Org session in GDM, and KDE Plasma 6.6 is Wayland. This suits Hyprland but means any X11-only tool needs XWayland.
7. **Fedora 44 KDE edition replaced SDDM with Plasma Login Manager.** How a third-party Wayland session is listed there needs checking if you use the KDE edition.
8. **PackageKit moved to libdnf5**, and `dnf` is DNF5. Scripts must use DNF5 syntax and not rely on old `dnf` plugin behavior. **VERIFY** exact `copr` plugin commands on your system.

## Unverified, must check on the ThinkPad

| Item | Why it matters |
|---|---|
| `kitty`, `zsh`, `neovim`, `fastfetch`, `waybar`, `dolphin` in official F44 repos | Expected but not confirmed here |
| Rofi Wayland support | Historically a separate `rofi-wayland` fork; confirm what the F44 `rofi` package supports |
| Edition installed (Workstation/GNOME vs KDE) | Not blocking: ZackOS auto-detects (`bash scripts/detect-env`). Dolphin is optional because it pulls in KDE libraries on GNOME |
| Waybar version vs. Hyprland IPC | Workspace modules break with mismatched versions |
| Intel UHD 620 graphics, Mesa version | Blur and animation cost on integrated GPU |
| ThinkPad specifics: TrackPoint, function keys, brightness, `fprintd` fingerprint, `power-profiles-daemon`/TLP | Need explicit keybindings and verification |
| SELinux enforcing | Custom services or scripts under `~/.config` can trigger denials |
| Login method (GDM or Plasma Login Manager) | Session file lives in `/usr/share/wayland-sessions/`, a root-owned location |

## Design consequences

- **Pin Hyprland** to one version from the `lionheartp/Hyprland` COPR (ADR 0001) and record it in `packages/fedora44.txt` once Phase 4 starts.
- **The COPR also carries `kitty` and `waybar-git`.** Restrict it to an allowlist so it cannot shadow Fedora's official packages (the DNF5 `includepkgs` option needs verifying).
- **Never mix** Hyprland ecosystem packages from different COPRs.
- **Install the session file only through the package**, to avoid ZackOS writing to `/usr/share` itself.
- **Keep the default session available** so a broken Hyprland update cannot lock you out.
- **Pre-upgrade check**: `zackos doctor` should warn before a Fedora major upgrade because COPR packages may lag a release.
- **Avoid features that depend on one Hyprland version** unless wrapped in version checks.

## Sources

- Fedora 44 release coverage: Fedora Magazine, Red Hat blog, Linuxiac, It's FOSS
- COPR project pages and READMEs for Hyprland builds on Fedora
- Fedora Discussion threads on Hyprland COPRs and the F44 portal issue

## Verified on Fedora 44 containers (CI, not on the ThinkPad)

- `dnf5 repoquery --installed --queryformat` supports `%{from_repo}` (reports `fedora`, `updates` or the COPR repo ID). `\t` is not expanded: use a real tab. `%{repoid}` reports `@System` for installed packages and is not useful.
- `dnf5 history list` and `dnf5 history undo <id>` work as advised.
- `install --repo <id>` is accepted by dnf5.
- kitty 0.47.1 has no `--debug-config`; configs are checked by loading them with `kitty +runpy` and reading kitty's own "Ignoring ..." warnings.
- Fedora's zsh package ships `/etc/skel/.zshrc` and `.zprofile`; ZackOS never touches them.
- A minimal Fedora install may lack `diffutils` (`cmp`, `diff`); ZackOS does not need them.
- Hyprland packages are not in the Fedora 44 repos used by these containers; nothing about Hyprland itself was tested.
