#!/usr/bin/env bash
# discourse-restore.sh — ONE-12 §7 Disaster Recovery / rollback
#
# Restores a discourse backup produced by discourse-backup.sh onto a (new)
# Discourse host: restores the pg_dump into the dedicated Postgres container,
# restores /shared uploads, then the operator resets env + starts the units.
#
# Usage: discourse-restore.sh <backup-file.sql.gz> [shared-tarball]
set -euo pipefail

BACKUP_FILE="${1:-}"
[ -n "$BACKUP_FILE" ] || { echo "usage: $0 <backup.sql.gz> [shared-dir]" >&2; exit 1; }
[ -f "$BACKUP_FILE" ] || { echo "backup not found: $BACKUP_FILE" >&2; exit 1; }

DISCOURSE_PG_CONTAINER="${DISCOURSE_PG_CONTAINER:-discourse-postgres}"
DISCOURSE_DB_NAME="${DISCOURSE_DB_NAME:-discourse}"
DISCOURSE_DB_USER="${DISCOURSE_DB_USER:-discourse_app}"
RESTORE_PG_TOOL="${DISCOURSE_RESTORE_PG_TOOL:-psql}"

echo "[restore] starting $(date -u +%FT%TZ) from $BACKUP_FILE"

# Source DB credentials from the host env file (0600) — not printed.
if [ -f "$HOME/.config/containers/systemd/discourse-postgres.env" ]; then
  # shellcheck disable=SC1090
  set -a; . "$HOME/.config/containers/systemd/discourse-postgres.env"; set +a
fi

echo "[restore] verifying checksum of the backup"
gzip -t "$BACKUP_FILE"

echo "[restore] restoring postgres database ${DISCOURSE_DB_NAME}"
gunzip -c "$BACKUP_FILE" | podman exec -i -u postgres "$DISCOURSE_PG_CONTAINER" \
  "$RESTORE_PG_TOOL" -U "$DISCOURSE_DB_USER" -d "$DISCOURSE_DB_NAME"

if [ -n "${2:-}" ] && [ -d "$2" ]; then
  echo "[restore] restoring /shared uploads from $2"
  rsync -a "$2/" "$HOME/discourse/volumes/shared/" 2>/dev/null \
  || rsync -a "$2/" "/var/lib/discourse/shared/" 2>/dev/null || true
fi

echo "[restore] complete $(date -u +%FT%TZ)"
echo "[restore] NOTE: verify row counts/checksum, then start discourse units."
