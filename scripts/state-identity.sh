#!/usr/bin/env bash
set -euo pipefail
state=/var/lib/passbolt
for key in "$state/keys/gpg/serverkey_private.asc" "$state/keys/gpg/serverkey.asc" "$state/keys/jwt/jwt.key" "$state/keys/jwt/jwt.pem"; do test -s "$key"; done
gpg --batch --show-keys --with-colons "$state/keys/gpg/serverkey.asc" 2>/dev/null | awk -F: '$1=="fpr" { print $10; exit }'
sha256sum "$state/keys/gpg/serverkey_private.asc" "$state/keys/gpg/serverkey.asc" "$state/keys/jwt/jwt.key" "$state/keys/jwt/jwt.pem" "$state/security-salt.sha256" | sha256sum | cut -d' ' -f1
