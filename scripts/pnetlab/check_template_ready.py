#!/usr/bin/env python3
"""
Check whether a PNETLab/EVE-NG QEMU image is "template-ready".

We use a simple marker file created by commit_template.sh:
  /opt/unetlab/addons/qemu/<image_name>/.template_ready

Designed to be used as a Terraform external data source.
Input (stdin JSON):
  - image_name (required)

Output (stdout JSON):
  - ready: "true" | "false"
  - marker: marker path
"""

from __future__ import annotations

import json
import os
import subprocess
import sys


def read_query() -> dict:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    return json.loads(raw)


def build_ssh_command(remote_cmd: str) -> list[str]:
    host = (
        (os.environ.get("PNET_SSH_HOST") or "").strip()
        or (os.environ.get("TF_VAR_pnet_ssh_host") or "").strip()
    )
    if not host:
        raise RuntimeError("PNET_SSH_HOST is required (or TF_VAR_pnet_ssh_host).")

    user = (
        (os.environ.get("PNET_SSH_USER") or "").strip()
        or (os.environ.get("TF_VAR_pnet_ssh_user") or "").strip()
        or "root"
    )
    port = (os.environ.get("PNET_SSH_PORT") or "22").strip() or "22"
    password = (
        (os.environ.get("PNET_SSH_PASSWORD") or "").strip()
        or (os.environ.get("TF_VAR_pnet_ssh_password") or "").strip()
    )
    key_path = (
        (os.environ.get("PNET_SSH_KEY_PATH") or "").strip()
        or (os.environ.get("TF_VAR_pnet_ssh_key_path") or "").strip()
    )

    base = [
        "ssh",
        "-p",
        port,
        "-o",
        "StrictHostKeyChecking=no",
        "-o",
        "UserKnownHostsFile=/dev/null",
    ]
    if key_path:
        base.extend(["-i", key_path])

    full = base + [f"{user}@{host}", remote_cmd]
    if password and not key_path:
        full = ["sshpass", "-p", password] + full
    return full


def main() -> int:
    query = read_query()
    image_name = str(query.get("image_name") or "").strip()
    if not image_name:
        raise RuntimeError("image_name is required.")

    marker = f"/opt/unetlab/addons/qemu/{image_name}/.template_ready"
    cmd = build_ssh_command(f"test -f '{marker}'")

    proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    ready = proc.returncode == 0
    sys.stdout.write(json.dumps({"ready": "true" if ready else "false", "marker": marker}))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        raise SystemExit(1)

