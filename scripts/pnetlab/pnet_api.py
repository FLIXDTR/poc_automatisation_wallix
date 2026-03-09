#!/usr/bin/env python3
"""
PNETLab / EVE-NG API helper for Terraform (external data source).

This script reads a JSON object from stdin (Terraform external provider "query"),
performs one action, then prints a JSON object to stdout.

Actions are implemented in an idempotent way: "ensure_*" returns existing IDs
when resources already exist.
"""

from __future__ import annotations

import json
import os
import ssl
import sys
import uuid
from dataclasses import dataclass
from pathlib import PurePosixPath
from typing import Any
from urllib.parse import quote, urljoin
from urllib.request import HTTPCookieProcessor, HTTPSHandler, Request, build_opener
import http.cookiejar
import urllib.error


def parse_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "y", "on"}:
        return True
    if normalized in {"0", "false", "no", "n", "off"}:
        return False
    return default


def fail(message: str) -> None:
    print(f"[ERROR] {message}", file=sys.stderr)
    raise SystemExit(1)


def read_query() -> dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    return json.loads(raw)


def jsend_data(payload: Any) -> Any:
    if isinstance(payload, dict) and "data" in payload:
        return payload["data"]
    return payload


def normalize_lab_path(lab_path: str) -> str:
    value = (lab_path or "").strip()
    if not value:
        fail("lab_path is required")
    return value.lstrip("/")


def encode_lab_path(lab_path: str) -> str:
    return quote(normalize_lab_path(lab_path), safe="/")


def split_lab_for_create(lab_path: str) -> tuple[str, str]:
    posix = PurePosixPath("/" + normalize_lab_path(lab_path))
    lab_name = posix.stem
    folder = str(posix.parent)
    if folder == ".":
        folder = "/"
    return folder, lab_name


@dataclass
class PnetClient:
    base_url: str
    username: str
    password: str
    validate_certs: bool

    def __post_init__(self) -> None:
        self.base_url = self.base_url.rstrip("/") + "/"
        self._cookie_jar = http.cookiejar.CookieJar()

        context = ssl.create_default_context()
        if not self.validate_certs:
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
        self._ssl_context = context
        self._opener = build_opener(
            HTTPCookieProcessor(self._cookie_jar),
            HTTPSHandler(context=self._ssl_context),
        )

    def request(self, method: str, path: str, payload: dict | None = None) -> tuple[int, Any]:
        url = urljoin(self.base_url, path.lstrip("/"))
        data = None
        headers = {"Accept": "application/json"}
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"

        req = Request(url=url, data=data, method=method.upper(), headers=headers)
        try:
            with self._opener.open(req, timeout=30) as resp:
                status = int(resp.status)
                raw = resp.read()
                ctype = (resp.headers.get("Content-Type") or "").lower()
                if raw and "json" in ctype:
                    return status, json.loads(raw.decode("utf-8", errors="replace"))
                if raw:
                    return status, raw.decode("utf-8", errors="replace")
                return status, None
        except urllib.error.HTTPError as err:
            status = int(err.code)
            raw = err.read()
            ctype = (err.headers.get("Content-Type") or "").lower()
            if raw and "json" in ctype:
                try:
                    return status, json.loads(raw.decode("utf-8", errors="replace"))
                except json.JSONDecodeError:
                    return status, None
            return status, None

    def login(self) -> None:
        status, payload = self.request(
            "POST",
            "/api/auth/login",
            {"username": self.username, "password": self.password},
        )
        if status != 200:
            fail(f"PNET API login failed (status={status}). Check pnet_api_user/pnet_api_password.")

        if isinstance(payload, dict) and payload.get("status") not in {None, "success"}:
            fail("PNET API login failed (unexpected payload).")

    def get_lab(self, lab_path: str) -> dict[str, Any] | None:
        encoded = encode_lab_path(lab_path)
        status, payload = self.request("GET", f"/api/labs/{encoded}")
        if status == 404:
            return None
        if status != 200:
            fail(f"GET lab failed (status={status}) for {lab_path}")
        data = jsend_data(payload)
        if not isinstance(data, dict):
            fail("GET lab returned unexpected data.")
        return data

    def create_lab(self, lab_path: str) -> dict[str, Any]:
        folder, name = split_lab_for_create(lab_path)
        status, payload = self.request(
            "POST",
            "/api/labs",
            {
                "path": folder,
                "name": name,
                "version": "1",
                "author": self.username,
                "description": "",
                "body": "",
            },
        )
        if status not in {200, 201}:
            fail(f"Create lab failed (status={status}) for {lab_path}")
        data = jsend_data(payload)
        if isinstance(data, dict):
            return data
        return {}

    def ensure_lab(self, lab_path: str) -> dict[str, str]:
        lab = self.get_lab(lab_path)
        if lab is None:
            self.create_lab(lab_path)
            lab = self.get_lab(lab_path)

        if not lab:
            fail("ensure_lab could not resolve lab after create.")

        lab_id = str(lab.get("id") or "").strip()
        if not lab_id:
            fail("Lab id missing from API response.")

        return {"lab_id": lab_id, "lab_path": normalize_lab_path(lab_path)}

    def list_networks(self, lab_path: str) -> dict[str, Any]:
        encoded = encode_lab_path(lab_path)
        status, payload = self.request("GET", f"/api/labs/{encoded}/networks")
        if status != 200:
            fail(f"List networks failed (status={status})")
        data = jsend_data(payload)
        if isinstance(data, dict):
            return data
        return {}

    def ensure_network(self, lab_path: str, name: str, net_type: str) -> dict[str, str]:
        networks = self.list_networks(lab_path)
        for net_id, net in networks.items():
            if isinstance(net, dict) and str(net.get("name") or "") == name:
                return {"network_id": str(net_id), "network_name": name}

        encoded = encode_lab_path(lab_path)
        status, _ = self.request(
            "POST",
            f"/api/labs/{encoded}/networks",
            {"name": name, "type": net_type, "left": "35%", "top": "25%"},
        )
        if status not in {200, 201}:
            fail(f"Create network failed (status={status})")

        networks = self.list_networks(lab_path)
        for net_id, net in networks.items():
            if isinstance(net, dict) and str(net.get("name") or "") == name:
                return {"network_id": str(net_id), "network_name": name}

        fail("ensure_network could not find network after create.")
        raise AssertionError

    def list_nodes(self, lab_path: str) -> dict[str, Any]:
        encoded = encode_lab_path(lab_path)
        status, payload = self.request("GET", f"/api/labs/{encoded}/nodes")
        if status != 200:
            fail(f"List nodes failed (status={status})")
        data = jsend_data(payload)
        if isinstance(data, dict):
            return data
        return {}

    def ensure_node(
        self,
        lab_path: str,
        node_name: str,
        template: str,
        image: str,
        cpu: int,
        ram: int,
        ethernet: int,
    ) -> dict[str, str]:
        nodes = self.list_nodes(lab_path)
        for node_id, node in nodes.items():
            if isinstance(node, dict) and str(node.get("name") or "") == node_name:
                return {"node_id": str(node_id), "node_name": node_name}

        encoded = encode_lab_path(lab_path)
        status, payload = self.request(
            "POST",
            f"/api/labs/{encoded}/nodes",
            {
                "type": "qemu",
                "template": template,
                "image": image,
                "name": node_name,
                "cpu": cpu,
                "ram": ram,
                "ethernet": ethernet,
                "console": "vnc",
                "delay": 0,
                "icon": "Server.png",
                "left": "25%",
                "top": "25%",
                "config": "Unconfigured",
                "uuid": str(uuid.uuid4()),
            },
        )
        if status not in {200, 201}:
            fail(f"Create node failed (status={status})")

        data = jsend_data(payload)
        if isinstance(data, dict) and data.get("id") is not None:
            return {"node_id": str(data["id"]), "node_name": node_name}

        # fallback: list again
        nodes = self.list_nodes(lab_path)
        for node_id, node in nodes.items():
            if isinstance(node, dict) and str(node.get("name") or "") == node_name:
                return {"node_id": str(node_id), "node_name": node_name}

        fail("ensure_node could not find node after create.")
        raise AssertionError

    def update_node_interface(
        self,
        lab_path: str,
        node_id: str,
        interface_index: str,
        network_id: str,
    ) -> dict[str, str]:
        encoded = encode_lab_path(lab_path)
        try:
            iface = int(str(interface_index))
        except ValueError:
            fail("interface_index must be an integer")

        network_value: Any = network_id
        if str(network_id).isdigit():
            network_value = int(network_id)

        status, _ = self.request(
            "PUT",
            f"/api/labs/{encoded}/nodes/{node_id}/interfaces",
            {str(iface): network_value},
        )
        if status not in {200, 201}:
            fail(f"Update node interface failed (status={status})")
        return {"node_id": str(node_id), "interface_index": str(iface), "network_id": str(network_id)}

    def node_power(self, action: str, lab_path: str, node_id: str) -> dict[str, str]:
        encoded = encode_lab_path(lab_path)
        status, _ = self.request("GET", f"/api/labs/{encoded}/nodes/{node_id}/{action}")
        if status not in {200, 201}:
            fail(f"{action} node failed (status={status})")
        return {"node_id": str(node_id), "action": action}


def main() -> int:
    query = read_query()
    action = str(query.get("action") or "").strip()
    if not action:
        fail("action is required")

    api_url = str(query.get("api_url") or os.environ.get("PNET_API_URL") or "").strip()
    api_user = str(query.get("api_user") or os.environ.get("PNET_API_USER") or "").strip()
    api_password = str(query.get("api_password") or os.environ.get("PNET_API_PASSWORD") or "").strip()

    if not api_url or not api_user or not api_password:
        fail("Missing API credentials. Set pnet_api_url/pnet_api_user/pnet_api_password.")

    validate_certs = parse_bool(
        str(query.get("validate_certs") or os.environ.get("PNET_VALIDATE_CERTS") or "false"),
        False,
    )

    client = PnetClient(
        base_url=api_url,
        username=api_user,
        password=api_password,
        validate_certs=validate_certs,
    )
    client.login()

    result: dict[str, str]
    if action == "ensure_lab":
        lab_path = str(query.get("lab_path") or "")
        result = client.ensure_lab(lab_path)
    elif action == "ensure_network":
        lab_path = str(query.get("lab_path") or "")
        network_name = str(query.get("network_name") or "")
        network_type = str(query.get("network_type") or "")
        if not network_name or not network_type:
            fail("network_name and network_type are required")
        result = client.ensure_network(lab_path, network_name, network_type)
    elif action == "ensure_node":
        lab_path = str(query.get("lab_path") or "")
        node_name = str(query.get("node_name") or "")
        template = str(query.get("template") or "linux")
        image = str(query.get("image") or "")
        if not node_name or not image:
            fail("node_name and image are required")
        cpu = int(str(query.get("cpu") or "4"))
        ram = int(str(query.get("ram") or "8192"))
        ethernet = int(str(query.get("ethernet") or "1"))
        result = client.ensure_node(lab_path, node_name, template, image, cpu, ram, ethernet)
    elif action == "update_node_interface":
        lab_path = str(query.get("lab_path") or "")
        node_id = str(query.get("node_id") or "")
        interface_index = str(query.get("interface_index") or "")
        network_id = str(query.get("network_id") or "")
        if not lab_path or not node_id or not interface_index or not network_id:
            fail("lab_path/node_id/interface_index/network_id are required")
        result = client.update_node_interface(lab_path, node_id, interface_index, network_id)
    elif action in {"start_node", "stop_node", "wipe_node"}:
        lab_path = str(query.get("lab_path") or "")
        node_id = str(query.get("node_id") or "")
        if not lab_path or not node_id:
            fail("lab_path and node_id are required")
        action_name = action.replace("_node", "")
        result = client.node_power(action_name, lab_path, node_id)
    else:
        fail(f"Unsupported action: {action}")

    sys.stdout.write(json.dumps(result))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        raise SystemExit(1)
