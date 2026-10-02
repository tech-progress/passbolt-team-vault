# License review — publication BLOCKED


## Owner-approved recipe license

On October 2, 2026, the code owner explicitly approved MIT for newly authored recipe, wrapper, application and test code. `LICENSE` records that narrow scope. Upstream components are not relicensed: all original notices, corresponding-source/network-use obligations, enterprise exceptions and artwork/trademark terms remain applicable. This approval resolves the authored-code license hold only; it does not close the artifact or behavioral publication gates.

Checked primary artifacts on 2026-10-02; this is an engineering inventory, **not legal advice or final compliance signoff**.

| Component | Primary evidence | Boundary |
| --- | --- | --- |
| Passbolt CE API v5.16.0 | Tagged `composer.json` declares `AGPL-3.0-or-later`; source headers and `LICENSE.txt` are AGPLv3. | Network-use/source obligations apply; preserve notices, provide corresponding source including modifications. |
| Passbolt rootless Docker | Pinned container label declares `AGPL-3.0-only`; Docker source LICENSE is AGPLv3, Debian package copyright lists AGPL-3 and numerous vendor licenses. | Label/source declaration differs: retain both, obtain review rather than collapsing it to a single claimed license. |
| Packaged API/config/dependencies | Container package `passbolt-ce-server 5.16.0-1`; version.php and upstream entrypoint hash-match primary source. Packaged default.php intentionally patches GnuPG keyring/putenv. | Matching selected files does not establish a complete reproducible corresponding-source archive or SBOM. This remains a gate. |
| MariaDB 11.4.10 official image | OCI labels GPL-2.0; main server source and image build repositories linked below. | GPL server plus distro/runtime notices; inventory licenses before redistribution. |
| Railway npm SDK 3.6.0 | Registry package declares MIT; exact transitive integrity lock in package-lock.json. | Maintainer-only tooling; preserve notices if distributed with node_modules. |
| Passbolt browser/mobile clients | Separate upstream distributions, not bundled by this recipe. | Browser onboarding is required; client versions, stores, notices and their exact licenses require separate verification. Do not imply CE image license covers every client or Pro feature. |

Primary records:

- https://github.com/passbolt/passbolt_api/blob/v5.16.0/composer.json
- https://github.com/passbolt/passbolt_api/blob/v5.16.0/LICENSE.txt
- https://github.com/passbolt/passbolt_docker/blob/fafe7789db612323bc56d6846cbce8c8939b6207/LICENSE
- https://github.com/passbolt/passbolt_docker/blob/fafe7789db612323bc56d6846cbce8c8939b6207/debian/Dockerfile.rootless
- Container `/usr/share/doc/passbolt-ce-server/copyright` and OCI license/source labels (see FINDINGS).
- https://github.com/MariaDB/server
- https://github.com/MariaDB/mariadb-docker
- https://registry.npmjs.org/railway/3.6.0
- https://github.com/railwayapp/railway-ts-sdk

Release blocker: review the CE-only source/config/image correspondence, supply corresponding source/notices for all redistributed pieces and wrapper changes, inventory bundled vendor/distro and separately used clients, and sign off on AGPL network obligations/trademark/icon use. No hosting/deployment success is a license-compliance result. No Pro feature, commercial support entitlement or recovery capability is promised.
