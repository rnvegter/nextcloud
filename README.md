# Nextcloud with Docker Compose

Nextcloud on PostgreSQL and Redis, with all data in plain folders and nightly restic backups to a Hetzner Storage Box. One script sets up a new server; one script restores a backup onto it.

## Layout

`install.sh` creates this structure in the target folder (default `/srv/nextcloud`):

```
/srv/nextcloud/
├── compose.yaml
├── .env              passwords and settings (generated)
├── restic.env        backup repository and password (generated)
├── app/              Nextcloud code, config and apps
├── data/             user files
├── db/               PostgreSQL files (not backed up directly)
├── backup/db/        database dump, made by backup.sh
└── scripts/
    ├── backup.sh
    └── restore.sh
```

## New server

```bash
./install.sh /srv/nextcloud
```

Then:

1. Set `NEXTCLOUD_TRUSTED_DOMAINS` in `.env`.
2. Set `RESTIC_REPOSITORY` in `restic.env` and store `RESTIC_PASSWORD` in your password manager. Without it the backups can't be read.
3. Give the server SSH access to the Storage Box (port 23):
   `ssh-copy-id -p 23 -s u123456@u123456.your-storagebox.de`
4. Start Nextcloud and create the backup repository:
   `cd /srv/nextcloud && docker compose up -d && scripts/backup.sh init`
5. In Nextcloud, set background jobs to "Cron" (Administration > Basic settings).

## Backups

`scripts/backup.sh` puts Nextcloud in maintenance mode, dumps the database with `pg_dumpall`, backs up `.env`, `compose.yaml`, `app/`, `data/` and the dump with restic, then applies the retention in `restic.env` (default 7 daily, 4 weekly, 12 monthly).

Run it nightly, for example from root's crontab:

```
30 3 * * * /srv/nextcloud/scripts/backup.sh >> /var/log/nextcloud-backup.log 2>&1
```

## Restore or move to another server

1. `./install.sh /srv/nextcloud` (without `--start`).
2. Copy the old `restic.env` into `/srv/nextcloud`.
3. `/srv/nextcloud/scripts/restore.sh` (or pass a snapshot id; default is `latest`).

The restore brings back files, database and `.env`, then starts Nextcloud. If the domain changed, add it with `occ config:system:set trusted_domains`.

## Requirements

Docker with the Compose plugin, `openssl`, and `restic` on the host.
