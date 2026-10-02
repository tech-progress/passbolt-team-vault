import { defineRailway, group, project, service, volume } from "railway/iac";

function requiredSource(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required; no distribution repository is assumed.`);
  return value;
}

const repository = requiredSource("TEMPLATE_SOURCE_REPO");
const branch = requiredSource("TEMPLATE_SOURCE_BRANCH");
const rootDirectory = requiredSource("TEMPLATE_SOURCE_ROOT_DIR");
if (!/^[\w.-]+\/[\w.-]+$/.test(repository)) throw new Error("Source must be owner/repository.");
if (!/^release-v[1-9][0-9]*$/.test(branch)) throw new Error("Source branch must be a release-vN channel.");
if (!rootDirectory.startsWith("/") || rootDirectory.includes("..")) throw new Error("Source root must be an absolute repository path, or / for a standalone mirror.");

const alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const secret = (length: number) => ({ generator: `secret(${length}, "${alphabet}")`, isOptional: false });
const required = (description: string) => ({ value: "", isOptional: false, description });

export default defineRailway(() => {
  const databaseData = volume("MariaDB data", { sizeMB: 5_000 });
  const appState = volume("Passbolt keys", { sizeMB: 1_000 });
  const database = service("MariaDB", {
    source: { image: "mariadb:11.4.10@sha256:3b4dfcc32247eb07adbebec0793afae2a8eafa6860ec523ee56af4d3dec42f7f" },
    start: "docker-entrypoint.sh mariadbd --bind-address=0.0.0.0,::",
    volumeMounts: { "/var/lib/mysql": databaseData },
    deploy: { numReplicas: 1 },
    env: {
      PORT: "3306",
      MARIADB_DATABASE: "passbolt",
      MARIADB_USER: "passbolt",
      MARIADB_PASSWORD: secret(32),
      MARIADB_ROOT_PASSWORD: secret(48),
    },
  });
  const app = service("Passbolt", {
    source: { repo: repository, branch },
    rootDirectory,
    build: { builder: "DOCKERFILE", dockerfilePath: "Dockerfile" },
    start: "/opt/template/entrypoint.sh",
    healthcheck: "/healthcheck/status.json",
    healthcheckTimeout: 300,
    networking: { serviceDomains: { "<hasDomain>": { port: 8080 } } },
    deploy: { numReplicas: 1 },
    volumeMounts: { "/var/lib/passbolt": appState },
    env: {
      PORT: "8080",
      RAILWAY_RUN_UID: "0",
      TEMPLATE_MODE: "production",
      APP_FULL_BASE_URL: "https://${{Passbolt.RAILWAY_PUBLIC_DOMAIN}}",
      DATASOURCES_DEFAULT_HOST: "${{MariaDB.RAILWAY_PRIVATE_DOMAIN}}",
      DATASOURCES_DEFAULT_PORT: "3306",
      DATASOURCES_DEFAULT_DATABASE: "${{MariaDB.MARIADB_DATABASE}}",
      DATASOURCES_DEFAULT_USERNAME: "${{MariaDB.MARIADB_USER}}",
      DATASOURCES_DEFAULT_PASSWORD: "${{MariaDB.MARIADB_PASSWORD}}",
      SECURITY_SALT: secret(64),
      PASSBOLT_KEY_EMAIL: required("Required server GPG identity email; keep stable after initial boot."),
      PASSBOLT_KEY_NAME: "Passbolt team vault",
      EMAIL_DEFAULT_FROM: required("Required verified SMTP sender address."),
      EMAIL_DEFAULT_FROM_NAME: "Passbolt team vault",
      EMAIL_TRANSPORT_DEFAULT_HOST: required("Required external SMTP provider; Railway Pro or above."),
      EMAIL_TRANSPORT_DEFAULT_PORT: "587",
      EMAIL_TRANSPORT_DEFAULT_USERNAME: required("Required SMTP account username."),
      EMAIL_TRANSPORT_DEFAULT_PASSWORD: required("Required SMTP account password; configure privately."),
      EMAIL_TRANSPORT_DEFAULT_TLS: "true",
      PASSBOLT_SSL_FORCE: "true",
      PASSBOLT_SECURITY_COOKIE_SECURE: "true",
      PASSBOLT_SECURITY_FULLBASEURL_ENFORCE: "true",
      PASSBOLT_SECURITY_PREVENT_EMAIL_ENUMERATION: "true",
      PASSBOLT_PLUGINS_SELF_REGISTRATION_ENABLED: "false",
      PASSBOLT_PLUGINS_SMTP_SETTINGS_ENABLED: "false",
      PASSBOLT_PLUGINS_JWT_AUTHENTICATION_ENABLED: "true",
      DEBUG: "false",
    },
  });
  return project("Passbolt team vault", {
    resources: [group("Vault", [app, appState]), group("Private database", [database, databaseData])],
  });
});
