#!/usr/bin/env python3
"""Lightweight consistency checks for the app folders (run by CI).

Checks per app folder:
  * slug matches the folder name, arch is amd64 only
  * every option has a schema entry, every translation key has a schema entry
  * the newest CHANGELOG.md entry matches config.yaml `version`
  * Dockerfile has an explicit, non-floating FROM (no BUILD_FROM, no :latest)
  * the `# upstream_version:` comments in config.yaml and Dockerfile agree
"""
import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
APPS = ["postiz_postgres", "postiz_redis", "postiz_temporal", "postiz", "postiz_temporal_ui"]
errors = []


def err(app, msg):
    errors.append(f"{app}: {msg}")


for app in APPS:
    folder = ROOT / app
    cfg = yaml.safe_load((folder / "config.yaml").read_text())
    if cfg.get("slug") != app:
        err(app, f"slug {cfg.get('slug')!r} != folder name")
    if cfg.get("arch") != ["amd64"]:
        err(app, "arch must be [amd64]")
    if "image" in cfg and ":" in cfg["image"].split("/")[-1]:
        err(app, "image must not contain a tag")
    schema = cfg.get("schema") or {}
    for key in (cfg.get("options") or {}):
        if key not in schema:
            err(app, f"option {key!r} missing from schema")
    tr = yaml.safe_load((folder / "translations" / "en.yaml").read_text())
    for key in (tr.get("configuration") or {}):
        if key not in schema:
            err(app, f"translation key {key!r} not in schema")
    changelog = (folder / "CHANGELOG.md").read_text()
    m = re.search(r"^## \[?([0-9][^\]\s]*)", changelog, re.M)
    if not m or m.group(1) != str(cfg["version"]):
        err(app, f"CHANGELOG top entry {m.group(1) if m else None!r} != version {cfg['version']!r}")
    dockerfile = (folder / "Dockerfile").read_text()
    froms = re.findall(r"^FROM\s+(\S+)", dockerfile, re.M)
    if not froms:
        err(app, "Dockerfile has no FROM")
    for ref in froms:
        if "BUILD_FROM" in ref or ref.endswith(":latest") or ":" not in ref:
            err(app, f"floating or implicit base image {ref!r}")
    cfg_text = (folder / "config.yaml").read_text()
    up_cfg = re.search(r"upstream_version:\s*(.+)", cfg_text)
    up_df = re.search(r"upstream_version:\s*(.+)", dockerfile)
    if not up_cfg or not up_df:
        err(app, "missing upstream_version comment")
    else:
        tag = (froms[0] if froms else "").split(":")[-1]
        ver = re.match(r"v?\d+(?:\.\d+)+", tag)
        ver = ver.group(0) if ver else tag
        for label, text in (("config.yaml", up_cfg.group(1)), ("Dockerfile", up_df.group(1))):
            if ver not in text:
                err(app, f"{label} upstream_version comment does not mention base version {ver!r}")
    for path in (folder / "rootfs").rglob("*.sh"):
        if "\r" in path.read_text():
            err(app, f"{path} has CRLF line endings")

if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"config checks passed for {len(APPS)} apps")
