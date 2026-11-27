# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for scripts/render-theme.py. Run: python3 -m unittest discover -s tests -v"""

import copy
import importlib.util
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("render_theme", ROOT / "scripts" / "render-theme.py")
rt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rt)


def good_palette() -> dict:
    return copy.deepcopy(rt.load_toml(rt.PALETTE_PATH))


class PaletteValidation(unittest.TestCase):
    def test_committed_palette_is_valid(self):
        self.assertEqual(rt.validate_palette(good_palette()), [])

    def test_approved_colors_match_brief(self):
        c = good_palette()["colors"]
        self.assertEqual(c["background"], "#090E12")
        self.assertEqual(c["background_alt"], "#111B22")
        self.assertEqual(c["accent"], "#00D9FF")
        self.assertEqual(c["green"], "#00E676")
        self.assertEqual(c["text"], "#D8E5E9")
        self.assertEqual(c["muted"], "#81949C")
        self.assertEqual(c["border"], "#20323B")

    def test_missing_required_key(self):
        p = good_palette()
        del p["colors"]["accent"]
        self.assertTrue(any("accent" in e for e in rt.validate_palette(p)))

    def test_invalid_hex(self):
        p = good_palette()
        p["colors"]["text"] = "D8E5E9"
        self.assertTrue(any("not a #RRGGBB" in e for e in rt.validate_palette(p)))

    def test_ansi_length(self):
        p = good_palette()
        p["ansi"]["normal"] = p["ansi"]["normal"][:7]
        self.assertTrue(any("list of 8" in e for e in rt.validate_palette(p)))

    def test_low_contrast_is_rejected(self):
        p = good_palette()
        p["colors"]["text"] = "#0A0F13"
        self.assertTrue(any("contrast text on background" in e for e in rt.validate_palette(p)))


class Filters(unittest.TestCase):
    def test_contrast_black_white(self):
        self.assertAlmostEqual(rt.contrast("#000000", "#FFFFFF"), 21.0, places=1)

    def test_filters(self):
        v = "#00D9FF"
        self.assertEqual(rt.FILTERS["hex"]("#00d9ff", None), v)
        self.assertEqual(rt.FILTERS["nohash"](v, None), "00D9FF")
        self.assertEqual(rt.FILTERS["rgb"](v, None), "0, 217, 255")
        self.assertEqual(rt.FILTERS["rgbsc"](v, None), "0;217;255")
        self.assertEqual(rt.FILTERS["hexa"](v, 1.0), "#00D9FFFF")
        self.assertEqual(rt.FILTERS["hexa"](v, 0.0), "#00D9FF00")
        self.assertEqual(rt.FILTERS["hypr"](v, None), "rgb(00d9ff)")
        self.assertEqual(rt.FILTERS["hypr"](v, 1.0), "rgba(00d9ffff)")
        self.assertEqual(rt.FILTERS["css_rgba"](v, 0.5), "rgba(0, 217, 255, 0.5)")

    def test_alpha_out_of_range(self):
        with self.assertRaises(rt.ThemeError):
            rt.FILTERS["hexa"]("#00D9FF", 1.5)

    def test_alpha_filter_requires_argument(self):
        with self.assertRaises(rt.ThemeError):
            rt.FILTERS["hexa"]("#00D9FF", None)


class Rendering(unittest.TestCase):
    def test_lookup_list_index_and_errors(self):
        p = good_palette()
        self.assertEqual(rt.lookup(p, "ansi.normal.5"), "#00D9FF")
        with self.assertRaises(rt.ThemeError):
            rt.lookup(p, "colors.nope")
        with self.assertRaises(rt.ThemeError):
            rt.lookup(p, "ansi.normal.99")

    def test_render_value_defaults(self):
        p = good_palette()
        self.assertEqual(rt.render_value(p, "colors.accent", None, None), "#00D9FF")
        self.assertEqual(rt.render_value(p, "effects.blur", None, None), "true")
        self.assertEqual(rt.render_value(p, "geometry.radius", None, None), "8")

    def test_alpha_argument_can_be_palette_key(self):
        p = good_palette()
        out = rt.render_value(p, "colors.background", "css_rgba", "effects.bar_opacity")
        self.assertEqual(out, "rgba(9, 14, 18, 0.92)")

    def test_filter_on_non_color_fails(self):
        with self.assertRaises(rt.ThemeError):
            rt.render_value(good_palette(), "geometry.radius", "hex", None)

    def test_unknown_filter_fails(self):
        with self.assertRaises(rt.ThemeError):
            rt.render_value(good_palette(), "colors.accent", "nope", None)

    def test_header_comment_styles(self):
        hash_header = rt.build_header("x.tmpl", "#", "")
        self.assertTrue(all(line.startswith("# ") for line in hash_header.splitlines()))
        css_header = rt.build_header("x.tmpl", "/*", "*/")
        self.assertTrue(all(line.startswith("/* ") and line.endswith(" */") for line in css_header.splitlines()))
        self.assertIn("SPDX-License-Identifier: GPL-3.0-or-later", hash_header)

    def test_rendering_is_deterministic(self):
        self.assertEqual(rt.render_all(), rt.render_all())

    def test_no_unresolved_tags_and_trailing_newline(self):
        for path, content in rt.render_all().items():
            with self.subTest(path=path.name):
                self.assertNotIn("{{", content)
                self.assertNotIn("@@HEADER@@", content)
                self.assertTrue(content.endswith("\n"))
                self.assertIn("GENERATED FILE", content)


class RepositorySync(unittest.TestCase):
    """The key guarantee: committed generated files equal a fresh render."""

    def test_generated_files_are_up_to_date(self):
        for path, content in rt.render_all().items():
            with self.subTest(path=str(path.relative_to(ROOT))):
                self.assertTrue(path.exists(), "generated file is missing")
                self.assertEqual(path.read_text(encoding="utf-8"), content)

    def test_every_template_has_a_target(self):
        targets = rt.load_toml(rt.TARGETS_PATH)["target"]
        used = {t["template"] for t in targets}
        present = {p.name for p in rt.TEMPLATE_DIR.glob("*.tmpl")}
        self.assertEqual(used, present)

    def test_main_check_mode_passes(self):
        self.assertEqual(rt.main(["--check"]), 0)


if __name__ == "__main__":
    unittest.main()


class FastfetchConfig(unittest.TestCase):
    """The Fastfetch identity: structure checks that need no Fastfetch binary.
    (The real binary is exercised by the Fedora 44 terminal job.)"""

    TEMPLATE = ROOT / "design" / "templates" / "fastfetch.jsonc.tmpl"
    OUTPUT = ROOT / "modules" / "fastfetch" / "files" / ".config" / "fastfetch" / "config.jsonc"

    def load(self):
        text = "\n".join(l for l in self.OUTPUT.read_text().splitlines() if not l.lstrip().startswith("//"))
        return json.loads(text)

    def test_template_has_no_raw_colors(self):
        self.assertIsNone(re.search(r"#[0-9A-Fa-f]{6}\b", self.TEMPLATE.read_text()), "use {{ colors.x }}")

    def test_config_is_valid_jsonc(self):
        self.assertIsInstance(self.load(), dict)

    def test_only_known_top_level_keys(self):
        self.assertLessEqual(set(self.load()), {"$schema", "logo", "display", "modules"})

    def test_logo_is_ascii_with_both_palette_colors(self):
        logo = self.load()["logo"]
        self.assertEqual(logo["type"], "data")
        self.assertTrue(logo["source"].isascii(), "no Nerd Font or other non-ASCII glyphs in the logo")
        self.assertIn("$1", logo["source"])
        self.assertIn("$2", logo["source"])
        self.assertEqual(set(logo["color"]), {"1", "2"})
        self.assertNotIn("\\", logo["source"].replace("\n", ""))

    def test_fedora_stays_identified_as_the_os(self):
        mods = self.load()["modules"]
        self.assertIn("os", mods)
        self.assertIn("Matrix Edition", json.dumps(mods))
        self.assertNotIn("ZackOS Linux", self.OUTPUT.read_text())

    def test_useful_system_info_is_kept(self):
        mods = [m if isinstance(m, str) else m["type"] for m in self.load()["modules"]]
        for needed in ("kernel", "uptime", "packages", "shell", "terminal", "de", "wm", "cpu", "gpu", "memory", "disk"):
            self.assertIn(needed, mods)


class KittyTheme(unittest.TestCase):
    OUTPUT = ROOT / "modules" / "kitty" / "files" / ".config" / "kitty" / "zackos-theme.conf"

    def entries(self):
        for line in self.OUTPUT.read_text().splitlines():
            if line.strip() and not line.startswith("#"):
                yield line.split(None, 1)

    def test_every_line_is_key_value(self):
        for parts in self.entries():
            self.assertEqual(len(parts), 2, parts)

    def test_color_options_are_valid_hex(self):
        for key, value in self.entries():
            if key.endswith(("color", "foreground", "background")) or re.fullmatch(r"color\d+", key):
                self.assertRegex(value, r"^#[0-9A-F]{6}$", key)

    def test_mark_text_is_always_the_dark_background(self):
        bg = good_palette()["colors"]["background"]
        values = dict(self.entries())
        for n in (1, 2, 3):
            self.assertEqual(values[f"mark{n}_foreground"], bg)
