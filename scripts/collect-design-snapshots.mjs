#!/usr/bin/env node
// Copy design-snapshot attachments out of an exported xcresult.
import { copyFileSync, existsSync, mkdirSync, readFileSync, statSync } from 'node:fs';
import { normalize, resolve } from 'node:path';

try {
  const [exported, output] = process.argv.slice(2);
  if (exported === undefined || output === undefined) {
    throw new Error('Usage: collect-design-snapshots.mjs <exported> <output>');
  }
  mkdirSync(resolve(output), { recursive: true });
  const manifest = JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: true })
    .decode(readFileSync(resolve(exported, 'manifest.json'))));
  const prefix = 'design-snapshot-';
  let count = 0;
  for (const test of manifest) {
    for (const item of test.attachments === undefined ? [] : test.attachments) {
      const name = item.suggestedHumanReadableName === undefined ? '' : item.suggestedHumanReadableName;
      if (!name.startsWith(prefix)) continue;
      // xcresulttool appends "_<index>_<uuid>.<ext>" to the attachment name.
      let stem = name.slice(prefix.length);
      for (let index = 0; index < 2 && stem.includes('_'); index += 1) {
        stem = stem.slice(0, stem.lastIndexOf('_'));
      }
      if (!/^[A-Za-z0-9-]+$/.test(stem)) {
        throw new Error(`refusing unsafe snapshot name: ${JSON.stringify(stem)}`);
      }
      const source = resolve(exported, item.exportedFileName), destination = resolve(output, `${stem}.png`);
      if (existsSync(destination)) {
        const original = statSync(source, { bigint: true }), target = statSync(destination, { bigint: true });
        if (original.dev === target.dev && original.ino === target.ino) {
          throw new Error('source and destination are the same file');
        }
      }
      copyFileSync(source, destination);
      count += 1;
    }
  }
  const displayOutput = normalize(output).replace(/\/+$/, '') || '/';
  console.log(`✓ collected ${count} design snapshot(s) into ${displayOutput}`);
  process.exitCode = count ? 0 : 1;
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
