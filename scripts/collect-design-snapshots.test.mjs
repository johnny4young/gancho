import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, linkSync, mkdtempSync, mkdirSync, readFileSync, readdirSync,
  rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const script = fileURLToPath(new URL('./collect-design-snapshots.mjs', import.meta.url));
const bytes = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x00, 0xff, 0x0a]);

function fixture(t, manifest) {
  const root = mkdtempSync(join(tmpdir(), 'gancho-snapshot-collector-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const exported = join(root, 'exported'), output = join(root, 'output');
  mkdirSync(exported);
  writeFileSync(join(exported, 'manifest.json'), JSON.stringify(manifest));
  return { root, exported, output };
}

function run(exported, output, options = {}) {
  return spawnSync(process.execPath, [script, exported, output], {
    encoding: 'utf8', timeout: 5000, ...options,
  });
}

const attachment = (name, file = 'image.png') => ({
  suggestedHumanReadableName: name, exportedFileName: file,
});

test('copies only named snapshots, removes the two xcresult suffixes and preserves bytes', (t) => {
  const { exported, output } = fixture(t, [
    {}, { attachments: [{}, attachment('other-attachment'),
      attachment('design-snapshot-Library-Dark_4_abc.png')] },
    { attachments: [attachment('design-snapshot-panel_0_def.png', 'second.png')] },
  ]);
  writeFileSync(join(exported, 'image.png'), bytes);
  writeFileSync(join(exported, 'second.png'), Buffer.from('second synthetic image'));
  const result = run(exported, output);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  assert.equal(result.stdout, `✓ collected 2 design snapshot(s) into ${output}\n`);
  assert.deepEqual(readdirSync(output).sort(), ['Library-Dark.png', 'panel.png']);
  assert.deepEqual(readFileSync(join(output, 'Library-Dark.png')), bytes);
  assert.equal(readFileSync(join(output, 'panel.png'), 'utf8'), 'second synthetic image');
});

test('accepts names with no suffix or only one suffix, and overwrites duplicate stems in order', (t) => {
  const { exported, output } = fixture(t, [{ attachments: [
    attachment('design-snapshot-panel'), attachment('design-snapshot-panel_0', 'new.png'),
  ] }]);
  writeFileSync(join(exported, 'image.png'), bytes);
  writeFileSync(join(exported, 'new.png'), 'latest');
  const result = run(exported, output);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /collected 2 design snapshot\(s\)/);
  assert.deepEqual(readdirSync(output), ['panel.png']);
  assert.equal(readFileSync(join(output, 'panel.png'), 'utf8'), 'latest');
});

test('empty or irrelevant manifests create the output directory and exit 1 with a zero count', (t) => {
  for (const manifest of [[], [{}], [{ attachments: [attachment('unrelated')] }]]) {
    const { exported, output } = fixture(t, manifest);
    const result = run(exported, output);
    assert.equal(result.status, 1);
    assert.equal(result.stderr, '');
    assert.equal(result.stdout, `✓ collected 0 design snapshot(s) into ${output}\n`);
    assert.deepEqual(readdirSync(output), []);
  }
});

test('unsafe and empty stems fail before copying any file', (t) => {
  for (const stem of ['', '../outside', 'has space', 'under_score', 'é', 'line\n']) {
    const { exported, output } = fixture(t, [{ attachments: [
      attachment(`design-snapshot-${stem}_0_uuid.png`),
    ] }]);
    writeFileSync(join(exported, 'image.png'), bytes);
    const result = run(exported, output);
    assert.equal(result.status, 1, JSON.stringify(stem));
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^refusing unsafe snapshot name: /);
    assert.deepEqual(readdirSync(output), []);
  }
});

test('supports relative input/output paths independently of the script directory', (t) => {
  const { root, exported, output } = fixture(t, [{ attachments: [
    attachment('design-snapshot-panel_0_uuid.png'),
  ] }]);
  writeFileSync(join(exported, 'image.png'), bytes);
  const result = run('./exported', './output/', { cwd: root });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, '✓ collected 1 design snapshot(s) into output\n');
  assert.deepEqual(readFileSync(join(output, 'panel.png')), bytes);
});

test('missing/invalid manifests and missing source files exit 1 without a success summary', (t) => {
  for (const mode of ['missing-manifest', 'invalid-json', 'invalid-utf8', 'json-bom', 'missing-source']) {
    const { exported, output } = fixture(t, [{ attachments: [
      attachment('design-snapshot-panel_0_uuid.png'),
    ] }]);
    const manifest = join(exported, 'manifest.json');
    if (mode === 'missing-manifest') rmSync(manifest);
    if (mode === 'invalid-json') writeFileSync(manifest, '{');
    if (mode === 'invalid-utf8') writeFileSync(manifest, Buffer.from([0xff]));
    if (mode === 'json-bom') writeFileSync(manifest, '\uFEFF[]');
    const result = run(exported, output);
    assert.equal(result.status, 1, mode);
    assert.equal(result.stdout, '', mode);
    assert.notEqual(result.stderr, '', mode);
    assert.equal(existsSync(join(output, 'panel.png')), false);
  }
});

test('missing arguments exit 1, and extra arguments remain ignored', (t) => {
  const absent = spawnSync(process.execPath, [script], { encoding: 'utf8', timeout: 5000 });
  assert.equal(absent.status, 1);
  assert.equal(absent.stdout, '');
  assert.match(absent.stderr, /^Usage: /);
  const { exported, output } = fixture(t, []);
  const extra = spawnSync(process.execPath, [script, exported, output, 'ignored'], {
    encoding: 'utf8', timeout: 5000,
  });
  assert.equal(extra.status, 1);
  assert.equal(extra.stderr, '');
  assert.match(extra.stdout, /collected 0 design snapshot\(s\)/);
});

test('malformed attachment fields are errors rather than silently ignored null values', (t) => {
  for (const malformed of [{ attachments: null }, { attachments: {} },
    { attachments: [null] }, { attachments: [{ suggestedHumanReadableName: null }] }]) {
    const { exported, output } = fixture(t, [{ attachments: [
      attachment('design-snapshot-panel_0_uuid.png'),
    ] }, malformed]);
    writeFileSync(join(exported, 'image.png'), bytes);
    const result = run(exported, output);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.notEqual(result.stderr, '');
    // Like the original sequential copier, earlier copies remain after an error.
    assert.deepEqual(readFileSync(join(output, 'panel.png')), bytes);
  }
});

test('an empty output argument denotes the current directory', (t) => {
  const { root, exported } = fixture(t, [{ attachments: [
    attachment('design-snapshot-panel_0_uuid.png'),
  ] }]);
  writeFileSync(join(exported, 'image.png'), bytes);
  const result = run(exported, '', { cwd: root });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, '✓ collected 1 design snapshot(s) into .\n');
  assert.deepEqual(readFileSync(join(root, 'panel.png')), bytes);
});

test('copying onto the same file fails, including hard-link and symbolic-link aliases', (t) => {
  for (const kind of ['same-path', 'hard-link', 'symbolic-link']) {
    const { exported, output } = fixture(t, [{ attachments: [
      attachment('design-snapshot-panel_0_uuid.png', 'panel.png'),
    ] }]);
    const source = join(exported, 'panel.png');
    writeFileSync(source, bytes);
    if (kind !== 'same-path') {
      mkdirSync(output);
      if (kind === 'hard-link') linkSync(source, join(output, 'panel.png'));
      if (kind === 'symbolic-link') symlinkSync(source, join(output, 'panel.png'));
    }
    const result = run(exported, kind === 'same-path' ? exported : output);
    assert.equal(result.status, 1, kind);
    assert.equal(result.stdout, '');
    assert.notEqual(result.stderr, '');
    assert.deepEqual(readFileSync(source), bytes);
  }
});

test('the collector remains directly executable through its Node shebang', (t) => {
  const { exported, output } = fixture(t, []);
  const result = spawnSync(script, [exported, output], { encoding: 'utf8', timeout: 5000 });
  assert.equal(result.status, 1, result.error?.message);
  assert.equal(result.stderr, '');
  assert.equal(result.stdout, `✓ collected 0 design snapshot(s) into ${output}\n`);
});
