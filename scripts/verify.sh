#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
[[ "${1:-}" == '' || "${1:-}" == --release ]] || { echo 'Usage: bash scripts/verify.sh [--release]' >&2; exit 1; }
for command in node npm docker jq; do command -v "$command" >/dev/null || { echo "Missing verifier dependency: $command" >&2; exit 1; }; done
required=(Dockerfile .env.example .dockerignore .gitignore .railway/railway.ts compose.yaml compose.smoke.yaml package.json package-lock.json VERSION CHANGELOG.md README.md FINDINGS.md MARKETPLACE.md PUBLISHING.md SUPPORT.md UPGRADE.md LICENSE_REVIEW.md marketplace-metadata.json template-defaults.json template-descriptions.json template-networking.json template-volumes.json acceptance-gates.example.json scripts/smoke.sh scripts/entrypoint.sh scripts/healthcheck.sh scripts/state-identity.sh scripts/cake.sh scripts/validate-runtime.php scripts/smtp-fixture.php scripts/restore-template-draft.mjs scripts/audit-template.mjs)
for file in "${required[@]}"; do test -f "$file" || { echo "Missing required artifact: $file" >&2; exit 1; }; done
for file in scripts/*.sh; do bash -n "$file"; done
for file in scripts/*.mjs; do node --check "$file"; done
node --input-type=module <<'NODE'
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = (file) => readFileSync(file, 'utf8');
const json = (file) => JSON.parse(read(file));
assert.equal(read('VERSION').trim(), '1.0.1');
assert.equal(json('package.json').version, read('VERSION').trim());
assert.equal(json('package.json').devDependencies.railway, '3.6.0');
assert.equal(json('package-lock.json').packages['node_modules/railway'].version, '3.6.0');
assert.ok(json('package-lock.json').packages['node_modules/railway'].integrity.startsWith('sha512-'));
assert.ok(read('CHANGELOG.md').includes('1.0.1 — 2026-10-02'));
const metadata = json('marketplace-metadata.json');
assert.ok(metadata.description.length >= 45 && metadata.description.length <= 75);
assert.equal(metadata.directory, 'passbolt-team-vault');
for (const forbidden of ['id','code','distributionRepo']) assert.equal(metadata[forbidden], undefined);
assert.ok(metadata.icon.includes('passbolt_api/v5.16.0/webroot/favicon'));
for (const origin of metadata.origins) assert.ok(read('README.md').includes(origin.url));
const defaults = json('template-defaults.json');
const descriptions = json('template-descriptions.json');
for (const [service, variables] of Object.entries(defaults)) {
  assert.deepEqual(Object.keys(variables).sort(), Object.keys(descriptions[service]).sort());
  for (const key of Object.keys(variables)) assert.ok(read('README.md').includes('`'+key+'`'), `Undocumented variable ${key}`);
}
assert.ok(!read('.railway/railway.ts').includes('ctx.randomString'));
for (const file of ['Dockerfile','compose.yaml','.railway/railway.ts']) assert.ok(!read(file).includes('/var/run/docker.sock'));
assert.ok(read('Dockerfile').includes('sha256:1f6aba5b18199809de9aaec17ba1525b88ac75be9390c5fc343b88a9b18f525d'));
for (const file of ['compose.yaml','.railway/railway.ts']) assert.ok(read(file).includes('sha256:3b4dfcc32247eb07adbebec0793afae2a8eafa6860ec523ee56af4d3dec42f7f'));
for (const heading of ['# Deploy and Host','## About Hosting','## Why Deploy','## Common Use Cases','## Dependencies for','### Deployment Dependencies']) assert.ok(read('MARKETPLACE.md').includes(heading));
console.log('Artifact, pin, metadata, lock and variable-documentation checks passed.');
NODE
MARIADB_PASSWORD=verify012345678901234567890123456789 MARIADB_ROOT_PASSWORD=verify012345678901234567890123456789 SECURITY_SALT=verify01234567890123456789012345678901234567890123456789012345678901234 APP_FULL_BASE_URL=https://vault.example.com PASSBOLT_KEY_EMAIL=server@example.com EMAIL_DEFAULT_FROM=vault@example.com EMAIL_TRANSPORT_DEFAULT_HOST=smtp.example.com docker compose -f compose.yaml -f compose.smoke.yaml config --quiet
node --test scripts/offline-template.test.mjs
if [[ "${1:-}" == --release ]]; then
  node --input-type=module <<'NODE'
import { readFileSync } from 'node:fs';
try {
  const expected = JSON.parse(readFileSync('acceptance-gates.example.json', 'utf8'));
  const evidence = JSON.parse(readFileSync('.local/acceptance-gates.json', 'utf8'));
  for (const key of Object.keys(expected)) {
    if (evidence[key]?.passed !== true || !evidence[key]?.evidence?.trim()) throw new Error();
  }
  console.log('Recorded human release evidence present; independently review references before publication.');
} catch {
  console.error('RELEASE BLOCKED: missing/failed human acceptance evidence. No cloud or publication mutation performed.');
  process.exitCode = 1;
}
NODE
fi
echo 'Local structural verification passed. Smoke and human production/publication gates are separate.'
