# ADR 0002: License is GPL-3.0-or-later

- Status: accepted by the project owner on 2026-11-24

## Decision

All ZackOS-authored code, scripts, configuration and documentation are licensed under GPL-3.0-or-later. The unmodified GPL v3 text is in `LICENSE`. Files carry the header `SPDX-License-Identifier: GPL-3.0-or-later`; generated files include it automatically.

## Third-party material

Fonts, icons, cursors, wallpapers and other assets keep their own licenses. The rules and the register are in `THIRD_PARTY_NOTICES.md`. Assets are not committed until they have an entry there, and fonts are referenced by name and installed from Fedora packages rather than bundled.

## Consequences

Derived works must stay GPL-compatible. Configuration snippets copied from other projects must have a compatible license, which must be recorded when they are copied.
