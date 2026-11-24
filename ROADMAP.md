# ZackOS Roadmap

Each phase ends with a review. **No phase starts without your approval.** Phases are deliberately small enough to be tested on the ThinkPad before moving on.

| Phase | Name | Status |
|---|---|---|
| 1 | Repository architecture and scaffolding | In review |
| 2 | Design system and shared configuration | Not started |
| 3 | Terminal: Kitty, Zsh, Fastfetch | Not started |
| 4 | Hyprland and keyboard shortcuts | Not started |
| 5 | Waybar and Rofi | Not started |
| 6 | Application integration and polish | Not started |
| 7 | Install, backup, restore automation | Not started |
| 8 | Testing and documentation | Not started |
| 9 | Reproducible deployment | Not started |
| 10 | Installable ZackOS ISO (exploration) | Not started |

## Phase 1 — Architecture and scaffolding
**Deliver:** README, ARCHITECTURE, ROADMAP, CONTRIBUTING, testing strategy, compatibility notes.
**Exit:** you approve the structure and the open decisions in ARCHITECTURE.md section 10 are answered.

## Phase 2 — Design system and shared configuration
**Deliver:** `design/palette.toml`, theme render script, typography and spacing decisions (font choice, border radius, opacity values), shared shell library (`lib/`: logging, backup, preflight).
**Exit:** render script output is deterministic and validated; library functions have unit tests. Still no installer touching `$HOME`.

## Phase 3 — Terminal customization
**Deliver:** Kitty, Zsh and Fastfetch modules, themed from the palette.
**Safety:** first modules that deploy files, so this phase delivers the minimal `plan` and `install` for these modules with backup, tested in a throwaway `$HOME` before you run it for real.
**Exit:** you run it on the ThinkPad, report results, and rollback is demonstrated to work.

## Phase 4 — Hyprland configuration and shortcuts
**Deliver:** Hyprland module, keybinding map (documented as a table), monitor, input and ThinkPad specifics (TrackPoint, touchpad, function keys, brightness), idle and lock.
**Prerequisite:** decision on Hyprland packaging source.
**Exit:** a login into the Hyprland session works and the previous session still works.

## Phase 5 — Waybar and Rofi
**Deliver:** bar modules (workspaces, clock, battery, network, audio), launcher, power menu.
**Exit:** all themed from the palette; keyboard-only navigation verified.

## Phase 6 — Application integration and polish
**Deliver:** Dolphin, Neovim, GTK/Qt theming, cursor and icon theme, wallpaper, notifications, subtle animations tuned for the T480s integrated GPU.
**Exit:** consistent appearance; battery and performance sanity check.

## Phase 7 — Installation, backup, restoration automation
**Deliver:** the `zackos` CLI (`doctor`, `plan`, `install`, `status`, `rollback`, `uninstall`).
**Exit:** full install, rollback and reinstall cycle works with no manual cleanup.

## Phase 8 — Testing and documentation
**Deliver:** CI, container-based tests, user guide, keybinding cheat sheet, troubleshooting guide.

## Phase 9 — Reproducible deployment
**Deliver:** pinned package sources, a documented fresh-Fedora-to-ZackOS procedure, version tags. First release, only on your approval.

## Phase 10 — Installable ISO (exploration)
**Deliver:** a feasibility write-up first: options such as a Kickstart-based spin, or `livemedia-creator`/`kiwi`, legal and licensing considerations, size and maintenance cost. Building an ISO only if the write-up justifies it.

## Principles for changing this roadmap
Phases can be reordered or split. Any change is made in a commit that explains why.
