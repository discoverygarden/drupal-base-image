#!/usr/bin/env bash
# Smoke test: the Drupal base image has the expected PHP version and extensions,
# a valid Apache config, and Apache serves requests.
# Usage: test/smoke.sh <image>
set -euo pipefail
IMAGE="${1:?usage: $0 <image>}"
NAME="drupal-base-smoke-$$"
trap 'rc=$?; [ $rc -ne 0 ] && docker logs "$NAME" >&2 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; exit $rc' EXIT

docker run -d --name "$NAME" "$IMAGE" >/dev/null

php_version="$(docker exec "$NAME" sh -c 'echo $PHP_VERSION')"
docker exec "$NAME" php -v | head -1
docker exec "$NAME" php -r "exit(PHP_VERSION_ID >= 80400 ? 0 : 1);" || { echo "FAIL: PHP older than 8.4" >&2; exit 1; }
echo "ok: PHP ${php_version}"

mods="$(docker exec "$NAME" php -m)"
for ext in apcu bcmath ctype curl fileinfo gd iconv intl mbstring memcached pdo pdo_pgsql pgsql SimpleXML soap tokenizer xml zip; do
  echo "$mods" | grep -qix "$ext" || { echo "FAIL: PHP extension missing: $ext" >&2; exit 1; }
done
echo "ok: required PHP extensions present"

docker exec "$NAME" apachectl -t 2>&1 | grep -q 'Syntax OK' || { echo "FAIL: apache config invalid" >&2; exit 1; }
echo "ok: apache config valid"

echo "waiting for Apache..."
for _ in $(seq 1 30); do
  code="$(docker exec "$NAME" curl -s -o /dev/null -w '%{http_code}' http://localhost/ 2>/dev/null || true)"
  case "$code" in 000|"") sleep 1 ;; *) up=1; break ;; esac
done
[ "${up:-0}" = "1" ] || { echo "FAIL: Apache never answered" >&2; exit 1; }
echo "ok: Apache answering (HTTP $code; no Drupal codebase in the base image)"

docker exec "$NAME" sh -c 'command -v clear-cache' >/dev/null || { echo "FAIL: clear-cache missing" >&2; exit 1; }
echo "smoke test passed"
