#!/usr/bin/env bash
# discourse-healthcheck.sh — ONE-12 §6 step 2 (Container/DB health)
#
# Rootless, safe-to-run smoke check: asserts the five systemd-user units are
# active, the dedicated Postgres answers pg_isready, Redis PINGs with the
# host-env password, and the web container answers its /srv/healthcheck.
# Exits non-zero on any failure. Never touches other services.
set -uo pipefail

DISCORD_UNITS=(discourse-pod discourse-web discourse-sidekiq discourse-postgres discourse-redis)
DISCOURSE_PG_CONTAINER="${DISCOURSE_PG_CONTAINER:-discourse-postgres}"
DISCOURSE_REDIS_CONTAINER="${DISCOURSE_REDIS_CONTAINER:-discourse-redis}"
DISCOURSE_WEB_CONTAINER="${DISCOURSE_WEB_CONTAINER:-discourse-web}"
DISCOURSE_DB_NAME="${DISCOURSE_DB_NAME:-discourse}"
DISCOURSE_DB_USER="${DISCOURSE_DB_USER:-discourse_app}"

fails=0

echo "== unit activity =="
for u in "${DISCORD_UNITS[@]}"; do
  st="$(systemctl --user is-active "$u.service" 2>/dev/null || echo inactive)"
  echo "  $u: $st"
  [ "$st" = "active" ] || fails=$((fails+1))
done

echo "== postgres =="
if podman container exists "$DISCOURSE_PG_CONTAINER" 2>/dev/null; then
  if podman exec "$DISCOURSE_PG_CONTAINER" pg_isready -U "$DISCOURSE_DB_USER" -d "$DISCOURSE_DB_NAME" >/dev/null 2>&1; then
    echo "  pg_isready: OK"
  else
    echo "  pg_isready: FAIL" >&2; fails=$((fails+1))
  fi
else
  echo "  postgres container missing" >&2; fails=$((fails+1))
fi

echo "== redis =="
if podman container exists "$DISCOURSE_REDIS_CONTAINER" 2>/dev/null; then
  # Password from host env file (0600).
  rpw=""
  # shellcheck disable=SC1090
  [ -f "$HOME/.config/containers/systemd/discourse-redis.env" ] && . "$HOME/.config/containers/systemd/discourse-redis.env"
  if podman exec "$DISCOURSE_REDIS_CONTAINER" redis-cli -a "$rpw" PING 2>/dev/null | grep -q PONG; then
    echo "  redis PING: OK"
  else
    echo "  redis PING: FAIL" >&2; fails=$((fails+1))
  fi
else
  echo "  redis container missing" >&2; fails=$((fails+1))
fi

echo "== web =="
if podman container exists "$DISCOURSE_WEB_CONTAINER" 2>/dev/null; then
  if podman exec "$DISCOURSE_WEB_CONTAINER" curl -fsS http://127.0.0.1:80/srv/healthcheck >/dev/null 2>&1; then
    echo "  web /srv/healthcheck: OK"
  else
    echo "  web /srv/healthcheck: FAIL" >&2; fails=$((fails+1))
  fi
else
  echo "  web container missing" >&2; fails=$((fails+1))
fi

if [ "$fails" -eq 0 ]; then
  echo "== ALL DISCOURSE HEALTH CHECKS PASSED =="
  exit 0
fi
echo "== $fails DISCOURSE HEALTH CHECK(S) FAILED ==" >&2
exit 1
