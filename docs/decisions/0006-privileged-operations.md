# ADR 0006: Privileged operations

- Status: accepted by the project owner on 2026-11-25

## Decision

- ZackOS runs as a normal user and refuses to run as root.
- Anything needing root is a **privileged step**: a command plus a description and an undo description, run through `sudo` by `lib/priv.sh` and nothing else.
- Every step is **individually confirmed**: the exact command and its undo are printed, and the user must type `yes` for that step. There is no global "assume yes" for privileged steps.
- **Dry-run is the default.** Without `--apply` a step only prints what it would do.
- Every executed step is appended to `~/.local/state/zackos/priv-journal.tsv` (time, description, command, undo, result).
- ZackOS never performs destructive package rollback. Undo information is printed as advice for the owner to run.
- The only privileged steps available in Phase 3 are installing approved Fedora packages. COPR steps are locked (ADR 0005).

## Consequences

Scripts cannot hide `sudo` calls. Tests replace `sudo`, `dnf5` and `rpm` with fakes and assert that no real privileged command can be reached.
