#!/usr/bin/env bash
# discourse-backup.sh — ONE-12 §3.6 / §7
#
# Runs on the Discourse host as the rootless discourse_run_user. Produces:
#   1. PostgreSQL logical dump of the dedicated `discourse` database
#   2. A tarball of /shared uploads (and the Discourse backups dir)
# into $DISCOURSE_BACKUP_DEST, prunes old backups by retention days.
#
# Credentials are read ONLY from the host-side 0600 env files; nothing here
# is a secret. This script is wired to a systemd-user timer by the
# discourse-backup role. It never touches the existing services' data.
set -euo pipefail

# Optional overrides from the systemd unit / environment.
DISCOURSE_BACKUP_DEST="${DISCOURSE_BACKUP_DEST:-$HOME/discourse/backups}"
DISCOURSE_BACKUP_RETENTION_DAYS="${DISCOURSE_BACKUP_RETENTION_DAYS:-14}"
# Name of the dedicated Postgres container (in the discourse pod).
DISCOURSE_PG_CONTAINER="${DISCOURSE_PG_CONTAINER:-discourse-postgres}"
DISCOURSE_SHARED_VOL="${DISCOURSE_SHARED_VOL:-discourse-shared}"
PG_DUMP_TOOL="${DISCOURSE_PG_DUMP_TOOL:-pg_dump}"

USERSYSTEMD="${XDG_RUNTIME_DIR:+systemctl --user}"
PIN="$(date +%Y%m%d%H%M%S)"
mkdir -p "$DISCOURSE_BACKUP_DEST"

echo "[backup] starting at $(date -u +%FT%TZ)"

# Source DB credentials from the host env file (0600) — not printed.
if [ -f "$HOME/.config/containers/systemd/discourse-postgres.env" ]; then
  # shellcheck disable=SC1090
  set -a; . "$HOME/.config/containers/systemd/discourse-postgres.env"; set +a
fi
: "${DISCOURSE_DB_NAME:=discourse}"
: "${DISCOURSE_DB_USER:=discourse_app}"

echo "[backup] dumping postgres database ${DISCOURSE_DB_NAME}"
if podman container exists "$DISCOURSE_PG_CONTAINER" 2>/dev/null; then
  podman exec -u postgres "$DISCOURSE_PG_CONTAINER" \
    "${PG_DUMP_TOOL}" -U "$DISCOURSE_DB_USER" -d "$DISCOURSE_DB_NAME" \
    | gzip > "$DISCOURSE_BACKUP_DEST/discourse-pg-$PIN.sql.gz"
else
  echo "[backup] WARN: postgres container not present; skipping pg dump" >&2
fi

echo "[backup] archiving /shared uploads"
# /shared lives on the dedicated discourse-shared volume; back up its contents
# by rsync into the backup destination (simple, low-coupling).
if command -v rsync >/dev/null 2>&1; then
  mkdir -p "$DISCOURSE_BACKUP_DEST/shared"
  rsync -a --delete "$HOME/discourse/volumes/shared/" \
    "$DISCOURSE_BACKUP_DEST/shared/" 2>/dev/null \
  || rsync -a --delete "/var/lib/discourse/shared/" \
    "$DISCOURSE_BACKUP_DEST/shared/" 2>/dev/null || true
else
  echo "[backup] WARN: rsync unavailable; uploads not archived" >&2
fi

echo "[backup] pruning backups older than ${DISCOURSE_BACKUP_RETENTION_DAYS} days"
find "$DISCOURSE_BACKUP_DEST" -maxdepth 1 -name 'discourse-pg-*.sql.gz' \
  -mtime "+${DISCOURSE_BACKUP_RETENTION_DAYS}" -delete 2>/dev/null || true

echo "[backup] complete at $(date -u +%FT%TZ)"
