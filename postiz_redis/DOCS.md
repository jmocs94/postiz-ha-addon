# Postiz Redis

Redis 7.2 for Postiz. Postiz uses it only for short-lived data: API rate-limit
counters, OAuth "connect a channel" state, upload tickets and small caches.
Postiz's job queues live in Temporal, not Redis.

## Options

| Option | Description |
|---|---|
| `password` | Required. Enter the same value as **Redis password** in the **Postiz** app. 16-128 characters from `A-Z a-z 0-9 . _ ~ -` (`openssl rand -hex 24`). |
| `maxmemory_mb` | Default 128. Least-recently-used keys are evicted when full. |
| `persistence` | Default off. When on, RDB snapshots are written to this app's data folder and included in backups. Not needed for Postiz: losing Redis only interrupts a channel connection or upload that is in progress at that moment. |

The password is written to a config file inside the container on every start;
it never appears on a command line or in the log.

## Network

Port 6379 is **not** published on your LAN. Only apps on the internal
Supervisor network can reach it, and they need the password.

## Backups

Backups are hot (Redis keeps running). With persistence off there is nothing
of value to back up.
