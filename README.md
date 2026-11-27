# ZackOS — Matrix Edition

> A keyboard-first, Matrix-inspired Linux desktop environment for Fedora, delivered as a reproducible, reversible set of user-level configurations.

**Status: Phase 2 — design system and shared library.** The repository contains documentation, the design system with generated theme fragments, and a tested shell library. It contains no installer, and nothing in it modifies your system. See [ROADMAP.md](ROADMAP.md).

## What is ZackOS?

ZackOS is a personalized desktop layer on top of stock Fedora, not a fork of it. It aims to provide:

- A tiling, keyboard-driven workflow (Hyprland).
- One consistent visual identity across every tool: dark, minimal, cyan primary accent, Matrix-green secondary accent, subtle transparency and animation.
- A safe installation story: every change is explicit, backed up and reversible.

Your existing Fedora install and desktop environment stay untouched; ZackOS is an *additional* session you choose at login. It works the same whether your Fedora uses GNOME or KDE Plasma: the desktop and display manager are detected automatically, and no KDE packages are required.

## Design language

| Role | Hex |
|---|---|
| Background | `#090E12` |
| Secondary background | `#111B22` |
| Primary accent (cyan) | `#00D9FF` |
| Secondary accent (Matrix green) | `#00E676` |
| Main text | `#D8E5E9` |
| Muted text | `#81949C` |
| Borders | `#20323B` |

The palette lives in [design/palette.toml](design/palette.toml) and is rendered into per-application theme files that are committed to the repository, so installing needs no generation step. See [docs/DESIGN-SYSTEM.md](docs/DESIGN-SYSTEM.md).

## Target environment

- Lenovo ThinkPad T480s, x86_64, 16 GB RAM
- Fedora Linux 44

Other Fedora versions and hardware are not goals for now.

## Planned stack (under evaluation)

Hyprland · Waybar · Rofi · Kitty · Zsh · Dolphin · Neovim · Fastfetch

Fedora 44 availability of these is **not assumed**. Hyprland is not in Fedora's official repositories; ZackOS will use the `lionheartp/Hyprland` COPR (see [ADR 0001](docs/decisions/0001-hyprland-source.md)). Dolphin is optional. See [docs/FEDORA-COMPATIBILITY.md](docs/FEDORA-COMPATIBILITY.md).

## Documentation

| Document | Purpose |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Repository layout, configuration management, installation safety, backup and rollback |
| [ROADMAP.md](ROADMAP.md) | The 10 phases and their exit criteria |
| [docs/DESIGN-SYSTEM.md](docs/DESIGN-SYSTEM.md) | Palette, generated files, regeneration |
| [docs/decisions/](docs/decisions/) | Architecture decision records |
| [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | Licenses of fonts, icons, wallpapers and other assets |
| [docs/TESTING.md](docs/TESTING.md) | Testing strategy |
| [docs/FEDORA-COMPATIBILITY.md](docs/FEDORA-COMPATIBILITY.md) | Known Fedora 44 risks and open verification items |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Workflow, commit style, rules for scripts |

## Safety promise

ZackOS will never, without explicit approval: reinstall Fedora, touch partitions, remove your current desktop, overwrite configs without a backup, or change bootloader settings.

## Checking the repository

```
bash tests/run.sh          # theme sync, unit tests, shell tests, shellcheck; touches nothing outside temp dirs
bash scripts/detect-env    # read-only: prints your Fedora, desktop and display manager
```

## License

ZackOS is licensed under **GPL-3.0-or-later** (see [LICENSE](LICENSE)). Third-party fonts, icons, wallpapers and other assets keep their own licenses, listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Phase 3 command line (dry-run by default)

```
bin/zackos doctor                 # read-only report
bin/zackos plan                   # what install would do (kitty, zsh, fastfetch)
bin/zackos install kitty --apply  # link files into $HOME; never overwrites
bin/zackos rollback --apply       # removes only links ZackOS can prove it created
bin/zackos packages plan          # Fedora packages that would be installed
bin/zackos repo show-override     # COPR isolation override preview (written nowhere)
```

COPR enable/disable are locked in this phase. Hyprland packages are candidates and cannot be selected. See docs/INSTALLATION-DESIGN.md and docs/PACKAGE-POLICY.md.
