// Neutral small-text pairs from source colors, alpha composited in sRGB, not full WCAG:
// https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const CSS = read('site/styles.css');
const HTML = read('site/index.html');

function block(source, pattern, name) {
  const match = source.match(pattern);
  assert.ok(match, `Missing ${name}`);
  return match[1];
}

function tokens(body) {
  return Object.fromEntries([...body.matchAll(/(--[\w-]+)\s*:\s*([^;]+);/g)].map((m) => [m[1], m[2]]));
}

function themeTokens() {
  const base = tokens(block(CSS, /:root\s*\{([^{}]+)\}/, ':root tokens'));
  const marker = '@media (prefers-color-scheme: dark)';
  assert.ok(CSS.includes(marker), 'Missing automatic dark theme');
  const automatic = CSS.slice(CSS.indexOf(marker) + marker.length);
  const themes = {
    'automatic-light': base,
    'automatic-dark': { ...base, ...tokens(block(automatic, /:root\s*\{([^{}]+)\}/, 'dark tokens')) },
  };
  for (const theme of ['light', 'dark']) {
    const pattern = new RegExp(`:root\\[data-theme="${theme}"\\]\\s*\\{([^{}]+)\\}`);
    themes[`explicit-${theme}`] = { ...base, ...tokens(block(CSS, pattern, `${theme} theme`)) };
  }
  return themes;
}

function color(value, palette) {
  value = value.trim();
  if (value.startsWith('var(')) {
    const name = value.slice(4, -1);
    assert.ok(name in palette, `Unknown token ${name}`);
    return color(palette[name], palette);
  }
  if (value.startsWith('#')) {
    assert.match(value, /^#[\da-f]{6}$/i, `Unsupported hex color: ${value}`);
    return [1, 3, 5].map((i) => Number.parseInt(value.slice(i, i + 2), 16) / 255).concat(1);
  }
  const match = value.match(/^rgba\(([^)]+)\)$/);
  assert.ok(match, `Unsupported color: ${value}`);
  const components = match[1].split(',').map(Number);
  assert.ok(components.length === 4 && components.every(Number.isFinite), `Invalid rgba color: ${value}`);
  return [...components.slice(0, 3).map((c) => c / 255), components[3]];
}

function over(foreground, background) {
  const alpha = foreground[3];
  return foreground.slice(0, 3).map((c, i) => c * alpha + background[i] * (1 - alpha)).concat(1);
}

function luminance(rgb) {
  const linear = rgb.slice(0, 3).map((v) => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722;
}

function contrast(foreground, background) {
  const values = [luminance(over(foreground, background)), luminance(background)];
  return (Math.max(...values) + 0.05) / (Math.min(...values) + 0.05);
}

function style(selector) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return block(HTML, new RegExp(`^\\s*${escaped}\\s*\\{([^{}]+)\\}`, 'm'), `style for ${selector}`);
}

// Bounded source pairs: no brand/syntax colors, gradients or blur.
const PAIRS = [
  ['.price-fine', '--text-tertiary', '--surface-card', false],
  ['.price-tier', '--text-tertiary', '--surface-card', false],
  ['.price-note', '--text-secondary', '--surface-card', false],
  ['.foot-note', '--text-tertiary', '--surface-app', false],
  ['.sa-note', '--text-tertiary', '--surface-app', false],
  ['.ph-search', '--text-tertiary', '--surface-app', true],
  ['.ic-card .tier', '--text-tertiary', '--surface-card', true],
];

test('formula matches known values', () => {
  const black = [0, 0, 0, 1], white = [1, 1, 1, 1];
  assert.equal(contrast(black, white), 21);
  assert.equal(contrast(white, black), 21);
  assert.equal(contrast(black, black), 1);
  assert.ok(Math.abs(contrast([0, 0, 0, 0.5], white) - 3.976653) < 0.0000005);
});

test('pairs still describe the actual small-text styles', () => {
  for (const [selector, foreground, , selected] of PAIRS) {
    const body = style(selector);
    assert.ok(body.includes(`color: var(${foreground})`), selector);
    if (selected) assert.ok(body.includes('background: var(--surface-selection)'), selector);
  }
  for (const [selector, background] of [['.price-card', '--surface-card'], ['.ic-card', '--surface-card'],
    ['.phone-scr', '--surface-app'], ['body', '--surface-app']]) {
    assert.ok(style(selector).includes(`background: var(${background})`), selector);
  }
});

test('primary, secondary and tertiary hierarchy is preserved', () => {
  for (const [theme, palette] of Object.entries(themeTokens())) {
    for (const surface of ['--surface-app', '--surface-card']) {
      const background = color(palette[surface], palette);
      const [primary, secondary, tertiary] = ['--text-primary', '--text-secondary', '--text-tertiary']
        .map((token) => contrast(color(palette[token], palette), background));
      assert.ok(primary > secondary && secondary > tertiary, `${theme} ${surface}`);
    }
  }
});

test('small-text pairs meet 4.5:1 without rounding', () => {
  for (const [theme, palette] of Object.entries(themeTokens())) {
    for (const [selector, foreground, background, selected] of PAIRS) {
      let surface = color(palette[background], palette);
      if (selected) surface = over(color(palette['--surface-selection'], palette), surface);
      const ratio = contrast(color(palette[foreground], palette), surface);
      assert.ok(ratio >= 4.5, `${theme} ${selector}: ${ratio.toFixed(6)}:1`);
    }
  }
});
