#!/usr/bin/env bash
set -euo pipefail
if [[ "$(id -u)" == 0 ]]; then
  exec setpriv --reuid=33 --regid=33 --init-groups --bounding-set=-all --no-new-privs /opt/template/cake.sh "$@"
fi
[[ "$(id -u)" == 33 ]] || exit 1
export GNUPGHOME=/var/lib/passbolt/.gnupg
export PASSBOLT_GPG_SERVER_KEY_PRIVATE=/var/lib/passbolt/keys/gpg/serverkey_private.asc
export PASSBOLT_GPG_SERVER_KEY_PUBLIC=/var/lib/passbolt/keys/gpg/serverkey.asc
export PASSBOLT_GPG_SERVER_KEY_FINGERPRINT="$(gpg --batch --show-keys --with-colons "$PASSBOLT_GPG_SERVER_KEY_PUBLIC" 2>/dev/null | awk -F: '$1=="fpr" {print $10; exit}')"
[[ -n "$PASSBOLT_GPG_SERVER_KEY_FINGERPRINT" ]] || exit 1
cd /usr/share/php/passbolt
exec bin/cake "$@"
