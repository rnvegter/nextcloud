#!/usr/bin/env bash
# Sets up a Nextcloud deployment folder: compose file, scripts, data folders and secrets.
# Safe to re-run: existing .env, restic.env and compose.yaml are kept, scripts are refreshed.
#
# Usage: ./install.sh [target-dir] [--start]
#   target-dir  where the deployment lives (default: /srv/nextcloud)
#   --start     start the stack after installing (skip this when you plan to restore a backup)
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET="/srv/nextcloud"
START=false

for arg in "$@"; do
  case "$arg" in
    --start) START=true ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown option: $arg" >&2; exit 1 ;;
    *) TARGET="$arg" ;;
  esac
done

need() { command -v "$1" >/dev/null || { echo "Missing required tool: $1" >&2; exit 1; }; }
need docker
need openssl
docker compose version >/dev/null 2>&1 || { echo "Missing required tool: docker compose plugin" >&2; exit 1; }
command -v restic >/dev/null || echo "Note: restic is not installed. Backups need it (apt install restic / brew install restic)."

mkdir -p "$TARGET"/{app,data,db,backup/db,scripts}
chmod 700 "$TARGET/backup"   # database dumps contain password hashes
TARGET="$(cd "$TARGET" && pwd)"

# Copies a template once; afterwards the deployment's own copy wins.
install_once() {
  local src="$1" dest="$2"
  if [[ ! -e "$dest" ]]; then
    cp "$src" "$dest"
    echo "Created $dest"
  elif ! cmp -s "$src" "$dest"; then
    echo "Kept existing $dest (differs from the template in $SRC)"
  fi
}

install_once "$SRC/compose.yaml" "$TARGET/compose.yaml"
cp "$SRC"/scripts/*.sh "$TARGET/scripts/"
chmod +x "$TARGET"/scripts/*.sh

if [[ ! -e "$TARGET/.env" ]]; then
  sed -e "s/^NEXTCLOUD_ADMIN_PASSWORD=.*/NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -hex 16)/" \
      -e "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" \
      -e "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=$(openssl rand -hex 24)/" \
      "$SRC/.env.example" > "$TARGET/.env"
  chmod 600 "$TARGET/.env"
  echo "Created $TARGET/.env with random passwords"
fi

if [[ ! -e "$TARGET/restic.env" ]]; then
  sed -e "s/^RESTIC_PASSWORD=.*/RESTIC_PASSWORD=\"$(openssl rand -hex 32)\"/" \
      "$SRC/restic.env.example" > "$TARGET/restic.env"
  chmod 600 "$TARGET/restic.env"
  echo "Created $TARGET/restic.env with a random repository password"
fi

# On Linux the container writes user files as www-data (uid 33).
# Docker Desktop on macOS maps ownership itself.
if [[ "$(uname -s)" == Linux && $EUID -eq 0 ]]; then
  chown 33:33 "$TARGET/data"
  chmod 750 "$TARGET/data"
fi

if $START; then
  (cd "$TARGET" && docker compose up -d)
fi

cat <<EOF

Nextcloud is set up in $TARGET

Next steps:
  1. Edit $TARGET/.env: set NEXTCLOUD_TRUSTED_DOMAINS (and NEXTCLOUD_VERSION if you want to pin one).
  2. Edit $TARGET/restic.env: set RESTIC_REPOSITORY to your Storage Box.
     Save RESTIC_PASSWORD in your password manager. Restoring on a new server needs it.
  3. Give this machine SSH access to the Storage Box (run as the user that runs backups):
       ssh-keygen -t ed25519            # if you have no key yet
       ssh-copy-id -p 23 -s u123456@u123456.your-storagebox.de
  4. Then choose one:
     New instance:       cd $TARGET && docker compose up -d && scripts/backup.sh init
     Restore a backup:   copy the old restic.env here, then run $TARGET/scripts/restore.sh
  5. Schedule nightly backups, e.g. in root's crontab:
       30 3 * * * $TARGET/scripts/backup.sh >> /var/log/nextcloud-backup.log 2>&1
EOF
