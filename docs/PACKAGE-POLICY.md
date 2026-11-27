# Package Source and Repository Isolation Policy

Status: Phase 3. Approved by the project owner on 2026-11-25 with the changes recorded in ADR 0005.

## 1. Rules

1. **Fedora repositories are the default source for every package.** The manifest `packages/fedora44.tsv` lists each package with its source.
2. **Protected packages always come from Fedora:** `kitty`, `zsh`, `neovim`, `fastfetch`, `waybar`, `rofi`, `dolphin`. The validator rejects any other source for them.
3. **No `*-git` package, no glob, no comma or whitespace** may appear in a package name or allowlist.
4. **Only packages in the `hyprland-session` group may name a COPR source**, and in Phase 3 they must have status `candidate`. Candidates cannot be selected for installation.
5. **The COPR is never enabled silently, and in Phase 3 not at all.** Enable and disable operations exist in `lib/repo.sh` as command builders, but their execution path is locked (ADR 0005) until the owner approves it.
6. **The allowlist is one safety layer, not the only one.** The layers are listed in section 3.
7. **Dolphin is optional** and is never part of a default group.
8. **ZackOS never removes packages.** Package rollback is advice only (section 5).

## 2. Manifest format

`packages/fedora44.tsv`: tab-separated, `#` comments, six columns.

| Column | Values |
|---|---|
| name | RPM name: `[A-Za-z0-9][A-Za-z0-9._+-]*` |
| source | `fedora` or `copr:<owner>/<project>` |
| group | `core-terminal`, `editor`, `bar-launcher`, `optional-dolphin`, `hyprland-session` |
| optional | `yes` or `no` |
| status | `approved` or `candidate` |
| purpose | free text |

**Selection.** The default selection is the group `core-terminal`. Other groups are added explicitly (`--group`). Only `approved` rows with source `fedora` are selectable in Phase 3. `optional` rows are never selected by default groups.

## 3. Isolation layers

| # | Layer | Status in Phase 3 |
|---|---|---|
| 1 | Manifest validator: protected names are Fedora-only, no `-git`, no globs | Implemented, unit-tested |
| 2 | Generated `includepkgs` override (`/etc/dnf/repos.override.d/50-zackos-...repo`) | Generator implemented; **not written to `/etc`** |
| 3 | Audit: installed packages whose origin is a COPR but are not in the allowlist, or protected packages from a COPR | Implemented with stubs; contract-tested against real DNF5 in CI |
| 4 | Default priority left unchanged | Policy |
| 5 | Locked enable/disable, individual confirmation for every privileged step | Implemented |
| 6 | Dependency-closure check: every COPR-provided dependency of an allowlisted package must itself be allowlisted | Pure function implemented; real closure computed before Phase 4 |

### What DNF5 documentation says (verified)

- `includepkgs` is a list option (names or globs, comma separated) allowed in `[main]` and per repository; DNF5 excludes every package of that repository that does not match.
- Override files in `/etc/dnf/repos.override.d/` modify existing repositories but cannot create them; files are applied alphabetically and the last value wins; repo IDs may use globs.
- `dnf5 copr enable` writes a `.repo` file under `/etc/yum.repos.d/`; `dnf5 copr disable` keeps it with `enabled=0`. The documentation mentions no priority and no package filtering.
- Default `priority` is 99; the lowest value wins even if the package is older.

### Verified on Fedora 44 (real dnf5, GitHub Actions) and what is still open

Run: https://github.com/zakbgr/ZackOS/actions/runs/45981701855 (commit af5248a): **25 pass, 0 fail, 1 skip**. The repositories in this test are local `file://` simulations of Fedora and of `copr:copr.fedorainfracloud.org:lionheartp:Hyprland` built from dummy RPMs; the override tested is the one `bin/zackos repo show-override` generates from the real manifest. The real COPR was never contacted.

| Scenario | Result |
|---|---|
| Negative control: without the override the COPR's `kitty 99.0` wins | confirmed (so the tests can detect a leak) |
| dnf5 loads the override; COPR then exposes exactly `hyprland`, `uwsm`, `xdg-desktop-portal-hyprland` | pass |
| Same package in Fedora and COPR (`kitty`, `zsh`): Fedora wins | pass |
| `from_repo` reports the repo ID (`fedora`, the COPR ID) | pass, after a fix: dnf5 does not expand `\t` in `--queryformat` |
| Allowlisted COPR package pulls its allowlisted COPR dependency; non-COPR dependency comes from Fedora | pass |
| Forbidden installs refused: `kitty-99.0`, `*-git`, non-allowlisted names, `install --repo <copr> kitty` | pass |
| COPR package whose COPR dependency is not allowlisted: dnf5 refuses, closure check reports the gap | pass |
| `dnf5 upgrade`: Fedora `kitty` stays on Fedora; allowlisted `hyprland` upgrades from the COPR | pass |
| Downgrade of a Fedora package stays in Fedora | pass |
| Version skew: if Fedora later ships a package that is also allowlisted from the COPR, the **higher version wins** and the origin becomes Fedora. This is expected and accepted; the audit does not flag it | observed |
| `dnf5 history list` / `dnf5 history undo <id>` removes exactly that transaction | pass |
| Override written before the repository exists; colon-containing repo ID | pass |
| Disabling the repo keeps the override and breaks nothing | pass |
| **PackageKit honoring the override** | **NOT TESTED** (no systemd/D-Bus in a container; reported as skip) |
| A COPR package that `Provides:` a protected name | **NOT TESTED** |
| Installing a local `.rpm` file or `--from-repo`-style explicit bypasses | not preventable by repository configuration; out of scope |
| The real COPR (real metadata, real dependency closure) | **NOT TESTED**; needs the owner's approval to enable it |

**Conclusion: repository isolation is NOT declared complete.** The DNF5 layer behaves as designed in every scenario that could be exercised, but PackageKit, `Provides:`-based shadowing and the real COPR remain unverified, and the owner has not run anything on the ThinkPad.

## 4. Allowlist production (before Phase 4)

Before Phase 4, the project will present the complete COPR dependency allowlist and justify every package that must originate from the COPR. The method: preview the transaction (`--assumeno`) on the owner's machine with the repository supplied temporarily, list each COPR-sourced package it would pull, and review the list with the owner. Nothing is guessed. Until then the Hyprland rows stay `candidate`.

## 5. Rollback of package changes

ZackOS prints advice and never runs destructive package commands:

- `dnf5 history list` and `dnf5 history info <id>` to find the transaction.
- `sudo dnf5 history undo <id>` to reverse it (the owner runs it).
- `sudo dnf5 copr disable <owner>/<project>` to stop using a COPR, or `remove` to delete it.
- Removing the single ZackOS-owned override file.

The availability of these commands on Fedora 44 is verified by a CI scenario.
