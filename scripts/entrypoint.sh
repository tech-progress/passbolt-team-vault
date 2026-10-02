#!/usr/bin/env bash
set -euo pipefail
umask 077
php /opt/template/validate-runtime.php
state=/var/lib/passbolt
mountpoint -q "$state" || { echo 'Mount the dedicated app volume at /var/lib/passbolt.' >&2; exit 1; }
if [[ "$(id -u)" == 0 ]]; then
  for directory in "$state" "$state/keys" "$state/keys/gpg" "$state/keys/jwt" "$state/.gnupg" "$state/tmp"; do
    [[ ! -L "$directory" ]] || { echo 'Symlink in state initialization path rejected.' >&2; exit 1; }
    mkdir -p "$directory"
    chown 33:33 "$directory"
    chmod 700 "$directory"
  done
  exec setpriv --reuid=33 --regid=33 --init-groups --bounding-set=-all --no-new-privs bash -c 'exec > >(cat); exec 2> >(cat >&2); exec /opt/template/entrypoint.sh'
fi
[[ "$(id -u)" == 33 ]] || { echo 'Passbolt must run as UID 33.' >&2; exit 1; }
[[ -w "$state/keys/gpg" && -w "$state/keys/jwt" && -w "$state/.gnupg" ]] || { echo 'App volume must be writable by UID/GID 33; use documented ownership bootstrap.' >&2; exit 1; }
[[ "$(readlink /etc/passbolt/gpg)" == "$state/keys/gpg" && "$(readlink /etc/passbolt/jwt)" == "$state/keys/jwt" ]] || exit 1
export GNUPGHOME="$state/.gnupg"
export PASSBOLT_GPG_SERVER_KEY_PRIVATE="$state/keys/gpg/serverkey_private.asc"
export PASSBOLT_GPG_SERVER_KEY_PUBLIC="$state/keys/gpg/serverkey.asc"
unset PASSBOLT_GPG_SERVER_KEY_FINGERPRINT
canonical_host="$(php -r '$url=parse_url(getenv("APP_FULL_BASE_URL")); echo $url["host"].(isset($url["port"])?":".$url["port"]:"");')"
cat >/etc/nginx/conf.d/template-origin.conf <<NGINX
map_hash_bucket_size 128;
map \$host \$template_host {
  default "$canonical_host";
}
map \$http_x_forwarded_proto \$template_forwarded_https {
  default "";
  https on;
}
map \$http_host:\$request_uri \$template_https {
  default \$template_forwarded_https;
  "healthcheck.railway.app:/healthcheck/status.json" on;
}
map \$template_https \$template_scheme {
  default http;
  on https;
}
NGINX
nginx -t
[[ ! -L "$state/security-salt.sha256" && ! -L "$state/keys.ready" ]] || exit 1
salt_hash="$(printf '%s' "$SECURITY_SALT" | sha256sum | cut -d' ' -f1)"
if [[ -f "$state/security-salt.sha256" ]]; then
  [[ "$(cat "$state/security-salt.sha256")" == "$salt_hash" ]] || { echo 'SECURITY_SALT changed: restore the original secret; refusing startup.' >&2; exit 1; }
else
  printf '%s\n' "$salt_hash" >"$state/security-salt.sha256"
fi
key_count=0
for key in "$state/keys/gpg/serverkey_private.asc" "$state/keys/gpg/serverkey.asc" "$state/keys/jwt/jwt.key" "$state/keys/jwt/jwt.pem"; do
  [[ ! -L "$key" ]] || { echo 'Symlinked key files rejected.' >&2; exit 1; }
  if [[ -s "$key" ]]; then key_count=$((key_count + 1)); fi
done
if [[ "$key_count" != 0 && "$key_count" != 4 ]] || [[ -f "$state/keys.ready" && "$key_count" != 4 ]]; then
  echo 'Incomplete key state: restore coordinated DB and app backup; never regenerate one missing key.' >&2
  exit 1
fi
if [[ -f "$state/keys.ready" ]]; then
  [[ "$(cat "$state/keys.ready")" == "$(/opt/template/state-identity.sh)" ]] || { echo 'Persisted key identity changed; restore the original coordinated backup.' >&2; exit 1; }
fi
timeout 180 /usr/bin/wait-for.sh "${DATASOURCES_DEFAULT_HOST}:${DATASOURCES_DEFAULT_PORT:-3306}" -- true
for attempt in {1..60}; do
  if php -r 'new PDO("mysql:host=".getenv("DATASOURCES_DEFAULT_HOST").";port=".(getenv("DATASOURCES_DEFAULT_PORT")?:3306).";dbname=".getenv("DATASOURCES_DEFAULT_DATABASE"),getenv("DATASOURCES_DEFAULT_USERNAME"),getenv("DATASOURCES_DEFAULT_PASSWORD"));' >/dev/null 2>&1; then break; fi
  [[ "$attempt" != 60 ]] || { echo 'Database authentication readiness timed out.' >&2; exit 1; }
  sleep 2
done
if [[ "$key_count" == 0 ]]; then
  existing_users="$(php -r '$db=new PDO("mysql:host=".getenv("DATASOURCES_DEFAULT_HOST").";port=".(getenv("DATASOURCES_DEFAULT_PORT")?:3306).";dbname=".getenv("DATASOURCES_DEFAULT_DATABASE"),getenv("DATASOURCES_DEFAULT_USERNAME"),getenv("DATASOURCES_DEFAULT_PASSWORD")); $exists=$db->query("SHOW TABLES LIKE '\''users'\''")->fetchColumn(); echo $exists ? $db->query("SELECT COUNT(*) FROM users")->fetchColumn() : 0;')"
  [[ "$existing_users" == 0 ]] || { echo 'Database contains users but keys are absent. Restore keys; refusing regeneration.' >&2; exit 1; }
fi
export TEMPLATE_PREVIOUS_IDENTITY="$(/opt/template/state-identity.sh 2>/dev/null || true)"
exec /docker-entrypoint.sh
