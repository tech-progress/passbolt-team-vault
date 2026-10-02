#!/usr/bin/env bash
set -euo pipefail
umask 077
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
for command in docker curl jq openssl timeout ss; do command -v "$command" >/dev/null || { echo "Missing $command; smoke BLOCKED." >&2; exit 1; }; done
[[ -z "$(ss -H -ltn 'sport = :18424')" ]] || { echo 'Loopback port 18424 is occupied; smoke BLOCKED; no process killed.' >&2; exit 1; }
project="passbolt-smoke-$(id -u)-$(openssl rand -hex 5)"
mkdir -p .local
temporary="$(mktemp -d "$root/.local/smoke.XXXXXXXX")"
export MARIADB_PASSWORD="$(openssl rand -hex 24)"
export MARIADB_ROOT_PASSWORD="$(openssl rand -hex 32)"
export SECURITY_SALT="$(openssl rand -hex 32)"
export TEMPLATE_MODE=local-test APP_FULL_BASE_URL=http://127.0.0.1:18424
export PASSBOLT_KEY_EMAIL=server@example.test EMAIL_DEFAULT_FROM=vault@example.test
export EMAIL_TRANSPORT_DEFAULT_HOST=smtp EMAIL_TRANSPORT_DEFAULT_PORT=2525
export EMAIL_TRANSPORT_DEFAULT_USERNAME='' EMAIL_TRANSPORT_DEFAULT_PASSWORD=''
export EMAIL_TRANSPORT_DEFAULT_TLS=false PASSBOLT_SSL_FORCE=false PASSBOLT_SECURITY_COOKIE_SECURE=false
compose() { docker compose --project-directory "$root" -p "$project" -f compose.yaml -f compose.smoke.yaml "$@"; }
cleanup() {
  result=$?
  trap - EXIT
  trap '' INT TERM
  image_cleanup=(--rmi local)
  for service in app smtp; do
    image="$project-$service:latest"
    if image_owner="$(docker image inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$image" 2>/dev/null)"; then
      if [[ "$image_owner" != "$project" ]]; then
        image_cleanup=()
        result=1
        echo 'Image ownership mismatch; image removal refused.' >&2
      fi
    fi
  done
  if ! timeout --kill-after=15s 60s docker compose --project-directory "$root" -p "$project" -f compose.yaml -f compose.smoke.yaml down --volumes --remove-orphans "${image_cleanup[@]}" --timeout 10 >"$temporary/cleanup.log" 2>&1; then result=1; fi
  if [[ -n "$(docker ps -aq --filter "label=com.docker.compose.project=$project")" || -n "$(docker volume ls -q --filter "label=com.docker.compose.project=$project")" || -n "$(docker network ls -q --filter "label=com.docker.compose.project=$project")" ]]; then result=1; fi
  for service in app smtp; do
    if docker image inspect "$project-$service:latest" >/dev/null 2>&1; then result=1; fi
  done
  if [[ "$result" == 0 ]]; then
    echo 'PASS: local plumbing, private onboarding, SMTP sink, restart, fail-closed state, SQL+keys restore; own resources removed.'
    rm -rf -- "$temporary"
  else
    echo "FAIL/BLOCKED: local smoke incomplete; private diagnostic directory: $temporary (may contain sensitive onboarding/backup data)." >&2
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
wait_app() {
  for attempt in {1..150}; do
    container="$(compose ps -q app)"
    if [[ -n "$container" && "$(docker inspect -f '{{.State.Health.Status}}' "$container")" == healthy ]]; then return; fi
    if [[ -n "$container" && "$(docker inspect -f '{{.State.Status}}' "$container")" == exited ]]; then break; fi
    sleep 2
  done
  compose logs --no-color app db >"$temporary/readiness.log" 2>&1
  echo 'Application readiness failed; see private diagnostic directory.' >&2
  return 1
}
users_count() { compose exec -T db bash -ec 'MYSQL_PWD="$MARIADB_PASSWORD" mariadb -u "$MARIADB_USER" "$MARIADB_DATABASE" -N -e "SELECT COUNT(*) FROM users"'; }
expect_failure() {
  local name="$1"
  shift
  if timeout 45 docker compose --project-directory "$root" -p "$project" -f compose.yaml -f compose.smoke.yaml run --rm --no-deps app "$@" >"$temporary/$name.log" 2>&1; then
    echo "Fail-closed $name test unexpectedly succeeded." >&2
    return 1
  else
    local status=$?
    [[ "$status" == 1 ]] || { echo "Fail-closed $name test BLOCKED by command/infrastructure failure ($status)." >&2; return 1; }
  fi
}
timeout 600 docker compose --project-directory "$root" -p "$project" -f compose.yaml -f compose.smoke.yaml build >"$temporary/build.log" 2>&1
[[ "$(compose run --rm --no-deps --entrypoint stat app -c %u /var/lib/passbolt 2>/dev/null)" == 0 ]]
compose up -d >"$temporary/start.log" 2>&1
wait_app
[[ "$(compose exec -T app stat -c %u /proc/1)" == 33 ]]
compose exec -T app bash -ec 'ps -eo uid,comm | awk '\''$2 ~ /^(nginx|php-fpm|supervisord|supercronic)/ {seen++; if ($1 != 33) exit 1} END {if (!seen) exit 1}'\''' 
compose exec -T --user 33:33 app /opt/template/cake.sh passbolt healthcheck --gpg --jwt --database --posix >"$temporary/healthcheck.log" 2>&1
identity="$(compose exec -T --user 33:33 app /opt/template/state-identity.sh)"
curl -fsS --max-time 10 http://127.0.0.1:18424/healthcheck/status.json | jq -e '.header.status=="success"' >/dev/null
registration_code="$(curl -sS --max-time 10 -o "$temporary/register.json" -w '%{http_code}' http://127.0.0.1:18424/auth/register.json)"
[[ "$registration_code" == 404 || "$registration_code" == 403 ]]
for endpoint in users resources; do
  code="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "http://127.0.0.1:18424/$endpoint.json")"
  [[ "$code" == 401 || "$code" == 403 ]]
done
compose exec -T --user 33:33 app /opt/template/cake.sh passbolt register_user -u admin@example.test -f Local -l Admin -r admin >"$temporary/admin-link.txt" 2>&1
compose exec -T --user 33:33 app /opt/template/cake.sh passbolt register_user -u colleague@example.test -f Local -l Colleague -r user >"$temporary/user-link.txt" 2>&1
[[ "$(users_count)" == 2 ]]
grep -q '/setup/start/' "$temporary/admin-link.txt"
compose exec -T --user 33:33 app /opt/template/cake.sh passbolt send_test_email --recipient=admin@example.test >"$temporary/test-email.log" 2>&1
compose exec -T smtp php -r '$found=false; foreach(glob("/spool/*.json") as $file) {$mail=json_decode(file_get_contents($file),true); if (str_contains($mail["recipient"],"admin@example.test") && str_contains($mail["message"],"Subject:")) $found=true;} exit($found?0:1);'
export PASSBOLT_SSL_FORCE=true
compose up -d --force-recreate app >"$temporary/forwarding-start.log" 2>&1
wait_app
for proto in http malformed; do
  code="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' -H "X-Forwarded-Proto: $proto" http://127.0.0.1:18424/auth/login)"
  printf 'proto=%s status=%s\n' "$proto" "$code" >>"$temporary/forwarding-results.log"
  [[ "$code" == 302 ]]
done
[[ "$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' http://127.0.0.1:18424/auth/login)" == 302 ]]
curl -fsS --max-time 10 -D "$temporary/forwarded-https.headers" -H 'X-Forwarded-Proto: https' http://127.0.0.1:18424/auth/login >"$temporary/forwarded-https.html"
grep -qi '^strict-transport-security:' "$temporary/forwarded-https.headers"
curl -fsS --max-time 10 -H 'Host: healthcheck.railway.app' http://127.0.0.1:18424/healthcheck/status.json | jq -e '.header.status=="success"' >/dev/null
export PASSBOLT_SSL_FORCE=false
compose up -d --force-recreate app >"$temporary/recreate.log" 2>&1
wait_app
[[ "$(compose exec -T --user 33:33 app /opt/template/state-identity.sh)" == "$identity" && "$(users_count)" == 2 ]]
compose stop app >/dev/null
compose run --rm --no-deps --entrypoint mv app /var/lib/passbolt/keys/jwt/jwt.pem /var/lib/passbolt/keys/jwt/jwt.pem.saved >/dev/null 2>&1
expect_failure partial-key
grep -q 'Incomplete key state:' "$temporary/partial-key.log"
compose run --rm --no-deps --entrypoint test app ! -e /var/lib/passbolt/keys/jwt/jwt.pem >/dev/null 2>&1
compose run --rm --no-deps --entrypoint mv app /var/lib/passbolt/keys/jwt/jwt.pem.saved /var/lib/passbolt/keys/jwt/jwt.pem >/dev/null 2>&1
compose run --rm --no-deps --entrypoint mv app /var/lib/passbolt/keys/gpg/serverkey.asc /var/lib/passbolt/keys/gpg/serverkey.asc.saved >/dev/null 2>&1
expect_failure partial-gpg-key
grep -q 'Incomplete key state:' "$temporary/partial-gpg-key.log"
compose run --rm --no-deps --entrypoint test app ! -e /var/lib/passbolt/keys/gpg/serverkey.asc >/dev/null 2>&1
compose run --rm --no-deps --entrypoint mv app /var/lib/passbolt/keys/gpg/serverkey.asc.saved /var/lib/passbolt/keys/gpg/serverkey.asc >/dev/null 2>&1
old_salt="$SECURITY_SALT"
export SECURITY_SALT="$(openssl rand -hex 32)"
expect_failure changed-salt
grep -q 'SECURITY_SALT changed:' "$temporary/changed-salt.log"
export SECURITY_SALT="$old_salt"
export TEMPLATE_MODE=production APP_FULL_BASE_URL=https://vault.example.com
expect_failure missing-production-smtp
grep -q 'Production requires real EMAIL_TRANSPORT_DEFAULT_USERNAME' "$temporary/missing-production-smtp.log"
export TEMPLATE_MODE=local-test APP_FULL_BASE_URL=http://127.0.0.1:18424
compose exec -T db bash -ec 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb-dump -u root --single-transaction --routines --events --triggers "$MARIADB_DATABASE"' >"$temporary/database.sql"
compose run --rm --no-deps --entrypoint tar app -cf - -C /var/lib/passbolt keys .gnupg security-salt.sha256 keys.ready >"$temporary/app-state.tar" 2>"$temporary/archive.log"
compose down --volumes --remove-orphans --timeout 10 >/dev/null
compose up -d db smtp >"$temporary/restore-start.log" 2>&1
for attempt in {1..90}; do
  database="$(compose ps -q db)"
  if [[ "$(docker inspect -f '{{.State.Health.Status}}' "$database")" == healthy ]]; then break; fi
  [[ "$attempt" != 90 ]] || exit 1
  sleep 2
done
compose exec -T db bash -ec 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -u root "$MARIADB_DATABASE"' <"$temporary/database.sql"
compose run --rm --no-deps -T --entrypoint tar app -xf - -C /var/lib/passbolt <"$temporary/app-state.tar" 2>"$temporary/restore-keys.log"
compose up -d app >"$temporary/restored-app.log" 2>&1
wait_app
[[ "$(users_count)" == 2 && "$(compose exec -T --user 33:33 app /opt/template/state-identity.sh)" == "$identity" ]]
compose exec -T --user 33:33 app /opt/template/cake.sh passbolt healthcheck --gpg --jwt --database --posix >"$temporary/restored-healthcheck.log" 2>&1
echo 'NOT RUN: real external mail, browser two-user encrypted sharing/unrelated-user denial, real TLS, Railway fresh-volume deployment, license publication review.'
