#!/usr/bin/env bash
set -euo pipefail
if [[ "$(id -u)" == 0 ]]; then
  exec setpriv --reuid=33 --regid=33 --init-groups --bounding-set=-all --no-new-privs /opt/template/healthcheck.sh
fi
[[ "$(id -u)" == 33 ]] || exit 1
state=/var/lib/passbolt
[[ ! -w "$state/keys/jwt" ]]
identity="$(/opt/template/state-identity.sh)"
if [[ -n "${TEMPLATE_PREVIOUS_IDENTITY:-}" && "$identity" != "$TEMPLATE_PREVIOUS_IDENTITY" ]]; then exit 1; fi
for key in "$state/keys/gpg/serverkey_private.asc" "$state/keys/jwt/jwt.key"; do
  [[ "$(stat -c %u "$key")" == 33 ]]
  [[ "$(stat -c %a "$key")" == 600 || "$(stat -c %a "$key")" == 640 ]]
done
php -r '$db=new PDO("mysql:host=".getenv("DATASOURCES_DEFAULT_HOST").";port=".(getenv("DATASOURCES_DEFAULT_PORT")?:3306).";dbname=".getenv("DATASOURCES_DEFAULT_DATABASE"),getenv("DATASOURCES_DEFAULT_USERNAME"),getenv("DATASOURCES_DEFAULT_PASSWORD")); $db->query("SELECT COUNT(*) FROM users")->fetchColumn();'
proto="$(php -r 'echo parse_url(getenv("APP_FULL_BASE_URL"),PHP_URL_SCHEME);')"
if [[ "$PASSBOLT_SSL_FORCE" == true ]]; then proto=https; fi
curl --fail --silent --show-error --max-time 5 -H "Host: $(php -r '$url=parse_url(getenv("APP_FULL_BASE_URL")); echo $url["host"].(isset($url["port"])?":".$url["port"]:"");')" -H "X-Forwarded-Proto: $proto" http://127.0.0.1:8080/healthcheck/status.json | php -r '$response=json_decode(stream_get_contents(STDIN),true); exit(($response["header"]["status"]??null)==="success" ? 0 : 1);'
if [[ -f "$state/keys.ready" ]]; then
  [[ "$(cat "$state/keys.ready")" == "$identity" ]]
else
  printf '%s\n' "$identity" >"$state/keys.ready"
fi
