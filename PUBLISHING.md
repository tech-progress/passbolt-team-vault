# Publishing gate — not published

No template ID, deploy code, public distribution repository, source branch or published URL is assumed. `marketplace-metadata.json` is a directory-local staging record, not a replacement for the repository-wide registry. The source inputs are explicitly required; test fixtures are not real source repositories or template IDs.

This task permits **only local implementation and isolated Docker tests**. Do not run Railway deployment/creation/mutation commands, create a distribution repository, push tags, spend money or publish. Both draft tools are offline-only. Their output is candidate JSON, not a successful remote repair.

Before a separately authorized publication:

1. Complete `LICENSE_REVIEW.md`, provide corresponding source/notices for the derived pinned image and upstream dependencies, and resolve source/license discrepancies. Do not distribute private `FINDINGS.md`, local files or secrets to a public mirror.
2. Create/authorize the real source repository through a separate approved task. Use the same sanitized recipe, an actual `release-v1` branch and immutable `v1.0.0` tag; monorepo tag would be `passbolt-team-vault-v1.0.0`. This implementation creates none of them.
3. Set `TEMPLATE_SOURCE_REPO`, `TEMPLATE_SOURCE_BRANCH`, `TEMPLATE_SOURCE_ROOT_DIR`; compile and assert source root, secure generators and volumes. Restore/audit an exported local draft snapshot. No seed image may remain beside the GitHub source.
4. Complete all acceptance gates: real Railway fresh root-owned mount/non-root processes/private IPv6 DB, genuine authenticated email and invitation delivery, real edge TLS/header trust, at least two browser-enrolled users sharing/decrypting a resource, an unrelated third user's denial, restart stability, coordinated DB/keys/salt/user-resource restore, memory/workload soak and no sensitive log leakage.
5. A separately authorized operator must audit/deploy the stored draft into a disposable project, verify current replicas and metadata, then stop/remove only that project's resources. Historical SUCCESS alone is not enough. Record evidence, not assertions of completion.
6. Add the real ID/code and this metadata to root `railway-template-metadata.json`, preserving upstream origins in every GitHub-facing README. Run root `scripts/sync-template-marketplace.sh`, then require root `scripts/audit-template-marketplace.sh` to pass. They are **not run here** because they mutate/query publication state and root changes are out of scope.
7. Follow the repository playbook/versioning release sequence only when authorized; fill a local acceptance record with evidence references and require `scripts/verify.sh --release` to pass. Publishing and resource cleanup require independent confirmation.
