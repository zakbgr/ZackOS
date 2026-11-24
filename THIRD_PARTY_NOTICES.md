# Third-Party Notices and Asset Licenses

ZackOS's own code, scripts, configuration and documentation are licensed under **GPL-3.0-or-later** (see [LICENSE](LICENSE)).

That license does **not** automatically cover third-party material. Fonts, icons, cursor themes, wallpapers, sounds and any other asset keep their own license, and must be recorded here **before** they are added to the repository or referenced by an installer.

## Policy

1. Every asset needs a row in the table below: name, author, source URL, license (SPDX identifier), and where it is used.
2. Only assets whose license permits redistribution in a GPL-3.0-or-later project may be committed. Prefer SIL OFL-1.1, CC0-1.0, CC-BY-4.0, MIT, Apache-2.0, GPL-compatible licenses.
3. Assets under non-commercial, no-derivatives, or unclear licenses are not committed. If wanted, the installer may download them from the original source with the user's explicit approval, and the license is shown first.
4. Third-party files keep their original license headers and files. They live under `assets/<name>/` with their license text beside them.
5. Fonts are preferably installed from Fedora's own packages instead of being bundled.
6. Wallpapers and images created for ZackOS are licensed CC-BY-SA-4.0 unless a row says otherwise.

## Assets

| Asset | Author | Source | License (SPDX) | Used in | Bundled? |
|---|---|---|---|---|---|
| *(none yet)* | | | | | |

## Fonts referenced but not bundled

These are named in `design/palette.toml`. They are installed by the user's package manager, not shipped here. Availability in Fedora 44 repositories is still to be verified.

| Font | License | Notes |
|---|---|---|
| JetBrains Mono | OFL-1.1 | Default monospace font |
| Symbols Nerd Font Mono | OFL-1.1 / MIT (check the exact release) | Icon glyphs for Waybar and terminal |

## Software ZackOS configures but does not distribute

Hyprland, Waybar, Rofi, Kitty, Zsh, Neovim, Fastfetch, Dolphin and others are separate programs with their own licenses. ZackOS ships only configuration files for them.
