# Deploy and Host Passbolt team vault on Railway

**Draft copy; unpublished and acceptance-gated.** Invite-only Passbolt CE sharing with private MariaDB and durable keys.

## About Hosting Passbolt team vault

Deploys one Community Edition web app and a private MariaDB, with durable database and server-key volumes. A one-time ownership initializer permanently drops to the upstream rootless application user. SMTP and canonical HTTPS are required; no public registration or default administrator exists. This single-instance recipe is not HA or a claim of certified production readiness.

## Why Deploy Passbolt team vault

Keeps server GPG/JWT identity together across restarts, checks salt/key continuity, references independently generated database secrets and leaves the database off public networking. Onboard users with a supported private Cake command, not a public bootstrap form.

## Common Use Cases

- Small-team password sharing after real browser/permission acceptance.
- Evaluating Passbolt CE with isolated private mail plumbing.
- Operating an invite-only vault with explicit recovery ownership.

## Dependencies for Passbolt team vault

[Passbolt CE](https://www.passbolt.com), [CE API source](https://github.com/passbolt/passbolt_api), [Passbolt Docker source](https://github.com/passbolt/passbolt_docker) and [MariaDB](https://mariadb.org). Browser onboarding requires the upstream client; commercial Pro capabilities are not included.

### Deployment Dependencies

Railway Pro or above for outbound SMTP, a genuine authenticated STARTTLS provider and verified sender, public HTTPS origin, two dedicated volumes, user recovery kits and encrypted coordinated SQL/server-key/secret backups. External delivery, two-user encrypted sharing, unrelated-user denial, real TLS and full user-resource restore must pass before production use. The local SMTP fixture is not included in the Railway graph.
