#!/usr/bin/env python3
"""Check the site's neutral small-text pairs, not full WCAG conformance.

Use source colors rather than antialiased screenshot pixels. Composite alpha
in sRGB before applying the WCAG relative-luminance contrast formula:
https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CSS = (ROOT / "site/styles.css").read_text()
HTML = (ROOT / "site/index.html").read_text()


def tokens(body):
    return dict(re.findall(r"(--[\w-]+)\s*:\s*([^;]+);", body))


def theme_tokens():
    base = tokens(re.search(r":root\s*\{([^{}]+)\}", CSS).group(1))
    auto = CSS.split("@media (prefers-color-scheme: dark)", 1)[1]
    auto = tokens(re.search(r":root\s*\{([^{}]+)\}", auto).group(1))
    themes = {"automatic-light": base, "automatic-dark": base | auto}
    for theme in ("light", "dark"):
        pattern = r':root\[data-theme="' + theme + r'"\]\s*\{([^{}]+)\}'
        themes["explicit-" + theme] = base | tokens(re.search(pattern, CSS).group(1))
    return themes


def color(value, palette):
    value = value.strip()
    if value.startswith("var("):
        return color(palette[value[4:-1]], palette)
    if value.startswith("#"):
        return tuple(int(value[i:i + 2], 16) / 255 for i in (1, 3, 5)) + (1.0,)
    match = re.fullmatch(r"rgba\(([^)]+)\)", value)
    if match:
        red, green, blue, alpha = map(float, match.group(1).split(","))
        return red / 255, green / 255, blue / 255, alpha
    raise ValueError(f"Unsupported color: {value}")


def over(foreground, background):
    assert background[3] == 1, "Compositing requires an opaque backing surface"
    alpha = foreground[3]
    return tuple(foreground[i] * alpha + background[i] * (1 - alpha)
                 for i in range(3)) + (1.0,)


def luminance(rgb):
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
              for v in rgb[:3]]
    return sum(v * weight for v, weight in zip(linear, (0.2126, 0.7152, 0.0722)))


def contrast(foreground, background):
    bright, dark = sorted((luminance(over(foreground, background)),
                           luminance(background)), reverse=True)
    return (bright + 0.05) / (dark + 0.05)


# Each pair names real neutral text and the surface(s) declared by its parent.
# This bounded check does not cover brand/syntax colors, gradients or blur.
PAIRS = (
    (".price-fine", "--text-tertiary", "--surface-card", False),
    (".price-tier", "--text-tertiary", "--surface-card", False),
    (".price-note", "--text-secondary", "--surface-card", False),
    (".foot-note", "--text-tertiary", "--surface-app", False),
    (".sa-note", "--text-tertiary", "--surface-app", False),
    (".ph-search", "--text-tertiary", "--surface-app", True),
    (".ic-card .tier", "--text-tertiary", "--surface-card", True),
)


class SiteContrastTests(unittest.TestCase):
    def test_formula_known_values(self):
        black, white = (0, 0, 0, 1), (1, 1, 1, 1)
        self.assertEqual(contrast(black, white), 21)
        self.assertEqual(contrast(white, black), 21)
        self.assertEqual(contrast(black, black), 1)
        self.assertAlmostEqual(contrast((0, 0, 0, 0.5), white), 3.976653, places=6)

    def test_pairs_still_describe_the_actual_small_text_styles(self):
        for selector, foreground, _, selected in PAIRS:
            with self.subTest(selector=selector):
                body = re.search(r"(?m)^\s*" + re.escape(selector) + r"\s*\{([^{}]+)\}", HTML).group(1)
                self.assertIn(f"color: var({foreground})", body)
                if selected:
                    self.assertIn("background: var(--surface-selection)", body)
        for selector, background in ((".price-card", "--surface-card"),
                                     (".ic-card", "--surface-card"),
                                     (".phone-scr", "--surface-app"),
                                     ("body", "--surface-app")):
            body = re.search(r"(?m)^\s*" + re.escape(selector) + r"\s*\{([^{}]+)\}", HTML).group(1)
            self.assertIn(f"background: var({background})", body)

    def test_small_text_pairs_meet_four_point_five_without_rounding(self):
        for theme, palette in theme_tokens().items():
            for selector, foreground, background, selected in PAIRS:
                with self.subTest(theme=theme, selector=selector):
                    surface = color(palette[background], palette)
                    if selected:
                        surface = over(color(palette["--surface-selection"], palette), surface)
                    ratio = contrast(color(palette[foreground], palette), surface)
                    self.assertGreaterEqual(ratio, 4.5, f"{theme} {selector}: {ratio:.6f}:1")

    def test_primary_secondary_tertiary_hierarchy_is_preserved(self):
        for theme, palette in theme_tokens().items():
            for surface in ("--surface-app", "--surface-card"):
                with self.subTest(theme=theme, surface=surface):
                    background = color(palette[surface], palette)
                    ratios = [contrast(color(palette[token], palette), background)
                              for token in ("--text-primary", "--text-secondary", "--text-tertiary")]
                    self.assertGreater(ratios[0], ratios[1])
                    self.assertGreater(ratios[1], ratios[2])


if __name__ == "__main__":
    unittest.main()
