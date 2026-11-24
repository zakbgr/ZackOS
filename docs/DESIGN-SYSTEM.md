# ZackOS Design System

Single source of truth: [`design/palette.toml`](../design/palette.toml). Everything visual is derived from it.

## Approved palette

| Key | Hex | Role |
|---|---|---|
| `colors.background` | `#090E12` | Main background |
| `colors.background_alt` | `#111B22` | Panels, inactive tabs |
| `colors.accent` | `#00D9FF` | Primary accent (cyan) |
| `colors.green` | `#00E676` | Secondary accent (Matrix green) |
| `colors.text` | `#D8E5E9` | Main text |
| `colors.muted` | `#81949C` | Secondary text |
| `colors.border` | `#20323B` | Borders |

## Proposed additions (awaiting your approval)

These are not in your brief. I added them because terminals and status bars need them.

- **Status colors:** warning `#FFB300`, error `#FF5252`.
- **16-color terminal palette:** normal and bright variants. Green, cyan and white reuse your palette; red, yellow, blue and magenta are new.
- **Fonts (by name only):** JetBrains Mono, Symbols Nerd Font Mono, size 11.
- **Geometry:** radius 8, border 2, gaps 4/8, bar height 32.
- **Effects:** terminal opacity 0.92, active window 0.97, inactive 0.90, bar 0.92, animation 120/220 ms.

Change any of these in `palette.toml` and regenerate.

## Contrast (WCAG)

Run `python3 scripts/render-theme.py --report`. Current ratios: text on background 15.05, text on background_alt 13.54, muted on background 6.14, muted on background_alt 5.52, accent on background 11.42, green on background 11.61. The generator refuses to render if a rule is violated (text 7:1, others 4.5:1).

## Generated files (committed)

| Generated file | Template | Used by |
|---|---|---|
| `lib/palette.sh` | `palette.sh.tmpl` | Shell library (colored log output) |
| `modules/kitty/files/.config/kitty/zackos-theme.conf` | `kitty.conf.tmpl` | Kitty, via `include zackos-theme.conf` |
| `modules/hypr/files/.config/hypr/zackos-theme.conf` | `hyprland.conf.tmpl` | Hyprland variables, via `source =` |
| `modules/waybar/files/.config/waybar/zackos-theme.css` | `waybar.css.tmpl` | Waybar, via `@import` |
| `modules/rofi/files/.config/rofi/zackos-theme.rasi` | `rofi.rasi.tmpl` | Rofi, via `@import` |
| `modules/nvim/files/.config/nvim/lua/zackos/palette.lua` | `nvim-palette.lua.tmpl` | Neovim, via `require("zackos.palette")` |

The mapping is in `design/targets.toml`. These are fragments only: the main configs that include them arrive in Phases 3 to 6. None of them is installed to your home directory yet.

## Regenerating

```
python3 scripts/render-theme.py            # write files
python3 scripts/render-theme.py --check    # exit 1 if any file is stale
python3 scripts/render-theme.py --report   # contrast ratios
```

Needs Python 3.11 or newer (standard library only). Template syntax: `{{ colors.accent }}`, optionally with a filter: `hex`, `nohash`, `rgb`, `rgbsc`, `hexa:<alpha>`, `css_rgba:<alpha>`, `hypr` or `hypr:<alpha>`. The alpha argument can be a number or a palette key such as `effects.bar_opacity`.

To add a themed file: write a template in `design/templates/` starting with a `@@HEADER@@` line, add a `[[target]]` to `design/targets.toml`, regenerate, commit all of it.

## Assets and licenses

Fonts, icons, wallpapers and other assets are governed by [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). Nothing third-party is bundled yet.

## Caveats

- Hyprland, Waybar and Rofi fragment syntax is written from documentation knowledge and has not been run against Fedora 44 builds. Check on the ThinkPad (see `docs/TESTING.md`).
- Font availability in Fedora 44 repositories is not yet verified.
