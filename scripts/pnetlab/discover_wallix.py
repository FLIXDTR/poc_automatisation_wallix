#!/usr/bin/env python3
"""
Discover a WALLIX Bastion node IP by scanning a subnet and probing /api/version.

Designed to be used as a Terraform external data source.
Input (stdin JSON):
  - mgmt_subnet: CIDR (ex: 192.168.214.0/24)
  - timeout_sec: seconds (string/int)
  - expected_ver: version prefix (ex: "12.")
  - node_mac: optional MAC address (ex: "02:aa:bb:cc:dd:ee"). If set, we will
    try to discover the node IP from PNETLab ARP/neighbor table via SSH first.

Output (stdout JSON):
  - ip
  - url
"""

from __future__ import annotations

import concurrent.futures
import ipaddress
import json
import os
import random
import re
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request


def parse_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "y", "on"}:
        return True
    if normalized in {"0", "false", "no", "n", "off"}:
        return False
    return default


def read_query() -> dict:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    return json.loads(raw)


def request_json(url: str, context: ssl.SSLContext, timeout: float = 3.0) -> dict | None:
    req = urllib.request.Request(url=url, method="GET", headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, context=context, timeout=timeout) as resp:
            if int(resp.status) != 200:
                return None
            raw = resp.read()
            if not raw:
                return None
            return json.loads(raw.decode("utf-8", errors="replace"))
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return None


def extract_version(payload: dict) -> str:
    for key in ("wab_version", "version", "WAB_VERSION", "WABVersion"):
        if key in payload:
            return str(payload.get(key) or "").strip()
    return ""


def probe(ip: str, context: ssl.SSLContext, expected_prefix: str) -> str | None:
    url = f"https://{ip}/api/version"
    payload = request_json(url, context=context, timeout=3.0)
    if not isinstance(payload, dict):
        return None
    version = extract_version(payload)
    if not version:
        return None
    if expected_prefix and not version.startswith(expected_prefix):
        return None
    return ip


def build_ssh_command(remote_cmd: str) -> list[str] | None:
    host = (os.environ.get("PNET_SSH_HOST") or "").strip()
    if not host:
        return None

    user = (os.environ.get("PNET_SSH_USER") or "root").strip() or "root"
    port = (os.environ.get("PNET_SSH_PORT") or "22").strip() or "22"
    password = (os.environ.get("PNET_SSH_PASSWORD") or "").strip()
    key_path = (os.environ.get("PNET_SSH_KEY_PATH") or "").strip()

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


def discover_ip_from_pnet_arp(node_mac: str) -> str | None:
    cmd = build_ssh_command("ip neigh show")
    if not cmd:
        return None

    proc = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        return None

    wanted = node_mac.strip().lower()
    regex = re.compile(
        r"^(?P<ip>\\d+\\.\\d+\\.\\d+\\.\\d+)\\s+dev\\s+\\S+\\s+lladdr\\s+(?P<mac>[0-9a-fA-F:]{17})\\s+(?P<state>\\S+)",
        re.MULTILINE,
    )

    candidates: list[tuple[int, str]] = []
    for match in regex.finditer(proc.stdout or ""):
        mac = (match.group("mac") or "").strip().lower()
        if mac != wanted:
            continue
        ip = (match.group("ip") or "").strip()
        state = (match.group("state") or "").strip().upper()
        priority = {
            "REACHABLE": 0,
            "STALE": 1,
            "DELAY": 2,
            "PROBE": 3,
            "FAILED": 4,
            "INCOMPLETE": 5,
        }.get(state, 10)
        candidates.append((priority, ip))

    if not candidates:
        return None
    candidates.sort(key=lambda x: x[0])
    return candidates[0][1]


def main() -> int:
    query = read_query()
    mgmt_subnet = str(query.get("mgmt_subnet") or "").strip()
    timeout_sec = float(str(query.get("timeout_sec") or "1800").strip() or "1800")
    expected_prefix = str(query.get("expected_ver") or "12.").strip()
    node_mac = str(query.get("node_mac") or "").strip()

    if not mgmt_subnet:
        raise RuntimeError("mgmt_subnet is required.")

    validate_certs = parse_bool(os.environ.get("WALLIX_VALIDATE_CERTS", "false"), False)
    context = ssl.create_default_context()
    if not validate_certs:
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE

    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        # Fast-path: if a MAC is provided, try to map it to an IP via the
        # PNETLab host neighbor cache (ARP). This is very quick when it works,
        # but some environments won't populate `ip neigh` reliably, so we also
        # fall back to scanning the subnet.
        if node_mac:
            ip = discover_ip_from_pnet_arp(node_mac)
            if ip:
                found = probe(ip, context, expected_prefix)
                if found:
                    result = {"ip": found, "url": f"https://{found}"}
                    sys.stdout.write(json.dumps(result))
                    return 0

        network = ipaddress.ip_network(mgmt_subnet, strict=False)
        if network.num_addresses > 4096:
            # Avoid blasting large networks in a PoC script.
            time.sleep(5)
            continue

        hosts = [str(ip) for ip in network.hosts()]
        if not hosts:
            raise RuntimeError("mgmt_subnet has no usable hosts.")

        random.shuffle(hosts)
        with concurrent.futures.ThreadPoolExecutor(max_workers=64) as executor:
            futures = {
                executor.submit(probe, ip, context, expected_prefix): ip for ip in hosts
            }
            for fut in concurrent.futures.as_completed(futures):
                found = fut.result()
                if found:
                    result = {"ip": found, "url": f"https://{found}"}
                    sys.stdout.write(json.dumps(result))
                    return 0
        time.sleep(5)

    raise RuntimeError(
        f"Timeout after {int(timeout_sec)}s: no WALLIX found on {mgmt_subnet} (/api/version)."
    )


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        raise SystemExit(1)
