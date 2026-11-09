#!/usr/bin/env node
// Check neutral small-text pairs, not full WCAG conformance. Composite alpha
// in sRGB before applying the WCAG relative-luminance contrast formula:
// https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
import assert from 'node:assert/strict';
import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function tokens(body) {
  return Object.fromEntries([...body.matchAll(/(--[\w-]+)\s*:\s*([^;]+);/g)]
    .map((match) => [match[1], match[2]]));
}

export function themeTokens(css) {
  const base = tokens(css.match(/:root\s*\{([^{}]+)\}/)[1]);
  const marker = '@media (prefers-color-scheme: dark)';
  const start = css.indexOf(marker);
  assert.ok(start >= 0, 'Missing automatic dark theme');
  const automatic = css.slice(start + marker.length);
  const themes = {
    'automatic-light': base,
    'automatic-dark': { ...base, ...tokens(automatic.match(/:root\s*\{([^{}]+)\}/)[1]) },
  };
  for (const theme of ['light', 'dark']) {
    const pattern = new RegExp(`:root\\[data-theme="${theme}"\\]\\s*\\{([^{}]+)\\}`);
    themes[`explicit-${theme}`] = { ...base, ...tokens(css.match(pattern)[1]) };
  }
  return themes;
}

export function color(value, palette) {
  value = value.trim();
  if (value.startsWith('var(')) return color(palette[value.slice(4, -1)], palette);
  if (value.startsWith('#')) {
    return [1, 3, 5].map((offset) => {
      const hex = value.slice(offset, offset + 2);
      assert.match(hex, /^[\da-f]+$/i, `Invalid hex color: ${value}`);
      return Number.parseInt(hex, 16) / 255;
    }).concat(1);
  }
  const match = value.match(/^rgba\(([^)]+)\)$/);
  if (match) {
    const components = match[1].split(',').map((component) => {
      assert.match(component.trim(), /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i,
        `Invalid rgba color: ${value}`);
      return Number(component);
    });
    assert.equal(components.length, 4, `Invalid rgba color: ${value}`);
    return [...components.slice(0, 3).map((component) => component / 255), components[3]];
  }
  throw new Error(`Unsupported color: ${value}`);
}

export function over(foreground, background) {
  assert.equal(background[3], 1, 'Compositing requires an opaque backing surface');
  const alpha = foreground[3];
  return foreground.slice(0, 3)
    .map((component, index) => component * alpha + background[index] * (1 - alpha)).concat(1);
}

export function luminance(rgb) {
  const linear = rgb.slice(0, 3).map((value) => value <= 0.04045
    ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return linear.reduce((sum, value, index) => sum + value * [0.2126, 0.7152, 0.0722][index], 0);
}

export function contrast(foreground, background) {
  const values = [luminance(over(foreground, background)), luminance(background)];
  return (Math.max(...values) + 0.05) / (Math.min(...values) + 0.05);
}

// Bounded source pairs: no brand/syntax colors, gradients or blur.
export const PAIRS = [
  ['.price-fine', '--text-tertiary', '--surface-card', false],
  ['.price-tier', '--text-tertiary', '--surface-card', false],
  ['.price-note', '--text-secondary', '--surface-card', false],
  ['.foot-note', '--text-tertiary', '--surface-app', false],
  ['.sa-note', '--text-tertiary', '--surface-app', false],
  ['.ph-search', '--text-tertiary', '--surface-app', true],
  ['.ic-card .tier', '--text-tertiary', '--surface-card', true],
];

function allCases(cases, check) {
  const errors = [];
  for (const entry of cases) {
    try { check(entry); } catch (error) { errors.push(error); }
  }
  if (errors.length) throw new AggregateError(errors, 'Site contrast checks failed');
}

function style(html, selector) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return html.match(new RegExp(`^\\s*${escaped}\\s*\\{([^{}]+)\\}`, 'm'))[1];
}

export function checks(css, html) {
  return {
    test_formula_known_values() {
      const black = [0, 0, 0, 1], white = [1, 1, 1, 1];
      assert.equal(contrast(black, white), 21);
      assert.equal(contrast(white, black), 21);
      assert.equal(contrast(black, black), 1);
      assert.ok(Math.abs(contrast([0, 0, 0, 0.5], white) - 3.976653) < 0.0000005);
    },
    test_pairs_still_describe_the_actual_small_text_styles() {
      const declarations = PAIRS.map(([selector, foreground, , selected]) =>
        [selector, `color: var(${foreground})`, selected]);
      declarations.push(...[['.price-card', '--surface-card'], ['.ic-card', '--surface-card'],
        ['.phone-scr', '--surface-app'], ['body', '--surface-app']]
        .map(([selector, background]) => [selector, `background: var(${background})`, false]));
      allCases(declarations, ([selector, declaration, selected]) => {
        const body = style(html, selector);
        assert.ok(body.includes(declaration), selector);
        if (selected) assert.ok(body.includes('background: var(--surface-selection)'), selector);
      });
    },
    test_primary_secondary_tertiary_hierarchy_is_preserved() {
      allCases(Object.entries(themeTokens(css)), ([theme, palette]) => {
        allCases(['--surface-app', '--surface-card'], (surface) => {
          const background = color(palette[surface], palette);
          const ratios = ['--text-primary', '--text-secondary', '--text-tertiary']
            .map((token) => contrast(color(palette[token], palette), background));
          assert.ok(ratios[0] > ratios[1] && ratios[1] > ratios[2], `${theme} ${surface}`);
        });
      });
    },
    test_small_text_pairs_meet_four_point_five_without_rounding() {
      allCases(Object.entries(themeTokens(css)), ([theme, palette]) => {
        allCases(PAIRS, ([selector, foreground, background, selected]) => {
          let surface = color(palette[background], palette);
          if (selected) surface = over(color(palette['--surface-selection'], palette), surface);
          const ratio = contrast(color(palette[foreground], palette), surface);
          assert.ok(ratio >= 4.5, `${theme} ${selector}: ${ratio.toFixed(6)}:1`);
        });
      });
    },
  };
}

function diagnostic(error) {
  return error instanceof AggregateError ? error.errors.map(diagnostic).join('\n') : error.message;
}

// Keep the gate's four-check summary on stderr; regression tests use node:test separately.
export function main(args = process.argv.slice(2), root = new URL('../', import.meta.url)) {
  if (args.some((arg) => !['-v', '--verbose', '-q', '--quiet', '-h', '--help'].includes(arg))) {
    process.stderr.write('Usage: check-site-contrast.mjs [-v | -q]\n');
    return 2;
  }
  if (args.includes('-h') || args.includes('--help')) {
    process.stdout.write('Usage: check-site-contrast.mjs [-v | -q]\n');
    return 0;
  }
  let verbosity = 1;
  for (const arg of args) verbosity = ['-v', '--verbose'].includes(arg) ? 2 : 0;
  const verbose = verbosity === 2, quiet = verbosity === 0;
  const started = performance.now();
  let failures = 0;
  try {
    const css = readFileSync(new URL('site/styles.css', root), 'utf8');
    const html = readFileSync(new URL('site/index.html', root), 'utf8');
    for (const [name, check] of Object.entries(checks(css, html))) {
      try {
        check();
        if (!quiet) process.stderr.write(verbose ? `${name} ... ok\n` : '.');
      } catch (error) {
        failures += 1;
        process.stderr.write(`\nFAIL: ${name}\n${diagnostic(error)}\n`);
      }
    }
    process.stderr.write(`${quiet || verbose ? '' : '\n'}${'-'.repeat(70)}\nRan 4 tests in ${((performance.now() - started) / 1000).toFixed(3)}s\n\n`);
    process.stderr.write(failures ? `FAILED (failures=${failures})\n` : 'OK\n');
    return failures ? 1 : 0;
  } catch (error) {
    process.stderr.write(`${diagnostic(error)}\n`);
    return 1;
  }
}

if (process.argv[1] && existsSync(process.argv[1])
    && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  process.exitCode = main();
}
