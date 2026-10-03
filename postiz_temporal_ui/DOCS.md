# Temporal UI for Postiz (optional)

A web UI for the Postiz Temporal server. Use it to confirm that Postiz
workflows exist and run, e.g. during the first test or when a scheduled post
did not go out. **Postiz does not need it.**

**Security:** Temporal UI has no login. Anyone who can reach the port can
read workflow data (post IDs, organisation IDs, error messages). Because of
that, this app has `boot: manual` (it never starts on its own) and starts in
read-only mode. Start it, look, stop it.

## Using it

1. Start the app, then open `http://YOUR-HA-IP:8233` (or **Open web UI**).
2. Namespace `default` -> **Workflows**.
3. After Postiz has started you should see a running workflow with ID
   `missing-post-workflow`. Every scheduled post creates a workflow with ID
   `post_<postId>`.

## Options

| Option | Description |
|---|---|
| `read_only` | Default on: terminate/cancel/signal/reset are disabled. |
| `wait_timeout` | Seconds to wait for the Temporal app. |
| `temporal_host` | Leave empty (automatic discovery). |

The host port (default 8233) can be changed or removed in the **Network**
section.
