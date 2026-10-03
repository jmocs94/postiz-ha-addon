# Test plan

Run top to bottom on the real Home Assistant machine. Record date, app
versions and result for each line. "Log" means the app's Log tab.

## 1. Install test
- [ ] Repository added; five apps listed under "Postiz for Home Assistant".
- [ ] PostgreSQL, Redis, Temporal, Postiz install (build) without errors.
- [ ] Settings > System > Repairs shows nothing new; HA Core unaffected.

## 2. First boot (empty storage)
- [ ] PostgreSQL log: `initialising a new PostgreSQL 16 cluster`, then
      `Roles and databases are in place`, then `ready to accept connections`.
- [ ] Redis log: `Password authentication: on`, `Ready to accept connections`.
- [ ] Temporal log: `login as 'temporal' verified`, schema statements,
      `Default namespace default registration complete`,
      `Temporal is ready`.
- [ ] Postiz log: `generated a new random secret (first start)`, the three
      dependency checks, `prisma db push`, `Postiz is ready`.
- [ ] No password, secret or full connection string appears in any log.

## 3. Second boot (credentials/data reused)
- [ ] Restart all four apps. PostgreSQL: `Existing PostgreSQL 16 cluster found`.
      Temporal: schema setup is skipped ("Skip version upgrade"),
      `namespace default already registered`. Postiz: `reusing the stored secret`.

## 4. Postiz login
- [ ] `http://<HA-IP>:4007` from another LAN computer opens `/auth`.
- [ ] First account created and usable without e-mail.
- [ ] After logout `/auth` shows "Registration is disabled".

## 5. Restart Postiz
- [ ] Restart Postiz app; log in again with the same account.
- [ ] Log shows `Stop requested: stopping Postiz processes gracefully...` and
      `Postiz stopped.` (no Supervisor warning about exit code 143).

## 6. Host reboot
- [ ] Settings > System > ⋮ > Restart system (host reboot).
- [ ] HA Core comes up as usual; PostgreSQL/Redis start before Core,
      Temporal/Postiz after it; Postiz becomes reachable without manual action.

## 7. Redis restart
- [ ] Restart Postiz Redis while Postiz runs. Postiz keeps working after a
      few seconds (ioredis reconnects); log in / navigate still works.

## 8. Temporal restart
- [ ] Restart Postiz Temporal while Postiz runs. After `Temporal is ready`,
      schedule a post (or check Temporal UI) - Postiz workers reconnect.
      If not, restart Postiz and note it.

## 9. Database restart
- [ ] Restart Postiz PostgreSQL. Temporal and Postiz log connection errors
      during the restart and recover afterwards (Prisma and Temporal retry).
      If either does not, restart it and note it.

## 10. Upload test
- [ ] Upload an image in the media library; it displays.
- [ ] Restart Postiz; the image still displays (file in /data/uploads).

## 11. Schedule test
- [ ] Start Temporal UI: workflow `missing-post-workflow` is Running in
      namespace `default` (proves the Postiz → Temporal connection and workers).
- [ ] With a channel that needs no OAuth app (Bluesky app password, or a
      Telegram bot from postiz.env), schedule a post 10 minutes ahead; a
      `post_<id>` workflow appears in Temporal UI and the post is published
      on time.
- [ ] Without any channel: at least confirm `missing-post-workflow` keeps
      running after a Temporal restart.
- [ ] Stop Temporal UI.

## 12. Backup test
- [ ] Create a full backup. In its details all five apps are listed.
- [ ] PostgreSQL was stopped and restarted during the backup (its log).
- [ ] Optional, on a test machine: restore PostgreSQL, then Redis/Temporal,
      then Postiz; log in; the uploaded image is present.

## 13. Update test
- [ ] Bump `version` of one app (e.g. Postiz Redis 0.1.0 → 0.1.1) without
      other changes, push, Check for updates, Update. Data and options remain;
      Postiz keeps working.

## 14. Failure containment
- [ ] Stop PostgreSQL, then start Postiz: Postiz logs `Waiting for PostgreSQL`
      every 30 s and stops with a clear FATAL after `wait_timeout`.
- [ ] Enter a wrong `redis_password` in Postiz: immediate clear FATAL.
- [ ] HA Core stays responsive throughout.

## 15. Uninstall test (only when you are done)
- [ ] Take a backup. Follow README Part 14.
- [ ] `configuration.yaml`, other apps and HA history are unchanged.
