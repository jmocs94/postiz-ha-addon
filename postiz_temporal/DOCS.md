# Postiz Temporal

Temporal runs every scheduled and background job in Postiz (publishing posts
at the scheduled time, retries, token refreshes, e-mails, the "missing posts"
check). Postiz has required Temporal since v2.12.0.

This app runs the upstream `temporalio/auto-setup` image (1.28.4) with:

- **PostgreSQL for persistence and visibility** (databases `temporal` and
  `temporal_visibility` in the Postiz PostgreSQL app). Elasticsearch is not
  used. Postiz's search attributes (`organizationId`, `postId`, type Text) and
  its workflow queries were tested against this configuration.
- `SKIP_ADD_CUSTOM_SEARCH_ATTRIBUTES=true`: upstream's demo attributes would
  otherwise take 2 of PostgreSQL's 3 Text attribute slots and Postiz would
  fail to register its own (Postiz issue #1504).
- The `default` namespace, created automatically on first start.

## Options

| Option | Description |
|---|---|
| `database_password` | Must equal `temporal_password` in the Postiz PostgreSQL app. |
| `namespace_retention` | How long finished workflow histories are kept, e.g. `72h`. Only used when the namespace is first created. |
| `log_level` | `warn` (default) keeps the log quiet. Use `info` or `debug` when troubleshooting. |
| `wait_timeout` | Seconds to wait for PostgreSQL at start-up before failing. |
| `postgres_host` | Leave empty. Override only if discovery fails. |

## Start-up log

Normal first start:

```
[postiz-temporal] PostgreSQL reachable; login as 'temporal' verified.
... (a long list of schema statements, first start only) ...
Temporal server started.
Default namespace default not found. Creating...        <- normal on first start
Default namespace default registration complete.
[postiz-temporal] Temporal is ready: frontend on port 7233, namespace 'default' available.
```

Lines like `level=ERROR msg="failed reaching server ... connection refused"`
right after `Temporal CLI address` are printed by the upstream script while
the server is still starting and are expected. A few `"level":"warn"` lines
about shards right after start are also normal.

## Data

This app keeps no important data itself; everything is in the Postiz
PostgreSQL app. Backups are hot.

## Network

gRPC port 7233 (and the HTTP API on 7243) are reachable only on the internal
Supervisor network. 7233 can be published temporarily in the **Network**
section for debugging.

## Upgrades

On every start the upstream script runs Temporal's `update-schema`, so a
newer patch version upgrades the schema automatically. Temporal must be
upgraded **one minor version at a time** (1.28 -> 1.29 -> ...). The
auto-setup image is deprecated upstream after 1.29; going beyond that will need
a new version of this app based on `temporalio/server`.
