# Support boundary

This unpublished recipe targets an invite-only, single-instance CE deployment with a private DB and external mail. It does not supply Passbolt Pro, enterprise recovery, HA, a compliance attestation, guaranteed email delivery or data recovery without intact server and user secrets. Use upstream Passbolt documentation/community for product/client behavior and Railway support for platform networking/volumes/billing.

If startup is rejected, check the **variable name** in the diagnostic, not by printing the entire environment. Validate SMTP on Pro+, canonical origin and generated secret references. Check that UID 33 owns the dedicated state mount after initialization and that all four GPG/JWT files and the original salt survive. Do not disable guards, run the app as root or expose the DB to fix readiness.

On lost/partial keys or salt mismatch, stop traffic and preserve both volumes before recovery. Registration links, SQL dumps, GPG/JWT private keys, recovery kits and provider diagnostics are secrets; redact them from support tickets. Never paste raw exported Railway variables/drafts. Failed smoke artifacts are private and must be deleted after diagnosis.

Supported variables/state/layout are in `README.md`; upgrade and restore gates are in `UPGRADE.md`. Production acceptance and publication remain blocked until the unrun gates are completed by an authorized human.
