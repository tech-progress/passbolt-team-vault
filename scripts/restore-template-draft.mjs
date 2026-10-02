import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { readJson, restoreDraft, root } from './offline-template.mjs';

try {
  const [draftFile, graphFile, outputFile] = process.argv.slice(2);
  if (!draftFile || !graphFile || !outputFile || process.argv.length !== 5) throw new Error('Explicit local inputs/output required.');
  const output = resolve(outputFile);
  if (!output.startsWith(resolve(root, '.local') + '/')) throw new Error('Output must be inside this template .local directory.');
  const restored = restoreDraft(readJson(draftFile), readJson(graphFile));
  mkdirSync(dirname(output), { recursive: true, mode: 0o700 });
  writeFileSync(output, JSON.stringify(restored, null, 2) + '\n', { mode: 0o600, flag: 'wx' });
  console.log('OFFLINE candidate written; existing IDs retained. Nothing submitted to Railway.');
} catch {
  console.error('OFFLINE restoration failed: invalid input, IDs/schema, graph or output path. No secret values printed.');
  process.exitCode = 1;
}
