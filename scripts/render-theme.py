#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Render ZackOS theme files from design/palette.toml.

Usage:
    python3 scripts/render-theme.py            write generated files
    python3 scripts/render-theme.py --check    exit 1 if any committed file is stale
    python3 scripts/render-theme.py --report   print contrast ratios

Only the Python standard library is needed (Python 3.11+ for tomllib). This is a
development-time tool: generated files are committed, so installing ZackOS never runs it.
"""

from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PALETTE_PATH = ROOT / "design" / "palette.toml"
TARGETS_PATH = ROOT / "design" / "targets.toml"
TEMPLATE_DIR = ROOT / "design" / "templates"

REQUIRED_COLORS = ("background", "background_alt", "accent", "green", "text", "muted", "border")
REQUIRED_SEMANTIC = ("warning", "error")
HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
TAG_RE = re.compile(r"\{\{\s*([\w.]+)\s*(?:\|\s*(\w+)\s*(?::\s*([\w.]+)\s*)?)?\}\}")
HEADER_MARK = "@@HEADER@@"

# (foreground key, background key, minimum WCAG contrast ratio)
CONTRAST_RULES = (
    ("text", "background", 7.0),
    ("text", "background_alt", 7.0),
    ("muted", "background", 4.5),
    ("muted", "background_alt", 4.5),
    ("accent", "background", 4.5),
    ("green", "background", 4.5),
    ("background", "accent", 4.5),  # text drawn on an accent-colored fill
)


class ThemeError(Exception):
    """Raised for invalid palette data, templates or targets."""


# ---------------------------------------------------------------- color helpers
def _to_rgb(value: str) -> tuple[int, int, int]:
    return int(value[1:3], 16), int(value[3:5], 16), int(value[5:7], 16)


def _alpha_byte(alpha: float) -> str:
    if not 0.0 <= alpha <= 1.0:
        raise ThemeError(f"alpha must be between 0 and 1, got {alpha}")
    return f"{round(alpha * 255):02x}"


def luminance(value: str) -> float:
    def channel(c: int) -> float:
        s = c / 255
        return s / 12.92 if s <= 0.03928 else ((s + 0.055) / 1.055) ** 2.4

    r, g, b = (channel(c) for c in _to_rgb(value))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(fg: str, bg: str) -> float:
    a, b = luminance(fg), luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


# ---------------------------------------------------------------------- filters
def _filter_hex(value: str, arg: float | None) -> str:
    return value.upper()


def _filter_nohash(value: str, arg: float | None) -> str:
    return value[1:].upper()


def _filter_rgb(value: str, arg: float | None) -> str:
    return "{}, {}, {}".format(*_to_rgb(value))


def _filter_rgbsc(value: str, arg: float | None) -> str:
    return "{};{};{}".format(*_to_rgb(value))


def _filter_hexa(value: str, arg: float | None) -> str:
    if arg is None:
        raise ThemeError("filter 'hexa' needs an alpha argument, e.g. hexa:0.9")
    return value.upper() + _alpha_byte(arg).upper()


def _filter_css_rgba(value: str, arg: float | None) -> str:
    if arg is None:
        raise ThemeError("filter 'css_rgba' needs an alpha argument, e.g. css_rgba:0.9")
    return "rgba({}, {}, {}, {})".format(*_to_rgb(value), arg)


def _filter_hypr(value: str, arg: float | None) -> str:
    body = value[1:].lower()
    return f"rgba({body}{_alpha_byte(arg)})" if arg is not None else f"rgb({body})"


FILTERS = {
    "hex": _filter_hex,
    "nohash": _filter_nohash,
    "rgb": _filter_rgb,
    "rgbsc": _filter_rgbsc,
    "hexa": _filter_hexa,
    "css_rgba": _filter_css_rgba,
    "hypr": _filter_hypr,
}


# ------------------------------------------------------------------- data access
def load_toml(path: Path) -> dict:
    try:
        with path.open("rb") as fh:
            return tomllib.load(fh)
    except FileNotFoundError as exc:
        raise ThemeError(f"missing file: {path.relative_to(ROOT)}") from exc
    except tomllib.TOMLDecodeError as exc:
        raise ThemeError(f"invalid TOML in {path.relative_to(ROOT)}: {exc}") from exc


def lookup(data: dict, dotted: str):
    node = data
    for part in dotted.split("."):
        if isinstance(node, dict) and part in node:
            node = node[part]
        elif isinstance(node, list) and part.isdigit() and int(part) < len(node):
            node = node[int(part)]
        else:
            raise ThemeError(f"unknown palette key: {dotted}")
    return node


def validate_palette(palette: dict) -> list[str]:
    """Return a list of error strings (empty when the palette is valid)."""
    errors: list[str] = []
    for section, keys in (("colors", REQUIRED_COLORS), ("semantic", REQUIRED_SEMANTIC)):
        table = palette.get(section, {})
        for key in keys:
            if key not in table:
                errors.append(f"[{section}] missing required key '{key}'")
    for section in ("colors", "semantic"):
        for key, value in palette.get(section, {}).items():
            if not isinstance(value, str) or not HEX_RE.match(value):
                errors.append(f"[{section}] {key} = {value!r} is not a #RRGGBB color")
    ansi = palette.get("ansi", {})
    for group in ("normal", "bright"):
        items = ansi.get(group)
        if not isinstance(items, list) or len(items) != 8:
            errors.append(f"[ansi] {group} must be a list of 8 colors")
            continue
        for i, value in enumerate(items):
            if not isinstance(value, str) or not HEX_RE.match(value):
                errors.append(f"[ansi] {group}[{i}] = {value!r} is not a #RRGGBB color")
    if errors:
        return errors
    colors = palette["colors"]
    for fg, bg, minimum in CONTRAST_RULES:
        ratio = contrast(colors[fg], colors[bg])
        if ratio < minimum:
            errors.append(f"contrast {fg} on {bg} is {ratio:.2f}:1, below required {minimum}:1")
    return errors


def contrast_report(palette: dict) -> str:
    colors = palette["colors"]
    lines = ["foreground on background          ratio   required"]
    for fg, bg, minimum in CONTRAST_RULES:
        ratio = contrast(colors[fg], colors[bg])
        flag = "ok" if ratio >= minimum else "FAIL"
        lines.append(f"{fg:>10} on {bg:<15} {ratio:6.2f}   {minimum:<4} {flag}")
    return "\n".join(lines)


# --------------------------------------------------------------------- rendering
def render_value(palette: dict, key: str, filter_name: str | None, arg: str | None) -> str:
    value = lookup(palette, key)
    if isinstance(value, (dict, list)):
        raise ThemeError(f"palette key '{key}' is not a scalar")
    if filter_name is None:
        if isinstance(value, bool):
            return "true" if value else "false"
        if isinstance(value, str) and HEX_RE.match(value):
            return value.upper()
        return str(value)
    if filter_name not in FILTERS:
        raise ThemeError(f"unknown filter '{filter_name}'")
    if not (isinstance(value, str) and HEX_RE.match(value)):
        raise ThemeError(f"filter '{filter_name}' needs a color, but '{key}' is {value!r}")
    alpha: float | None = None
    if arg is not None:
        try:
            alpha = float(arg)
        except ValueError:
            alpha = float(lookup(palette, arg))
    return FILTERS[filter_name](value, alpha)


def build_header(template: str, comment_open: str, comment_close: str) -> str:
    lines = (
        "GENERATED FILE. DO NOT EDIT.",
        f"Source: design/palette.toml (template: design/templates/{template})",
        "Regenerate: python3 scripts/render-theme.py",
        "SPDX-License-Identifier: GPL-3.0-or-later",
    )
    out = []
    for line in lines:
        text = f"{comment_open} {line}"
        if comment_close:
            text += f" {comment_close}"
        out.append(text)
    return "\n".join(out)


def render_target(palette: dict, target: dict) -> str:
    template_name = target["template"]
    path = TEMPLATE_DIR / template_name
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise ThemeError(f"missing template: design/templates/{template_name}") from exc
    if HEADER_MARK not in text:
        raise ThemeError(f"template {template_name} has no {HEADER_MARK} marker")
    header = build_header(template_name, target["comment_open"], target["comment_close"])
    text = text.replace(HEADER_MARK, header, 1)
    rendered = TAG_RE.sub(lambda m: render_value(palette, m.group(1), m.group(2), m.group(3)), text)
    if "{{" in rendered or "}}" in rendered:
        raise ThemeError(f"template {template_name} has an unparsed tag")
    return rendered if rendered.endswith("\n") else rendered + "\n"


def render_all() -> dict[Path, str]:
    palette = load_toml(PALETTE_PATH)
    errors = validate_palette(palette)
    if errors:
        raise ThemeError("invalid palette:\n  " + "\n  ".join(errors))
    targets = load_toml(TARGETS_PATH).get("target", [])
    if not targets:
        raise ThemeError("design/targets.toml defines no targets")
    outputs: dict[Path, str] = {}
    for target in targets:
        for key in ("template", "output", "comment_open", "comment_close"):
            if key not in target:
                raise ThemeError(f"target {target.get('output', '?')} is missing '{key}'")
        out_path = (ROOT / target["output"]).resolve()
        if ROOT not in out_path.parents:
            raise ThemeError(f"output path escapes the repository: {target['output']}")
        if out_path in outputs:
            raise ThemeError(f"duplicate output: {target['output']}")
        outputs[out_path] = render_target(palette, target)
    return outputs


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="fail if committed files are stale")
    mode.add_argument("--report", action="store_true", help="print contrast ratios and exit")
    args = parser.parse_args(argv)

    try:
        if args.report:
            print(contrast_report(load_toml(PALETTE_PATH)))
            return 0
        outputs = render_all()
    except ThemeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.check:
        stale = []
        for path, content in outputs.items():
            current = path.read_text(encoding="utf-8") if path.exists() else None
            if current != content:
                stale.append(path.relative_to(ROOT))
        if stale:
            print("stale or missing generated files:", file=sys.stderr)
            for rel in stale:
                print(f"  {rel}", file=sys.stderr)
            print("run: python3 scripts/render-theme.py", file=sys.stderr)
            return 1
        print(f"ok: {len(outputs)} generated files are up to date")
        return 0

    for path, content in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() and path.read_text(encoding="utf-8") == content:
            print(f"unchanged  {path.relative_to(ROOT)}")
            continue
        path.write_text(content, encoding="utf-8")
        print(f"wrote      {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
