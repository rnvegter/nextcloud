# Project Instructions

## What this is

Self-hosted Nextcloud deployment as code: Docker Compose (Nextcloud + PostgreSQL 17 + Redis 7), all state in plain folders next to the compose file, nightly restic backups to a Hetzner Storage Box. Not an application codebase — it ships a compose file plus install/backup/restore shell scripts that run on a Linux server (default target `/srv/nextcloud`). Reverse proxy is Nginx Proxy Manager from the separate `rnvegter/core-stack`; the stacks share no Docker network.

## Layout

- `compose.yaml` — 4 services: `db` (postgres:17-alpine), `redis` (redis:7-alpine), `app` (nextcloud `${NEXTCLOUD_VERSION:-stable}`-apache), `cron` (same image, `/cron.sh` entrypoint, background jobs every 5 min). `app` waits for db/redis healthchecks; `cron` waits for `app`.
- `install.sh` — idempotent setup: creates `app/ data/ db/ backup/db/ scripts/`, copies `compose.yaml` + scripts (scripts always refreshed, compose only once), generates `.env` and `restic.env` with random passwords (`openssl rand -hex`). `--start` boots the stack; omit when planning a restore. Requires root on Linux (fails loudly otherwise) — macOS exempt.
- `scripts/backup.sh` — maintenance mode on (trap restores it on any exit), `pg_dumpall` → `backup/db/nextcloud.sql`, `restic backup` of `.env compose.yaml app data backup/db`, `restic forget --prune` with retention from `restic.env`. `init` argument creates the repository.
- `scripts/restore.sh` — refuses non-empty `app/ data/ db/`, `restic restore` (default `latest`), boots db, applies SQL dump, boots full stack, maintenance off, `maintenance:data-fingerprint`.
- `.env.example` / `restic.env.example` — templates. Real `.env`/`restic.env` are generated, gitignored, chmod 600. `restic.env` is NOT in the backup (chicken-and-egg: its password is needed to read the backup).

## Design decisions (do not casually change)

- `pg_dumpall`, not `pg_dump`: Nextcloud connects as its own `oc_*` DB user; the dump must include roles.
- Plain (uncompressed) SQL dump: restic deduplicates unchanged content between nightly runs.
- `app/` backed up whole (code + config): the Nextcloud image only skips reinstalling code when `version.php` exists, so config without matching code would not boot. Restic stores the code once, so it is cheap.
- Proxy vars in compose.yaml use `${NEXTCLOUD_DOMAIN:+...}` expansion, so `OVERWRITEPROTOCOL`/`OVERWRITECLIURL`/`TRUSTED_PROXIES` are only set when a domain is configured. Trusted domains are only read at first install; later changes need `occ config:system:set trusted_domains`.
- `TRUSTED_PROXIES` is `172.16.0.0/12` (all Docker networks the proxy's requests come from).
- `NEXTCLOUD_BIND_IP=172.17.0.1` option exists so only the proxy can reach port 8080 (nobody skips HTTPS).
- `backup/` is chmod 700 — dumps contain password hashes. SQL dump is written to `.sql.tmp` then `mv`'d so a failed dump never leaves a partial file restic would back up.
- Nextcloud data dir is `/var/www/data` (outside the code mount `/var/www/html`), via `NEXTCLOUD_DATA_DIR`.
- Everything runs as root on Linux: `install.sh` refuses non-root, `docker compose` and the scripts read the root-owned `.env` (chmod 600), and `data/` is chowned to www-data (uid 33) at install — a non-root user hitting any compose command gets "open .env: permission denied", so README commands carry `sudo`. Docker Desktop on macOS is exempt (it maps ownership itself).

## Code style (shell)

- bash with `set -euo pipefail`; no dependencies beyond docker/openssl/restic on the host.
- Variables lowercase snake_case; `SRC`/`ROOT`/`TARGET` uppercase. Short helpers: `need`, `install_once`, `occ`, `maintenance_off`.
- Scripts resolve their own location (`dirname "$0"`) and `cd` to the deployment root, so they work from any cwd.
- Comments explain why, not what. Plain English, short sentences, no filler.

## Git

- Commit messages: imperative mood, concise ("Add Nextcloud Docker Compose setup with ...").
- Commits go directly to `main`; no branch/PR workflow in use.
- Always push after committing: origin is `rnvegter/nextcloud` (github.com/rnvegter/nextcloud) — commits never stay local-only.
- Never commit `.env`, `restic.env`, `app/`, `data/`, `db/`, `backup/` (all gitignored).

## After changes, verify

- `docker compose config` validates the compose file.
- `shellcheck install.sh scripts/*.sh` if available.
- Keep `README.md` in sync: it is the operator's source of truth (layout, proxy host setup, restore/move procedure).
