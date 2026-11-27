# ADR 0005: Package sources and COPR isolation

- Status: accepted by the project owner on 2026-11-25
- Supersedes the "leave the COPR enabled" proposal made in the Phase 3 plan.

## Decision

1. Fedora repositories are the default source. A manifest (`packages/fedora44.tsv`) is the only list of packages ZackOS installs.
2. The `lionheartp/Hyprland` COPR is **not enabled in Phase 3**. Enable and disable operations are implemented as command builders and as a locked execution path (exit code 5). They stay locked until a later explicit approval.
3. ZackOS never enables a COPR silently or as a side effect of another command.
4. An `includepkgs` override is generated, tested and audited, but is not written to `/etc` in Phase 3.
5. The allowlist is not the only safety mechanism. The other layers are in `docs/PACKAGE-POLICY.md`.
6. Isolation is **not** described as complete until the Fedora 44 CI scenarios and the on-device checks pass.
7. Before Phase 5, the complete COPR dependency allowlist is presented with a justification for every package.

## Consequences

- Hyprland rows in the manifest are `candidate` and cannot be selected.
- If real DNF5 or PackageKit behavior contradicts the documentation, the design is changed before any unlock.
- The "COPR always enabled" and "COPR disabled at rest, enabled per transaction" options remain open for the Phase 5 decision.

> Renumbering note (2026-11-27): "Phase 4" in this record meant the Hyprland phase, which is now Phase 5 (Phase 4 became the terminal experience). See ROADMAP.md.
