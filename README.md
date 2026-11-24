# ZackOS — Matrix Edition

> A keyboard-first, Matrix-inspired Linux desktop environment for Fedora, delivered as a reproducible, reversible set of user-level configurations.

**Status: Phase 1 — architecture and planning only.** This repository currently contains documentation. It contains no installers and nothing in it modifies your system. See [ROADMAP.md](ROADMAP.md).

## What is ZackOS?

ZackOS is a personalized desktop layer on top of stock Fedora, not a fork of it. It aims to provide:

- A tiling, keyboard-driven workflow (Hyprland).
- One consistent visual identity across every tool: dark, minimal, cyan primary accent, Matrix-green secondary accent, subtle transparency and animation.
- A safe installation story: every change is explicit, backed up and reversible.

Your existing Fedora install and desktop environment stay untouched; ZackOS is an *additional* session you choose at login.

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

The palette will live in a single source file and be rendered into each application's config (see [ARCHITECTURE.md](ARCHITECTURE.md)).

## Target environment

- Lenovo ThinkPad T480s, x86_64, 16 GB RAM
- Fedora Linux 44

Other Fedora versions and hardware are not goals for now.

## Planned stack (under evaluation)

Hyprland · Waybar · Rofi · Kitty · Zsh · Dolphin · Neovim · Fastfetch

Fedora 44 availability of these is **not assumed**. In particular, Hyprland is not in Fedora's official repositories and needs a third-party COPR or a source build. See [docs/FEDORA-COMPATIBILITY.md](docs/FEDORA-COMPATIBILITY.md).

## Documentation

| Document | Purpose |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Repository layout, configuration management, installation safety, backup and rollback |
| [ROADMAP.md](ROADMAP.md) | The 10 phases and their exit criteria |
| [docs/TESTING.md](docs/TESTING.md) | Testing strategy |
| [docs/FEDORA-COMPATIBILITY.md](docs/FEDORA-COMPATIBILITY.md) | Known Fedora 44 risks and open verification items |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Workflow, commit style, rules for scripts |

## Safety promise

ZackOS will never, without explicit approval: reinstall Fedora, touch partitions, remove your current desktop, overwrite configs without a backup, or change bootloader settings.

## License

Not yet chosen. To be decided before the first release.
