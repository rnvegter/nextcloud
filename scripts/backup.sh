#!/usr/bin/env bash
# Backs up Nextcloud to the restic repository configured in restic.env.
#
# Usage: scripts/backup.sh          dump the database, back up, apply retention
#        scripts/backup.sh init     create the restic repository (run once)
#
# Nextcloud stays in maintenance mode during the dump and upload so files and
# database match. The first upload of a large data folder can take a while.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
set -a; source ./restic.env; set +a

if [[ "${1:-}" == init ]]; then
  restic init
  exit
fi

occ() { docker compose exec -T -u www-data app php occ "$@"; }

maintenance_off() {
  occ maintenance:mode --off >/dev/null || echo "WARNING: could not turn off maintenance mode" >&2
}

echo "== $(date '+%F %T') backup started"
occ maintenance:mode --on >/dev/null
trap maintenance_off EXIT

# pg_dumpall includes roles: Nextcloud connects with its own oc_* user, not POSTGRES_USER.
# Plain SQL (not compressed) lets restic deduplicate unchanged parts between runs.
mkdir -p backup/db
chmod 700 backup
docker compose exec -T db sh -c 'pg_dumpall -U "$POSTGRES_USER" --clean --if-exists' \
  > backup/db/nextcloud.sql.tmp
mv backup/db/nextcloud.sql.tmp backup/db/nextcloud.sql

# app/ is backed up whole: the image only skips reinstalling code when it finds
# version.php, so config without matching code would not start. restic stores
# the unchanged code once, so this costs little after the first run.
restic backup --tag nextcloud .env compose.yaml app data backup/db

maintenance_off
trap - EXIT

restic forget --tag nextcloud --prune \
  --keep-daily "${KEEP_DAILY:-7}" --keep-weekly "${KEEP_WEEKLY:-4}" --keep-monthly "${KEEP_MONTHLY:-12}"
echo "== $(date '+%F %T') backup finished"
