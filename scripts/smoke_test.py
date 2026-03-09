#!/usr/bin/env python3
import argparse
import base64
import json
import os
import pathlib
import ssl
import subprocess
import sys
import urllib.error
import urllib.request


def run_terraform_output(terraform_dir: pathlib.Path) -> dict:
    process = subprocess.run(
        ["terraform", "output", "-json"],
        cwd=str(terraform_dir),
        check=False,
        capture_output=True,
        text=True,
    )
    if process.returncode != 0:
        raise RuntimeError(f"terraform output failed:\n{process.stderr.strip()}")
    return json.loads(process.stdout)


def extract(outputs: dict, key: str) -> str:
    value = outputs.get(key)
    if isinstance(value, dict) and "value" in value:
        value = value["value"]
    return str(value or "").strip()


def parse_bool(value: str, default: bool = False) -> bool:
    if value is None:
        return default
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "y", "on"}:
        return True
    if normalized in {"0", "false", "no", "n", "off"}:
        return False
    return default


def request_url(
    url: str,
    method: str = "GET",
    payload: dict | None = None,
    headers: dict | None = None,
    context: ssl.SSLContext | None = None,
) -> int:
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url=url,
        data=data,
        method=method,
        headers=headers or {},
    )
    try:
        with urllib.request.urlopen(request, context=context, timeout=20) as response:
            return int(response.status)
    except urllib.error.HTTPError as error:
        return int(error.code)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run minimal WALLIX smoke tests.")
    parser.add_argument(
        "--terraform-dir",
        default="terraform",
        help="Terraform working directory.",
    )
    parser.add_argument(
        "--bastion-url",
        default="",
        help="Bastion URL override (skip terraform output lookup).",
    )
    args = parser.parse_args()

    bastion_url = args.bastion_url.strip()
    if not bastion_url:
        terraform_dir = pathlib.Path(args.terraform_dir).resolve()
        outputs = run_terraform_output(terraform_dir)
        bastion_url = extract(outputs, "bastion_url")

    if not bastion_url:
        raise RuntimeError("Terraform output bastion_url is empty.")

    validate_certs = parse_bool(os.environ.get("WALLIX_VALIDATE_CERTS", "false"), False)
    context = ssl.create_default_context()
    if not validate_certs:
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE

    root_status = request_url(
        url=f"{bastion_url.rstrip('/')}/",
        method="GET",
        context=context,
    )
    print(f"[SMOKE] HTTPS root status: {root_status}")
    if root_status not in {200, 301, 302, 401, 403}:
        raise RuntimeError(f"Unexpected HTTPS status {root_status} on {bastion_url}")

    api_user = os.environ.get("WALLIX_API_USER", "").strip()
    api_password = os.environ.get("WALLIX_API_PASSWORD", "").strip()
    api_new_password = os.environ.get("WALLIX_ADMIN_NEW_PASSWORD", "").strip()
    if not api_user or not api_password:
        raise RuntimeError("WALLIX_API_USER and WALLIX_API_PASSWORD are required.")

    password_candidates = [api_password]
    if api_new_password and api_new_password != api_password:
        password_candidates.append(api_new_password)

    endpoints = os.environ.get(
        "WALLIX_AUTH_ENDPOINTS", "/api/auth/login,/api/v1/auth/login,/api/login"
    )
    endpoint_list = [item.strip() for item in endpoints.split(",") if item.strip()]

    auth_ok = False
    for endpoint in endpoint_list:
        for password in password_candidates:
            status = request_url(
                url=f"{bastion_url.rstrip('/')}{endpoint}",
                method="POST",
                payload={"username": api_user, "password": password},
                headers={"Content-Type": "application/json"},
                context=context,
            )
            print(f"[SMOKE] Auth endpoint {endpoint} -> {status}")
            if status in {200, 201}:
                auth_ok = True
                break
        if auth_ok:
            break

    if not auth_ok:
        probe_endpoints = os.environ.get(
            "WALLIX_BASIC_AUTH_PROBE_ENDPOINTS", "/api/users,/api/v1/users,/api/version"
        )
        probe_list = [item.strip() for item in probe_endpoints.split(",") if item.strip()]

        for password in password_candidates:
            basic_header = base64.b64encode(f"{api_user}:{password}".encode("utf-8")).decode(
                "ascii"
            )
            for endpoint in probe_list:
                status = request_url(
                    url=f"{bastion_url.rstrip('/')}{endpoint}",
                    method="GET",
                    headers={"Authorization": f"Basic {basic_header}"},
                    context=context,
                )
                print(f"[SMOKE] Basic auth probe {endpoint} -> {status}")
                if status in {200, 201, 204}:
                    auth_ok = True
                    break
            if auth_ok:
                break

    if not auth_ok:
        raise RuntimeError(
            "Authentication failed on token endpoints and basic-auth probes."
        )

    print("[SMOKE] All checks passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        raise SystemExit(1)
