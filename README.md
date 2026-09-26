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

1. Set `NEXTCLOUD_DOMAIN` in `.env` and add the proxy host (see [Reverse proxy](#reverse-proxy)).
2. Set `RESTIC_REPOSITORY` in `restic.env` and store `RESTIC_PASSWORD` in your password manager. Without it the backups can't be read.
3. Give the server SSH access to the Storage Box (port 23):
   `ssh-copy-id -p 23 -s u123456@u123456.your-storagebox.de`
4. Start Nextcloud and create the backup repository:
   `cd /srv/nextcloud && docker compose up -d && scripts/backup.sh init`
5. In Nextcloud, set background jobs to "Cron" (Administration > Basic settings).

## Reverse proxy

Nextcloud runs behind Nginx Proxy Manager from the core stack (`rnvegter/core-stack`, README section 5). The stacks don't share a Docker network: the proxy reaches Nextcloud on the port this stack publishes on the server.

```
https://nextcloud.home.yourdomain.nl
  → AdGuard Home: *.home.yourdomain.nl = the server
  → Nginx Proxy Manager (443, wildcard certificate)
  → http://host.docker.internal:8080
  → Nextcloud
```

**In `.env`:** set `NEXTCLOUD_DOMAIN` before the first start. The stack then sets Nextcloud's trusted domain, HTTPS links and trusted proxies itself. Leave it empty to run without a proxy on `http://<server>:8080`.

**In Nginx Proxy Manager:** Hosts → Proxy Hosts → Add Proxy Host.

- **Domain Names:** the value of `NEXTCLOUD_DOMAIN`
- **Scheme:** `http`. **Forward Hostname / IP:** `host.docker.internal`. **Forward Port:** `NEXTCLOUD_PORT` (8080)
- Tick **Block Common Exploits** and **Websockets Support**
- **SSL tab:** the `*.home.yourdomain.nl` certificate, tick **Force SSL** and **HTTP/2 Support**
- **Advanced tab**, so large uploads and long syncs work:

  ```
  client_max_body_size 0;
  proxy_request_buffering off;
  proxy_read_timeout 3600s;
  ```

**Good to know:**

- The trusted domain is only read at first install. To add or change a domain later:
  `docker compose exec -u www-data app php occ config:system:set trusted_domains 1 --value=nextcloud.home.yourdomain.nl`
- Keep Nextcloud out of the Cloudflare Tunnel: uploads over 100 MB fail there. Use it at home or over Tailscale.
- To stop people bypassing HTTPS on port 8080, set `NEXTCLOUD_BIND_IP=172.17.0.1` (Docker's bridge address on Linux; check with `ip -4 addr show docker0`). Only the proxy can reach Nextcloud then.

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
