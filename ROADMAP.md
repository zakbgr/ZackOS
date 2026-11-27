# ZackOS Roadmap

Each phase ends with a review. **No phase starts without your approval.** Phases are deliberately small enough to be tested on the ThinkPad before moving on.

| Phase | Name | Status |
|---|---|---|
| 1 | Repository architecture and scaffolding | Approved |
| 2 | Design system and shared configuration | Approved |
| 3 | Package policy, installer foundation, terminal modules | In progress |
| 4 | Terminal experience (Kitty, Zsh prompt, Fastfetch) | In progress |
| 5 | Hyprland and keyboard shortcuts | Not started |
| 6 | Waybar and Rofi | Not started |
| 7 | Application integration and polish | Not started |
| 8 | Install, backup, restore automation | Not started |
| 9 | Testing and documentation | Not started |
| 10 | Reproducible deployment | Not started |
| 11 | Installable ZackOS ISO (exploration) | Not started |

Renumbered on 2026-11-27 at the owner's request: Phase 4 is the terminal experience, and every phase that followed moved down by one. Older commits and decision records that say "Phase 4" for Hyprland mean Phase 5 now.

## Phase 1 — Architecture and scaffolding
**Deliver:** README, ARCHITECTURE, ROADMAP, CONTRIBUTING, testing strategy, compatibility notes.
**Exit:** you approve the structure and the open decisions in ARCHITECTURE.md section 10 are answered.

## Phase 2 — Design system and shared configuration
**Deliver:** `design/palette.toml`, theme render script, typography and spacing decisions (font choice, border radius, opacity values), shared shell library (`lib/`: logging, backup, preflight).
**Done in Phase 2:** palette and generator with validation and contrast checks, six committed generated files, `lib/` (log, detect, preflight, backup), `scripts/detect-env`, tests, CI, ADRs 0001 to 0004, LICENSE and third-party notices.
**Exit:** you review the proposed palette additions; the generator and library tests pass on your machine too (`bash tests/run.sh`). Still no installer touching `$HOME`.

## Phase 3 — Package policy, installer foundation, terminal modules
**Scope (approved 2026-11-25):** package manifest and selection; repository isolation generator and audit; read-only `doctor`, `plan`, `status`; user-level module deployment and rollback; Kitty, Zsh and Fastfetch modules from Fedora packages only; tests and documentation. This absorbs the foundation of the original install phase (now Phase 8).
**Locked:** COPR enable/disable (implemented, not executable), Hyprland, Waybar, Rofi, session registration, the hyprlang-to-Lua migration.
**Checklist:** [docs/PHASE3-CHECKLIST.md](docs/PHASE3-CHECKLIST.md). **Policy:** [docs/PACKAGE-POLICY.md](docs/PACKAGE-POLICY.md).
**Status (2026-11-27):** implemented and green in Fedora 44 CI (isolation 25 pass / 0 fail / 1 skip; real packages 19 pass). Isolation is **not** declared complete: PackageKit, `Provides:` shadowing, the real COPR and on-device checks remain. Merged to `main` through PRs #1, #2 and #3 (the last fixed the DNF5 install confirmation).
**Exit:** all checklist items pass in CI and the owner runs the local checks; isolation is declared complete only after the Fedora 44 scenarios and on-device checks pass.

## Phase 4 — Terminal experience
**Scope (approved 2026-11-27):** a coherent Matrix-inspired terminal: ZackOS identity in Fastfetch (Fedora stays identified as the operating system), a lightweight Zsh prompt with directory, Git status and exit-status feedback, and a refined Kitty theme. All colors come from `design/palette.toml`, which is unchanged (ANSI black stays `#111B22`; see docs/TERMINAL.md).
**Constraints:** Zsh stays opt-in (one `source` line; the login shell is never changed); shell history behavior is not touched; the user's own Kitty and Zsh files are never modified; no package installs; generated files are only ever produced by `scripts/render-theme.py`.
**Docs:** [docs/TERMINAL.md](docs/TERMINAL.md).
**Exit:** local suite and the Fedora 44 terminal checks pass; the owner reviews the pull request.

## Phase 5 — Hyprland configuration and shortcuts
**Deliver:** Hyprland module, keybinding map (documented as a table), monitor, input and ThinkPad specifics (TrackPoint, touchpad, function keys, brightness), idle and lock.
**Prerequisites:** the complete COPR dependency allowlist with justifications; the exact Hyprland version and supported configuration syntax (the hyprlang-to-Lua question is deferred to here); verified plain and UWSM session files; on-device isolation and PackageKit results; owner approval to unlock COPR operations (ADR 0005).
**Exit:** a login into the Hyprland session works and the previous session still works.

## Phase 6 — Waybar and Rofi
**Deliver:** bar modules (workspaces, clock, battery, network, audio), launcher, power menu.
**Exit:** all themed from the palette; keyboard-only navigation verified.

## Phase 7 — Application integration and polish
**Deliver:** Dolphin, Neovim, GTK/Qt theming, cursor and icon theme, wallpaper, notifications, subtle animations tuned for the T480s integrated GPU.
**Exit:** consistent appearance; battery and performance sanity check.

## Phase 8 — Installation, backup, restoration automation
**Deliver:** the `zackos` CLI (`doctor`, `plan`, `install`, `status`, `rollback`, `uninstall`).
**Exit:** full install, rollback and reinstall cycle works with no manual cleanup.

## Phase 9 — Testing and documentation
**Deliver:** CI, container-based tests, user guide, keybinding cheat sheet, troubleshooting guide.

## Phase 10 — Reproducible deployment
**Deliver:** pinned package sources, a documented fresh-Fedora-to-ZackOS procedure, version tags. First release, only on your approval.

## Phase 11 — Installable ISO (exploration)
**Deliver:** a feasibility write-up first: options such as a Kickstart-based spin, or `livemedia-creator`/`kiwi`, legal and licensing considerations, size and maintenance cost. Building an ISO only if the write-up justifies it.

## Principles for changing this roadmap
Phases can be reordered or split. Any change is made in a commit that explains why.
