# Passbolt team vault

An **unpublished, production-boundary recipe**, not a production certification: one Passbolt Community Edition instance, one private MariaDB instance, external authenticated STARTTLS mail, and separate durable volumes. No Pro features, HA, public signup, public database proxy, shared service mount, host Docker socket, or automatic administrator bootstrap.

Main upstream origins: [Passbolt CE](https://www.passbolt.com), [CE API](https://github.com/passbolt/passbolt_api), [Passbolt Docker](https://github.com/passbolt/passbolt_docker), and [MariaDB](https://mariadb.org). Preserve all four links in any standalone distribution README.

## What is pinned

Template `1.0.0` is independent of Passbolt `5.16.0-1-ce-non-root` and MariaDB `11.4.10`. `Dockerfile` and `compose.yaml` use immutable multi-platform manifest digests. The small wrapper image installs no packages; it retains upstream nginx, PHP-FPM, migrations, cron and the rootless entrypoint. The offline Railway SDK is exactly `railway@3.6.0` with `package-lock.json`; Node 22+ and npm are maintainer-only prerequisites, not deployed application dependencies. See `FINDINGS.md` for image/source correspondence and `LICENSE_REVIEW.md` for unresolved redistribution obligations.

## Production prerequisites and boundary

- Railway **Pro or above**, with outbound SMTP enabled. After a plan upgrade, redeploy the mail-sending app. A different SMTP provider does not bypass lower-plan SMTP restrictions; this recipe has no HTTPS mail API adapter.
- A real provider account, verified sender, external STARTTLS host/port, username and password. Missing SMTP values reject startup **before state initialization**. Configuration validation cannot prove provider credentials, delivery or inbox placement; run the real-email gate.
- A canonical public HTTPS origin at the Railway edge, initially `https://${{Passbolt.RAILWAY_PUBLIC_DOMAIN}}`. Set `APP_FULL_BASE_URL` to a verified custom origin if needed. Do not expose container HTTP directly to the public internet.
- One replica per service, volume snapshots plus encrypted off-platform backups, recovery owners, user recovery kits and monitored mail queue. Start budgeting at 1 GiB app and 1 GiB DB memory; actual sizing/soak and Railway deployment are unqualified, not capacity promises.
- Real browser onboarding, two-user encrypted sharing, unrelated-user denial, TLS and recovery acceptance remain mandatory. HTTP status and pending SQL users do not establish those behaviors.

The application image declares `USER www-data` (UID/GID 33). Railway mounts can be root-owned, so the graph sets `RAILWAY_RUN_UID=0` for an **ownership-only initializer**. It rejects symlinked state paths, creates/chowns only the dedicated mount directories, and permanently drops UID/GID, capabilities and privilege escalation before any upstream app command. A UID-33 stdio bridge allows upstream logging after a root-created container pipe. nginx, PHP-FPM, supervisor, cron and GPG then run non-root. This is a rootless **application**, not a claim of a rootless container lifecycle. Compose tests an empty `nocopy` root-owned volume; actual Railway volume behavior is a separate unrun gate.

The nginx wrapper maps forwarded `https` to `HTTPS=on`, all other values to an **empty string**: the pinned Cake request factory treats non-empty `off` as truthy. `REQUEST_SCHEME` is mapped consistently. PHP always receives the validated canonical host, never a raw client Host value, preserving the pinned nginx package's absolute-request-target hardening. Only the exact Railway health-probe host/path gets an HTTPS probe exception. Production trusts Railway's edge header sanitization; raw inbound HTTP/header spoofing is not a supported deployment. The local header test is not real TLS verification.

## Local verification, without cloud access

```bash
cd passbolt-team-vault
npm ci --ignore-scripts --no-audit --no-fund
bash scripts/verify.sh
bash scripts/smoke.sh
```

Smoke creates a uniquely named project, generated disposable secrets and empty volumes. Only `127.0.0.1:18424` is published. The optional SMTP fixture is private-only on port 2525, with no host port, no Docker socket and no internet-facing mail/UI service. No port 18425 is needed. It tests initial root ownership, non-root app processes, DB/GPG/JWT readiness, closed signup, unauthenticated API denial, supported private pending-user registration, test mail to a private sink, restart identity, partial-key/salt/missing-SMTP guards, and coordinated SQL+key restoration into fresh volumes. It does **not** authenticate a browser, decrypt/share passwords or deliver genuine external mail.

Build/readiness/guard waits are bounded. INT/TERM exit through the EXIT trap, which verifies exact project image labels and bounds `down --rmi local` to 60 seconds (15-second hard-kill grace). It removes only that script's project containers, volumes, networks and generated app/SMTP image tags; shared upstream images remain. No global prune or process selection is used. Successful runs delete private artifacts. A failed run retains a mode-700 `.local/smoke.*` directory for diagnosis: it can contain secret registration links and plaintext backups; delete it securely after investigation. This directory is ignored and excluded from image context. Port conflicts abort without killing an existing service. An optional outer bound is `timeout --kill-after=90s 1400s bash scripts/smoke.sh`.

For manual local operation, copy `.env.example` to an ignored `.env`, replace every placeholder and use a dedicated project such as `docker compose -p passbolt-team-vault-local up --build -d`. Production mode requires external SMTP and an HTTPS edge. The loopback-only `local-test` mode is restricted to `http://127.0.0.1:18424` and is rejected whenever `RAILWAY_ENVIRONMENT_ID` is present; do not deploy test mode or the fixture to Railway.

## Variables and secrets

Required user inputs have **no usable defaults**. Generate random values using a password manager or `openssl rand`; never use SDK `ctx.randomString`, which is deterministic in this SDK version. Railway generator objects produce the DB passwords and salt; the app references the generated DB password instead of creating a second one.

| Variable | Scope and requirement |
| --- | --- |
| `MARIADB_DATABASE`, `MARIADB_USER` | DB; fixed `passbolt`, application-only database principal. |
| `MARIADB_PASSWORD` | DB; generated 32 characters; local at least 32. App references it. Back up. |
| `MARIADB_ROOT_PASSWORD` | DB only; independent generated 48 characters; local at least 32. Never app-visible. Back up. |
| `SECURITY_SALT` | App; generated 64 characters; keep stable and back up separately. Mismatch against persisted hash rejects restart. |
| `APP_FULL_BASE_URL` | App; required canonical HTTPS origin in production, no subpath, credentials or query. |
| `PASSBOLT_KEY_EMAIL` | App; required valid server GPG identity email. Keep stable. |
| `PASSBOLT_KEY_NAME` | App; default `Passbolt team vault`, GPG display identity. |
| `EMAIL_DEFAULT_FROM` | App; required real, verified sender. |
| `EMAIL_DEFAULT_FROM_NAME` | App; sender display name, default `Passbolt team vault`. |
| `EMAIL_TRANSPORT_DEFAULT_HOST` | App; required genuine external SMTP hostname. Local sinks rejected in production. |
| `EMAIL_TRANSPORT_DEFAULT_PORT` | App; STARTTLS provider port, default `587`; no implicit TLS 465 contract. |
| `EMAIL_TRANSPORT_DEFAULT_USERNAME` | App; required production SMTP authentication identity. |
| `EMAIL_TRANSPORT_DEFAULT_PASSWORD` | App; required production SMTP secret, never store a real value in draft JSON. |
| `EMAIL_TRANSPORT_DEFAULT_TLS` | App; fixed `true` production, fixture uses `false` locally. |
| `DATASOURCES_DEFAULT_HOST` | App; `${{MariaDB.RAILWAY_PRIVATE_DOMAIN}}`, local `db`. |
| `DATASOURCES_DEFAULT_PORT` | App; `3306`. |
| `DATASOURCES_DEFAULT_DATABASE` | App; `${{MariaDB.MARIADB_DATABASE}}`. |
| `DATASOURCES_DEFAULT_USERNAME` | App; `${{MariaDB.MARIADB_USER}}`. |
| `DATASOURCES_DEFAULT_PASSWORD` | App; `${{MariaDB.MARIADB_PASSWORD}}`, never the root credential. |
| `PORT` | App fixed `8080`; DB `3306`. Only app has a public Railway domain. |
| `RAILWAY_RUN_UID` | Railway app `0` only for the ownership bootstrap; Compose `user: 0:0` emulates it. |
| `RAILWAY_ENVIRONMENT_ID` | Platform-provided; prevents local-test mode on Railway. Never fake it. |
| `TEMPLATE_MODE` | Default `production`; `local-test` only in isolated loopback smoke. |
| `PASSBOLT_SSL_FORCE`, `PASSBOLT_SECURITY_COOKIE_SECURE` | Fixed `true` production; fixture alone uses `false`. |
| `PASSBOLT_SECURITY_FULLBASEURL_ENFORCE` | Fixed `true`; restricts origin/Host poisoning. |
| `PASSBOLT_SECURITY_PREVENT_EMAIL_ENUMERATION` | Fixed `true`; reduce username disclosure. |
| `PASSBOLT_PLUGINS_SELF_REGISTRATION_ENABLED` | Fixed `false`; current self-registration switch, not obsolete registration config. |
| `PASSBOLT_PLUGINS_SMTP_SETTINGS_ENABLED` | Fixed `false`; administrator UI cannot override environment mail configuration. |
| `PASSBOLT_PLUGINS_JWT_AUTHENTICATION_ENABLED` | Fixed `true`; persisted JWT key pair required. |
| `DEBUG` | Fixed `false`. |
| `TEMPLATE_SOURCE_REPO` | Maintainer graph input; **required** actual accessible `owner/repository`; no invented distribution repo. |
| `TEMPLATE_SOURCE_BRANCH` | Maintainer graph input; **required** actual slash-free `release-vN` compatibility branch. |
| `TEMPLATE_SOURCE_ROOT_DIR` | Maintainer graph input; **required** `/passbolt-team-vault` in this monorepo, or `/` in a sanitized standalone mirror. |

Internal derived variables `GNUPGHOME`, `PASSBOLT_GPG_SERVER_KEY_PRIVATE`, `PASSBOLT_GPG_SERVER_KEY_PUBLIC` and `PASSBOLT_GPG_SERVER_KEY_FINGERPRINT` are assigned by wrappers, not user secrets. `TEMPLATE_PREVIOUS_IDENTITY` is an internal restart check. `_FILE`, URL, fingerprint and arbitrary key-location overrides are unsupported. Changing env passwords does not rotate initialized MariaDB users: use a coordinated DB user-password change, then update app references.

## Private administrator onboarding

After DB, keys, SMTP and HTTPS are healthy, an authorized operator runs the **supported** command privately in the app container, as UID 33:

```bash
docker compose -p passbolt-team-vault-local exec --user 33:33 app \
  /opt/template/cake.sh passbolt register_user \
  -u admin@example.com -f First -l Last -r admin
```

On Railway, open a private service shell and invoke `/opt/template/cake.sh passbolt register_user ...`; this wrapper drops privileges if the shell is root. Do not add this to the start command or publish its output. Register colleagues with `-r user`. The printed setup URL is a bearer secret: deliver through an authenticated private channel, never logs/issues/chat history. CLI creation produces a **pending account**, not a completed browser identity. Complete setup using the upstream browser extension, retain the user's private recovery kit and passphrase privately, and verify real mail. Use `/opt/template/cake.sh passbolt send_test_email --recipient=...` privately to diagnose delivery; it can print provider diagnostics.

## Durable state, backup and recovery

- App volume `/var/lib/passbolt` contains `keys/gpg/serverkey.asc`, `keys/gpg/serverkey_private.asc`, `keys/jwt/jwt.key`, `keys/jwt/jwt.pem`, `.gnupg`, `security-salt.sha256`, and `keys.ready` (public fingerprint plus aggregate identity). `/etc/passbolt/gpg` and `/etc/passbolt/jwt` are image-owned symlinks to this **one** mount. `tmp` caches are disposable. Server keys are not user recovery kits.
- Upstream bootstrap temporarily makes its UID-33-owned JWT directory writable for creation. A checked, pinned-source patch changes the upstream final directory permission from `0750` to `0550` **before supervisor/listeners start**, matching the upstream JWT health contract; readiness independently rejects a writable directory. UID 33 still owns that directory and can change its mode: this is not an immutable/read-only secret mount or protection against a fully compromised app UID. Files stay `0640`, and wrapper checks reject identity drift.
- DB volume `/var/lib/mysql` contains the actual encrypted resource records, permissions, users, pending email and migrations. No app filesystem is shared with MariaDB.
- Quiesce app writes and cron by stopping the app, take a transaction-consistent `mariadb-dump --single-transaction --routines --events --triggers`, and archive the app's `keys`, `.gnupg`, salt hash and identity marker. Export original `SECURITY_SALT`, DB credentials, source/image pins and canonical origin to a **separate encrypted secret backup**. Hashes in the volume do not recover the salt.
- Encrypt SQL and key archives offline, store off-platform with least privilege, verify integrity and set retention. A DB snapshot alone is not recovery. Never tar an actively changing database datadir.
- Restore into a **private isolated** empty DB and app volume, preserving file UID/GID 33 and original salt. Restore SQL and the complete app archive from the same quiesced generation before starting Passbolt. Compare GPG fingerprint/JWT identity, run `cake.sh passbolt healthcheck --gpg --jwt --database --posix`, then real-client authentication/sharing/denial and mail/TLS acceptance before DNS cutover.
- Missing one half of either pair, missing keys with existing users, changed salt, or changed persisted identity fail closed. Do not delete markers, auto-generate replacements or overwrite user/server keys to make a broken restore boot. Contact the recovery owner.

The automated local smoke restores pending-user SQL and server state into fresh volumes. **Recovery of browser-encrypted resources with user recovery kits remains unrun**, and is a production-release blocker.

## Offline Railway draft preparation

Set all three `TEMPLATE_SOURCE_*` inputs to an actual authorized source; run `npm run graph` and save its JSON under `.local/`. The graph configures a Dockerfile app, pinned private MariaDB, two independent volumes, one public app port, generated secrets and references. It performs no deployment by itself.

`node scripts/restore-template-draft.mjs LOCAL_DRAFT_JSON LOCAL_GRAPH_JSON .local/candidate.json` rewrites a **local DRAFT snapshot only**, preserves existing IDs, strips resolved secrets/seed images/public DB networking and refuses unknown topology or missing/shared volume IDs. `node scripts/audit-template.mjs .local/candidate.json LOCAL_GRAPH_JSON` compares generator expressions, exact source/branch/root, build/start/health settings, variables, volumes and ports without printing secrets. These tools do not read credentials, call an API, invent IDs or submit mutations.

`bash scripts/verify.sh --release` intentionally fails until human acceptance evidence exists. See `PUBLISHING.md`, `MARKETPLACE.md`, `SUPPORT.md` and `UPGRADE.md`. This task does not authorize cloud resources, source publication, tags or marketplace publication.
