# Postiz PostgreSQL

PostgreSQL 16 for the Postiz app suite. It holds three databases:

| Database | Owner/user | Used by |
|---|---|---|
| `postiz` | `postiz` | Postiz (accounts, posts, channels, media records) |
| `temporal` | `temporal` | Temporal persistence (workflows, timers, history) |
| `temporal_visibility` | `temporal` | Temporal visibility (workflow search/listing) |

Each user can only connect to its own databases. The `postgres` superuser can
only log in through the container's local socket; it is rejected over the
network.

## Options

| Option | Description |
|---|---|
| `postiz_password` | Password of the `postiz` user. Enter the same value as **Database password** in the **Postiz** app. |
| `temporal_password` | Password of the `temporal` user. Enter the same value as **Database password** in the **Postiz Temporal** app. Must differ from `postiz_password`. |
| `max_connections` | Default 100. Postiz + Temporal use roughly 40-60. |
| `shared_buffers_mb` | Default 128 MB. |

Passwords: 16-128 characters from `A-Z a-z 0-9 . _ ~ -`. Generate them in the
**Terminal & SSH** app with `openssl rand -hex 24`, or with a password manager.

**Changing a password:** change it here and restart this app (the new password
is applied on every start), then change it in the app that uses it and restart
that app.

## What happens on start

1. First start only: a new cluster is created in this app's data folder
   (`UTF8`, `C.UTF-8`, data checksums on). The log says
   `initialising a new PostgreSQL 16 cluster`.
2. Every start: `pg_hba.conf` is rewritten, missing roles/databases are
   created, passwords are applied. Nothing is ever dropped.
3. PostgreSQL starts on port 5432 on the internal Supervisor network.
   `database system is ready to accept connections` means it is up.

## Data and backups

- All data lives in this app's private data folder (`/data/postgres` inside
  the container). It survives restarts, reboots and app updates.
- Backups are **cold**: Supervisor stops PostgreSQL while it copies the data
  folder, so the copy is consistent. Postiz and Temporal lose their database
  for the duration (typically a minute or two) and reconnect afterwards.
- **Uninstalling this app permanently deletes the data folder, i.e. all
  Postiz and Temporal data.** Take a backup first.

## Network

Port 5432 is **not** published on your LAN. For temporary debugging you can
enter a host port in the **Network** section; clear it again afterwards.

## PostgreSQL major versions

This app is pinned to PostgreSQL **16**. If a future version of this app ever
changes the major version, it will ship with an explicit migration procedure.
If the data folder was created by a different major version, the app refuses
to start and changes nothing:

```
FATAL: The data in /data/postgres was created by PostgreSQL 15, but this app runs PostgreSQL 16 ...
```

Recovery from that message: restore the matching app version from a Home
Assistant backup (Settings > System > Backups).
