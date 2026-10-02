import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const root = fileURLToPath(new URL('../', import.meta.url));
export const readJson = (filename) => JSON.parse(readFileSync(filename, 'utf8'));
const defaults = readJson(`${root}template-defaults.json`);
const descriptions = readJson(`${root}template-descriptions.json`);
const volumes = readJson(`${root}template-volumes.json`);
const networking = readJson(`${root}template-networking.json`);

export function servicesFromGraph(result) {
  assert.equal(result.ok, true, 'Graph compilation failed.');
  const services = result.graph.resources.filter((resource) => resource.type === 'service');
  assert.deepEqual(services.map((service) => service.name).sort(), ['MariaDB', 'Passbolt'], 'Unexpected graph services.');
  for (const service of services) {
    assert.deepEqual(Object.keys(service.variables).sort(), Object.keys(defaults[service.name]).sort(), 'Graph variable keys drifted.');
    for (const [key, variable] of Object.entries(service.variables)) {
      const config = variable.type === 'raw' ? variable.value : variable;
      const desired = config.generator ? '${{' + config.generator + '}}' : config.value;
      assert.equal(desired, defaults[service.name][key], `Graph/default mismatch at ${service.name}.${key}.`);
    }
    const mounts = Object.values(service.volumeAttachments ?? {});
    assert.equal(mounts.length, 1, 'Each service needs exactly one dedicated mount.');
    assert.equal(mounts[0].mountPath, volumes[service.name].mountPath);
  }
  const app = services.find((service) => service.name === 'Passbolt');
  assert.ok(app.source.repo && app.source.branch && app.source.rootDirectory, 'Explicit repo, release branch and root required.');
  assert.equal(app.source.image, undefined, 'GitHub source may not also have a seed image.');
  return services;
}

export function unwrapDraft(snapshot) {
  const draft = snapshot.data?.template ?? snapshot;
  assert.equal(draft.name, 'Passbolt team vault', 'Draft name mismatch.');
  assert.ok(['DRAFT', 'draft'].includes(draft.status), 'Offline tooling only accepts a DRAFT snapshot.');
  assert.ok(draft.serializedConfig && typeof draft.serializedConfig === 'object', 'serializedConfig must be parsed JSON.');
  assert.deepEqual(Object.keys(draft.serializedConfig), ['services'], 'Unsupported top-level schema; shared variables/extra resources are not copied.');
  const services = draft.serializedConfig.services;
  assert.ok(Array.isArray(services), 'Unsupported services schema.');
  assert.deepEqual(services.map((service) => service.name).sort(), ['MariaDB', 'Passbolt'], 'Draft service set mismatch.');
  assert.equal(new Set(services.map((service) => service.id)).size, 2, 'Unique existing service IDs required.');
  const volumeIds = [];
  for (const service of services) {
    assert.ok(typeof service.id === 'string' && service.id.length > 0, 'Missing existing service ID.');
    const mounts = Object.entries(service.volumeMounts ?? {});
    assert.equal(mounts.length, 1, 'Draft must already have one volume per service; IDs are never invented.');
    volumeIds.push(mounts[0][0]);
  }
  assert.equal(new Set(volumeIds).size, 2, 'Services may not share a volume.');
  return draft;
}

function desiredSource(service) {
  const { type, ...source } = service.source;
  assert.ok(type === 'github' || type === 'image', 'Unsupported source type.');
  return source;
}

export function restoreDraft(snapshot, graph) {
  const draft = structuredClone(unwrapDraft(snapshot));
  const desired = servicesFromGraph(graph);
  for (const service of draft.serializedConfig.services) {
    const specification = desired.find((candidate) => candidate.name === service.name);
    service.source = desiredSource(specification);
    service.deploy = { ...specification.deploy };
    delete service.build;
    if (specification.build) service.build = { ...specification.build };
    service.variables = Object.fromEntries(Object.entries(defaults[service.name]).map(([key, value]) => [key, {
      defaultValue: value,
      description: descriptions[service.name][key],
      isOptional: false,
    }]));
    service.networking = networking[service.name].publicPort ? {
      serviceDomains: { '<hasDomain>': { port: networking[service.name].publicPort } },
    } : {};
    const [volumeId] = Object.keys(service.volumeMounts);
    service.volumeMounts = { [volumeId]: { ...volumes[service.name] } };
  }
  auditDraft(draft, graph);
  return draft;
}

export function auditDraft(snapshot, graph) {
  const draft = unwrapDraft(snapshot);
  const desired = servicesFromGraph(graph);
  for (const service of draft.serializedConfig.services) {
    const specification = desired.find((candidate) => candidate.name === service.name);
    assert.deepEqual(service.source, desiredSource(specification), 'Source/branch/root/image drift.');
    assert.deepEqual(service.deploy, specification.deploy, 'Start/health/replica drift.');
    assert.deepEqual(service.build ?? null, specification.build ?? null, 'Build drift.');
    const expectedNetworking = networking[service.name].publicPort ? { serviceDomains: { '<hasDomain>': { port: networking[service.name].publicPort } } } : {};
    assert.deepEqual(service.networking, expectedNetworking, 'Unexpected public networking or TCP proxy.');
    assert.deepEqual(Object.values(service.volumeMounts), [volumes[service.name]], 'Volume drift.');
    assert.deepEqual(Object.keys(service.variables).sort(), Object.keys(defaults[service.name]).sort(), 'Variable-set drift.');
    for (const [key, value] of Object.entries(defaults[service.name])) {
      const variable = service.variables[key];
      assert.equal(variable.defaultValue, value, `Variable-expression drift at ${service.name}.${key}.`);
      assert.equal(variable.isOptional, false, 'Required variable became optional.');
      assert.equal(variable.description, descriptions[service.name][key], 'Description drift.');
      for (const forbidden of ['value', 'encryptedValue', 'generator']) {
        assert.equal(variable[forbidden], undefined, 'Snapshot has resolved secret values or competing generator fields.');
      }
    }
  }
  return true;
}
