# Changelog

## 0.1.1

- Fix: give /etc/temporal/config back to the temporal user after COPY
  (start-up failed with "unable to create open /etc/temporal/config/docker.yaml:
  permission denied").

## 0.1.0

- First release. Upstream: temporalio/auto-setup:1.28.4.
- SQL visibility on PostgreSQL (Elasticsearch removed vs. upstream Postiz compose).
- `SKIP_ADD_CUSTOM_SEARCH_ATTRIBUTES=true` so Postiz's Text search attributes fit.
- Upstream Postiz compose pins 1.28.1; 1.28.4 is the same minor line with security fixes.
