import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { PAIRS, checks, color, contrast, luminance, over, themeTokens, tokens } from './check-site-contrast.mjs';

const scratch = mkdtempSync(join(tmpdir(), 'gancho-contrast-'));
after(() => rmSync(scratch, { recursive: true, force: true }));

function fixture(tertiary = '#444444') {
  const light = `--surface-app: #ffffff; --surface-card: #ffffff;
    --surface-selection: rgba(0, 0, 0, 0.08); --text-primary: #000000;
    --text-secondary: #222222; --text-tertiary: ${tertiary};`;
  const dark = `--surface-app: #000000; --surface-card: #000000;
    --surface-selection: rgba(255, 255, 255, 0.08); --text-primary: #ffffff;
    --text-secondary: #dddddd; --text-tertiary: #bbbbbb;`;
  return {
    css: `:root { ${light} }
      @media (prefers-color-scheme: dark) { :root { ${dark} } }
      :root[data-theme="light"] { ${light} }
      :root[data-theme="dark"] { ${dark} }`,
    html: `.price-fine { color: var(--text-tertiary); }
.price-tier { color: var(--text-tertiary); }
.price-note { color: var(--text-secondary); }
.foot-note { color: var(--text-tertiary); }
.sa-note { color: var(--text-tertiary); }
.ph-search { color: var(--text-tertiary); background: var(--surface-selection); }
.ic-card .tier { color: var(--text-tertiary); background: var(--surface-selection); }
.price-card { background: var(--surface-card); }
.ic-card { background: var(--surface-card); }
.phone-scr { background: var(--surface-app); }
body { background: var(--surface-app); }`,
  };
}

function cli({ css, html }, args = [], symlink = false) {
  const root = mkdtempSync(join(scratch, 'site-'));
  mkdirSync(join(root, 'scripts')); mkdirSync(join(root, 'site'));
  const script = join(root, 'scripts/check-site-contrast.mjs');
  copyFileSync(new URL('./check-site-contrast.mjs', import.meta.url), script);
  if (css !== undefined) writeFileSync(join(root, 'site/styles.css'), css);
  writeFileSync(join(root, 'site/index.html'), html);
  const entry = symlink ? join(root, 'linked-checker.mjs') : script;
  if (symlink) symlinkSync(script, entry);
  return spawnSync(process.execPath, [entry, ...args], {
    cwd: scratch, encoding: 'utf8', timeout: 5_000, maxBuffer: 128 * 1024,
    env: { PATH: process.env.PATH, TMPDIR: scratch },
  });
}

test('reference contrast values and alpha compositing match the specified formula', () => {
  const black = [0, 0, 0, 1], white = [1, 1, 1, 1];

  assert.equal(contrast(black, white), 21);
  assert.equal(contrast(white, black), 21);
  assert.equal(contrast(black, black), 1);
  assert.ok(Math.abs(contrast([0, 0, 0, 0.5], white) - 3.976653) < 0.0000005);
  assert.deepEqual(over([0, 0, 0, 0.5], white), [0.5, 0.5, 0.5, 1]);
});

test('the sRGB breakpoint uses the linear branch at 0.04045', () => {
  assert.ok(Math.abs(luminance([0.04045, 0.04045, 0.04045]) - 0.0031308049535603713) < 1e-15);
});

test('all four themes retain base tokens and apply their own overlays', () => {
  const css = fixture().css.replace('--text-tertiary: #444444;', '--alias: var(--text-tertiary); --text-tertiary: #444444;');

  const themes = themeTokens(css);

  assert.deepEqual(Object.keys(themes), ['automatic-light', 'automatic-dark', 'explicit-light', 'explicit-dark']);
  assert.equal(themes['automatic-light']['--surface-app'], '#ffffff');
  assert.equal(themes['automatic-dark']['--surface-app'], '#000000');
  assert.equal(themes['explicit-light']['--surface-app'], '#ffffff');
  assert.equal(themes['explicit-dark']['--surface-app'], '#000000');
  assert.deepEqual(color(themes['automatic-dark']['--alias'], themes['automatic-dark']), [187 / 255, 187 / 255, 187 / 255, 1]);
});

test('duplicate tokens keep the last declaration, including recursive variables', () => {
  const palette = tokens('--a: #ffffff; --a: #000000; --b: var(--a); --c: var(--b);');

  assert.deepEqual(color('var(--c)', palette), [0, 0, 0, 1]);
});

test('the same seven selected and unselected pairs remain in scope', () => {
  assert.deepEqual(PAIRS.map(([selector, , , selected]) => [selector, selected]), [
    ['.price-fine', false], ['.price-tier', false], ['.price-note', false],
    ['.foot-note', false], ['.sa-note', false], ['.ph-search', true], ['.ic-card .tier', true],
  ]);
});

test('a valid fixture passes all four legacy checks', () => {
  const { css, html } = fixture();
  const run = checks(css, html);

  assert.doesNotThrow(run.test_formula_known_values);
  assert.doesNotThrow(run.test_pairs_still_describe_the_actual_small_text_styles);
  assert.doesNotThrow(run.test_primary_secondary_tertiary_hierarchy_is_preserved);
  assert.doesNotThrow(run.test_small_text_pairs_meet_four_point_five_without_rounding);
});

test('selected surfaces are composited before contrast is checked', () => {
  const { css, html } = fixture('#767676');

  assert.ok(contrast(color('#767676', {}), [1, 1, 1, 1]) > 4.5);
  assert.throws(() => checks(css, html).test_small_text_pairs_meet_four_point_five_without_rounding(), AggregateError);
});

test('a ratio immediately below 4.5 fails even when formatted as 4.500000', () => {
  const { css, html } = fixture('rgba(118.65635798027955, 118.65635798027955, 118.65635798027955, 1)');
  const transparentSelection = css.replaceAll('rgba(0, 0, 0, 0.08)', 'rgba(0, 0, 0, 0)');

  assert.throws(() => checks(transparentSelection, html).test_small_text_pairs_meet_four_point_five_without_rounding(), AggregateError);
});

test('a ratio immediately above 4.5 passes on unselected surfaces', () => {
  const { css, html } = fixture('rgba(118.65635598027955, 118.65635598027955, 118.65635598027955, 1)');
  const transparentSelection = css.replaceAll('rgba(0, 0, 0, 0.08)', 'rgba(0, 0, 0, 0)');

  assert.doesNotThrow(() => checks(transparentSelection, html).test_small_text_pairs_meet_four_point_five_without_rounding());
});

test('missing selectors, changed declarations, hierarchy and missing themes fail closed', () => {
  const { css, html } = fixture();

  assert.throws(() => checks(css, html.replace('.price-fine', '.missing')).test_pairs_still_describe_the_actual_small_text_styles(), AggregateError);
  assert.throws(() => checks(css, html.replace('color: var(--text-tertiary)', 'color: red')).test_pairs_still_describe_the_actual_small_text_styles(), AggregateError);
  assert.throws(() => checks(css.replaceAll('--text-secondary: #222222', '--text-secondary: #000000'), html).test_primary_secondary_tertiary_hierarchy_is_preserved(), AggregateError);
  assert.throws(() => themeTokens(css.replace('data-theme="dark"', 'data-theme="missing"')));
  assert.throws(() => color('hsl(0, 0%, 0%)', {}), /Unsupported color/);
  assert.throws(() => color('rgba(0x10, 0, 0, 1)', {}), /Invalid rgba/);
  assert.throws(() => over([0, 0, 0, 1], [1, 1, 1, 0.5]), /opaque backing/);
});

test('CLI success keeps stdout empty and reports four checks on stderr from any cwd', () => {
  const result = cli(fixture());

  assert.equal(result.status, 0);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /^\.\.\.\.\n-{70}\nRan 4 tests in \d+\.\d{3}s\n\nOK\n$/);
});

test('CLI contrast failure stays nonzero with diagnostics on stderr', () => {
  const result = cli(fixture('#aaaaaa'));

  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /FAIL: test_small_text_pairs_meet_four_point_five_without_rounding/);
  assert.match(result.stderr, /FAILED/);
});

test('CLI invoked through a symlink still runs its checks against the target site', () => {
  const result = cli(fixture(), [], true);

  assert.equal(result.status, 0);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /Ran 4 tests/);
});

test('missing CSS fails instead of reporting a successful empty run', () => {
  const result = cli({ html: fixture().html });

  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /ENOENT/);
});

test('CLI quiet and verbose modes retain output channels and invalid arguments exit 2', () => {
  const quiet = cli(fixture(), ['-q']);
  const verbose = cli(fixture(), ['-v']);
  const invalid = cli(fixture(), ['--unknown']);

  assert.equal(quiet.status, 0);
  assert.equal(quiet.stdout, '');
  assert.match(quiet.stderr, /^-{70}\nRan 4 tests/);
  assert.equal(verbose.status, 0);
  assert.equal(verbose.stdout, '');
  assert.match(verbose.stderr, /test_formula_known_values ... ok/);
  assert.equal(invalid.status, 2);
  assert.equal(invalid.stdout, '');
});
