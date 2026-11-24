# ADR 0003: Generated theme files are committed

- Status: accepted by the project owner on 2026-11-24

## Decision

`design/palette.toml` is the only place colors, fonts, geometry and effects are defined. Files generated from it are committed, so installing ZackOS never needs a generation step.

## How it stays trustworthy

- Every generated file starts with a "GENERATED FILE. DO NOT EDIT." header naming its source and the regeneration command.
- `python3 scripts/render-theme.py --check` and the unit tests fail if any committed file differs from a fresh render. CI runs them on every push.
- The generator is deterministic (no timestamps) and uses only the Python standard library.
- The palette is validated: required keys, valid colors, minimum WCAG contrast.

## Consequences

Changing a color is a two-step commit: edit the palette, run the generator, commit both. Generated files are never edited by hand.
