# Upgrades and rollback

Template 1.0.0 tracks deployment-contract SemVer independently from upstream Passbolt and MariaDB. Do not replace digest pins with `latest` or silently move the application to Pro. SDK/runtime, app image and DB image are updated independently with verified primary sources and corresponding-source/license evidence.

Before an update, quiesce writes/cron, back up SQL, complete app state and original secrets together, and record GPG/JWT identities and exact pins. Restore that generation into private disposable storage and prove clients can authenticate/decrypt existing resources. The local pending-user restore test is not that full recovery proof.

Read upstream release/migration compatibility notes and MariaDB upgrade constraints. Test the candidate image's non-root entrypoint, key symlinks/permissions, DB migration, closed signup, real mail/client sharing/denial, TLS and restart. Never share an app volume across concurrently running release versions or scale above one replica.

The upstream entrypoint migrates schema during boot. **Rolling back only the image may not roll back the schema.** Restore the pre-upgrade SQL and app state/secret generation into isolated volumes with the old pin, prove the recovery, then perform an authorized cutover. Key or salt changes are not a casual rollback method.

For publication, bump VERSION/CHANGELOG and move the actual `release-v1` only for compatible updates; a breaking env/state contract needs a new major source channel and migration notes. All source pushes, tags, deployments and publication require a separate authorized task.
