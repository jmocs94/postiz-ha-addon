# Changelog

## 0.1.0

- First release. Upstream: postgres:16.15-trixie.
- Databases `postiz`, `temporal`, `temporal_visibility`; users `postiz`, `temporal`.
- Cluster created with UTF8 / C.UTF-8 and data checksums.
- Refuses to start on a data directory from another PostgreSQL major version.
