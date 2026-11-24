# ADR 0004: ZackOS is desktop-independent

- Status: accepted by the project owner on 2026-11-24

## Context

It is not yet known whether the ThinkPad runs Fedora Workstation (GNOME) or the KDE Plasma edition.

## Decision

- ZackOS never requires, replaces or removes GNOME, KDE or any other installed desktop. It only adds a session.
- The desktop environment and display manager are detected automatically (`lib/detect.sh`, `scripts/detect-env`) and every module adapts or skips accordingly.
- Dolphin is an optional module. It is installed only if the user asks. On GNOME it pulls in KDE libraries, which is why it is never a default.
- Nothing in the core install depends on KDE packages.

## Consequences

Display-manager-specific steps (how the Hyprland session appears at login) are checked per detected display manager. Unknown display managers produce a warning with manual instructions, not a guess.
