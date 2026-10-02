import { auditDraft, readJson } from './offline-template.mjs';

try {
  const [draftFile, graphFile] = process.argv.slice(2);
  if (!draftFile || !graphFile || process.argv.length !== 4) throw new Error('Usage: node scripts/audit-template.mjs LOCAL_DRAFT_JSON LOCAL_GRAPH_JSON');
  auditDraft(readJson(draftFile), readJson(graphFile));
  console.log('OFFLINE draft audit passed: source, secret expressions, private DB, ports and separate volumes. No network calls.');
} catch {
  console.error('OFFLINE audit failed: invalid input, unsupported schema or configuration drift. No secret values printed.');
  process.exitCode = 1;
}
