# chat-db (phase 1)

A single-node, secure CockroachDB in Docker that stores users for the chat app's authentication. Nothing else lives here yet.

> **Status:** written without access to Docker, so none of it has been run end to end. Expect to fix small things on first run, and see [Open items](#open-items-to-confirm).

## What you get

| Piece | Purpose |
|---|---|
| `Dockerfile` | Official CockroachDB image plus the scripts and SQL below |
| `docker-compose.yml` | `cockroach` (the node) and `db-setup` (one-shot bootstrap) |
| `scripts/start-node.sh` | Generates local TLS certs on first start, runs the node |
| `scripts/setup.sh` | Creates the database, app role, schema, grants (idempotent) |
| `sql/001_users.sql` | The `users` table |
| `scripts/backup.sh`, `scripts/restore.sh` | Host-side backup and restore |
| `install.sh` | Installer used inside a release package |
| `uninstall.sh` | Removes the containers, data, certs and image |

## Requirements

- Docker with the Compose plugin (`docker compose`)
- Outbound internet access from the container (the free license requires telemetry)

On Windows, keep the repo's LF line endings (`.gitattributes` handles this), otherwise the shell scripts fail inside the container.

## Install from a release package

The root `setup.sh -b <profile>` builds the image and writes it to `package/database/` next to the backend and frontend. That folder is self-contained: copy it anywhere, no registry and no source checkout needed.

```sh
sh install.sh
```

It loads the image from `chat-db.tar.gz`, creates `.env` with a generated app password (an existing `.env` is left alone), starts the database and follows the setup log. The image is built for the CPU architecture of the machine that ran `setup.sh`.

Everything below this section (connecting, backups, license) applies to both install methods.

## Install from source

```sh
cp .env.example .env
# edit .env: at minimum set APP_DB_PASSWORD (openssl rand -hex 24)

docker compose up -d --build
docker compose logs -f db-setup     # wait for "[setup] done"
```

`db-setup` runs once, after the node is healthy, and exits. Re-run it any time with `docker compose run --rm db-setup` (for example after changing the password in `.env`).

## Connect

The SQL port is published on `127.0.0.1` only. The node uses a local CA, so your client needs its certificate:

```sh
docker compose cp cockroach:/certs/ca.crt ./ca.crt
```

Connection string for the auth service:

```
postgresql://chat_app:<APP_DB_PASSWORD>@localhost:26257/chat_db?sslmode=verify-full&sslrootcert=./ca.crt
```

Quick check with a SQL shell inside the container (as root, for admin use only):

```sh
# Secure
docker compose exec cockroach /cockroach/cockroach sql --certs-dir=/certs --host=localhost:26257 -d chat_db -e "SHOW TABLES"

# Insecure
docker compose exec cockroach /cockroach/cockroach sql --insecure --host=localhost:26257 -d chat_db -e "SHOW TABLES"
```

## Schema

One table, `users`, with a random UUID primary key and **globally unique** `username_normalized` and `email_normalized`.

A second table, `refresh_tokens` (`sql/002_refresh_tokens.sql`), stores the SHA-256 hash of each refresh token for the backend (single-use, with expiry and a revoked flag).

If you already have a running database from an earlier version, apply the new table with `docker compose up -d --build` followed by `docker compose run --rm db-setup` (your data is kept).

Your auth service must:

- Normalize usernames and emails (Unicode NFKC, then lowercase) before every insert and lookup. The database cannot do this for you.
- Store the password as a full argon2id PHC string in `password_hash`.
- Retry transactions that fail with SQLSTATE `40001`.

The app role (`chat_app` by default) can `SELECT`, `INSERT` and `UPDATE` on `users` and `refresh_tokens`, and nothing else: no DDL and no `DELETE`. Add `DELETE` in `scripts/setup.sh` when you build account deletion. Grants for any new table must be added there too.

## License

CockroachDB is source-available, not open source. For personal use you run under **CockroachDB Enterprise Free**:

- Free for individuals, and for businesses under $10M annual revenue.
- One-year term, renewable only while you still meet the eligibility requirements. **Put the renewal date in your calendar.**
- Telemetry is required for any cluster that lives longer than 7 days.
- Community support only.

`setup.sh` applies `COCKROACH_ORG` and `COCKROACH_LICENSE` from `.env` using the `cluster.organization` and `enterprise.license` cluster settings, if both are set.

## Backup and restore

```sh
scripts/backup.sh                              # writes ./backups/<timestamp>
scripts/restore.sh backups/<timestamp> --yes   # DROPS the database, then restores
```

Backups are CockroachDB `BACKUP` files copied out of the container. **Test a restore once** before you rely on this. `docker compose down -v` deletes the data and cert volumes, and backups taken before that are the only way back.

## Security notes

- TLS and password authentication are on. The port is bound to localhost.
- The CA key (`ca.key`) lives in the certs volume next to the certs. That is fine for local development. For anything shared, generate certs yourself and keep the CA key offline.
- `APP_DB_PASSWORD` is passed to the setup container as an environment variable, so it is visible via `docker inspect` on the host.
- Never connect your app as `root`.

## Uninstall

```sh
sh uninstall.sh               # asks you to type "delete", then removes containers, volumes and the image
sh uninstall.sh --keep-data   # removes containers and the image, keeps the data and cert volumes
sh uninstall.sh --yes         # no prompt
```

`.env`, `ca.crt` and `backups/` are left in place. Take a backup first if you need the data.

## Reset everything

Same as `sh uninstall.sh`, or from a source checkout:

```sh
docker compose down -v
```

## Open items to confirm

1. **License activation.** Check the Enterprise Free docs for how to obtain the key, whether a cluster without one keeps running, and what happens at expiry. The setting names used in `setup.sh` (`cluster.organization`, `enterprise.license`) are from memory and not verified against v26.1.
2. **Image tag.** `.env.example` uses `latest-v26.1`. Replace it with an exact patch tag to pin fully.
3. **Backup/restore scripts** assume the `nodelocal` backup location maps to `<store>/extern` and that the container runs as a user allowed to read files copied in with `docker cp`.
4. **`REVOKE CREATE ON SCHEMA public`** in `setup.sh` is non-fatal if your version rejects it.

## Not done yet (on purpose)

- Multi-node cluster and `cockroach init`
- A migration tool. For now `sql/*.sql` files are applied in order on every setup, so every file must be idempotent. Pick a real migration tool before the schema grows.
- Sessions, refresh tokens, messages, and anything else beyond user authentication
- Production hardening (cert rotation, offline CA, monitoring)