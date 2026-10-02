import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import test from 'node:test';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { auditDraft, readJson, restoreDraft, root, servicesFromGraph } from './offline-template.mjs';

const graph = JSON.parse(execFileSync(`${root}node_modules/.bin/railway-iac-ts`, ['.railway/railway.ts'], {
  cwd: root,
  env: { ...process.env, TEMPLATE_SOURCE_REPO: 'fixture/passbolt-template', TEMPLATE_SOURCE_BRANCH: 'release-v1', TEMPLATE_SOURCE_ROOT_DIR: '/passbolt-team-vault' },
  encoding: 'utf8',
}));
const snapshot = {
  name: 'Passbolt team vault', status: 'DRAFT',
  serializedConfig: { services: [
    { name: 'Passbolt', id: 'existing-app', volumeMounts: { 'existing-app-volume': {} }, source: { image: 'seed' } },
    { name: 'MariaDB', id: 'existing-db', volumeMounts: { 'existing-db-volume': {} }, networking: { tcpProxies: { public: {} } } },
  ] },
};

test('SDK generators survive compilation and match template expressions', () => {
  servicesFromGraph(graph);
  const secrets = graph.graph.resources.filter((resource) => resource.type === 'service').flatMap((service) => Object.entries(service.variables).filter(([, variable]) => variable.value?.generator).map(([key, variable]) => [key, variable.value.generator]));
  assert.equal(secrets.length, 3);
  assert.ok(secrets.every(([, generator]) => /^secret\((32|48|64), "/.test(generator)));
  assert.equal(graph.graph.resources.find((resource) => resource.name === 'Passbolt').source.rootDirectory, '/passbolt-team-vault');
});
test('restoration is offline, strips seed source and real secrets, and preserves IDs', () => {
  snapshot.serializedConfig.services[0].variables = { EMAIL_TRANSPORT_DEFAULT_PASSWORD: { value: 'never-copy-this' } };
  const restored = restoreDraft(snapshot, graph);
  assert.equal(auditDraft(restored, graph), true);
  assert.equal(restored.serializedConfig.services[0].id, 'existing-app');
  assert.equal(JSON.stringify(restored).includes('never-copy-this'), false);
  assert.equal(restored.serializedConfig.services[0].source.image, undefined);
});
for (const mutation of ['source', 'generator', 'network', 'shared-volume', 'mount', 'optional', 'replicas', 'healthcheck']) {
  test(`audit rejects ${mutation} drift`, () => {
    const restored = restoreDraft(snapshot, graph);
    const [app, database] = restored.serializedConfig.services;
    if (mutation === 'source') app.source.branch = 'main';
    if (mutation === 'generator') database.variables.MARIADB_PASSWORD.defaultValue = 'deterministic-password';
    if (mutation === 'network') database.networking.tcpProxies = { public: {} };
    if (mutation === 'shared-volume') database.volumeMounts = { 'existing-app-volume': readJson(`${root}template-volumes.json`).MariaDB };
    if (mutation === 'mount') app.volumeMounts['existing-app-volume'].mountPath = '/etc/passbolt';
    if (mutation === 'optional') app.variables.EMAIL_TRANSPORT_DEFAULT_HOST.isOptional = true;
    if (mutation === 'replicas') app.deploy.numReplicas = 2;
    if (mutation === 'healthcheck') app.deploy.healthcheckPath = '/';
    assert.throws(() => auditDraft(restored, graph));
  });
}
test('published snapshots and missing volume IDs fail closed', () => {
  assert.throws(() => restoreDraft({ ...snapshot, status: 'PUBLISHED' }, graph));
  const missing = structuredClone(snapshot);
  missing.serializedConfig.services[0].volumeMounts = {};
  assert.throws(() => restoreDraft(missing, graph));
});
test('graph requires real source input and slash-free release channel', () => {
  for (const source of [{ TEMPLATE_SOURCE_REPO: '' }, { TEMPLATE_SOURCE_BRANCH: 'release/v1' }, { TEMPLATE_SOURCE_ROOT_DIR: '' }]) {
    assert.throws(() => execFileSync(`${root}node_modules/.bin/railway-iac-ts`, ['.railway/railway.ts'], {
      cwd: root, stdio: 'pipe', env: { ...process.env, TEMPLATE_SOURCE_REPO: 'fixture/passbolt-template', TEMPLATE_SOURCE_BRANCH: 'release-v1', TEMPLATE_SOURCE_ROOT_DIR: '/', ...source },
    }));
  }
});
test('audit and restoration CLI errors never print resolved-secret canaries', () => {
  mkdirSync(join(root, '.local'), { recursive: true, mode: 0o700 });
  const temporary = mkdtempSync(join(root, '.local/canary.'));
  const canary = 'CANARY_NEVER_PRINT_RESOLVED_SECRET_9fe0f67';
  try {
    const restored = restoreDraft(snapshot, graph);
    restored.serializedConfig.services[0].variables.SECURITY_SALT.defaultValue = canary;
    writeFileSync(join(temporary, 'snapshot.json'), JSON.stringify(restored));
    writeFileSync(join(temporary, 'graph.json'), JSON.stringify(graph));
    const invalid = structuredClone(restored);
    invalid.serializedConfig.services[0].name = canary;
    writeFileSync(join(temporary, 'invalid.json'), JSON.stringify(invalid));
    for (const [script, input, output] of [
      ['audit-template.mjs', 'snapshot.json', []],
      ['restore-template-draft.mjs', 'invalid.json', [join(temporary, 'output.json')]],
    ]) {
      let rejected = false;
      try {
        execFileSync(process.execPath, [join(root, 'scripts', script), join(temporary, input), join(temporary, 'graph.json'), ...output], { encoding: 'utf8', stdio: 'pipe' });
      } catch (error) {
        rejected = true;
        assert.equal(error.status, 1);
        assert.equal(`${error.stdout}${error.stderr}`.includes(canary), false);
      }
      assert.equal(rejected, true);
    }
  } finally {
    rmSync(temporary, { recursive: true });
  }
});
