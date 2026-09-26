#!/usr/bin/env bash
# Restores a Nextcloud backup from restic into a fresh deployment folder.
# Run install.sh first without --start, and put the old restic.env in place.
#
# Usage: scripts/restore.sh [snapshot-id]   (default: latest)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
set -a; source ./restic.env; set +a
SNAPSHOT="${1:-latest}"

if [[ -n "$(find app data db -mindepth 1 -print -quit 2>/dev/null)" ]]; then
  echo "app/, data/ and db/ must be empty. Restore only into a fresh install that has not been started." >&2
  exit 1
fi

# backup.sh backs up relative paths, so snapshots restore straight into this folder.
echo "== Restoring files from $SNAPSHOT"
restic restore "$SNAPSHOT" --tag nextcloud --target "$ROOT"
[[ -f backup/db/nextcloud.sql ]] || { echo "Snapshot has no database dump; is this a Nextcloud backup?" >&2; exit 1; }

echo "== Restoring database"
docker compose up -d db
for _ in $(seq 60); do
  docker compose exec -T db sh -c 'pg_isready -q -h 127.0.0.1 -U "$POSTGRES_USER"' && break
  sleep 2
done
# Errors about the connecting superuser already existing are expected and harmless.
docker compose exec -T db sh -c 'psql -q -U "$POSTGRES_USER" -d postgres' \
  < backup/db/nextcloud.sql > /dev/null

echo "== Starting Nextcloud"
docker compose up -d
occ() { docker compose exec -T -u www-data app php occ "$@"; }
# The backup was taken in maintenance mode; wait for the app to come up, then leave it.
for _ in $(seq 60); do
  occ maintenance:mode --off >/dev/null 2>&1 && break
  sleep 5
done
occ maintenance:mode --off
occ maintenance:data-fingerprint

cat <<EOF

Restore finished. If the domain changed, add it:
  docker compose exec -u www-data app php occ config:system:set trusted_domains 1 --value=new.example.com
EOF
