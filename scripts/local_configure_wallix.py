#!/usr/bin/env python3
import argparse
import base64
import json
import os
import ssl
import sys
import urllib.error
import urllib.request


def parse_bool(value: str, default: bool = False) -> bool:
    if value is None:
        return default
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "y", "on"}:
        return True
    if normalized in {"0", "false", "no", "n", "off"}:
        return False
    return default


def parse_list(value: str) -> list[str]:
    if value is None:
        return []
    raw = value.strip()
    if not raw:
        return []

    if raw.startswith("["):
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                return [str(item).strip() for item in parsed if str(item).strip()]
        except json.JSONDecodeError:
            pass

    return [item.strip() for item in raw.split(",") if item.strip()]


def build_basic_headers(api_user: str, api_password: str) -> dict[str, str]:
    basic_token = base64.b64encode(f"{api_user}:{api_password}".encode("utf-8")).decode(
        "ascii"
    )
    return {"Authorization": f"Basic {basic_token}"}


def request_url(
    url: str,
    method: str,
    context: ssl.SSLContext,
    payload: dict | None = None,
    headers: dict | None = None,
) -> tuple[int, dict | None]:
    body = None
    request_headers = dict(headers or {})
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        request_headers.setdefault("Content-Type", "application/json")

    request = urllib.request.Request(
        url=url,
        data=body,
        method=method,
        headers=request_headers,
    )
    try:
        with urllib.request.urlopen(request, context=context, timeout=20) as response:
            status = int(response.status)
            content_type = response.headers.get("Content-Type", "")
            raw = response.read()
            if "json" in content_type.lower() and raw:
                return status, json.loads(raw.decode("utf-8", errors="replace"))
            return status, None
    except urllib.error.HTTPError as error:
        status = int(error.code)
        raw = error.read()
        content_type = error.headers.get("Content-Type", "")
        if "json" in content_type.lower() and raw:
            try:
                return status, json.loads(raw.decode("utf-8", errors="replace"))
            except json.JSONDecodeError:
                return status, None
        return status, None


def can_auth_with_basic(api_url: str, basic_headers: dict[str, str], context: ssl.SSLContext) -> bool:
    status, _ = request_url(
        url=f"{api_url}/api/users",
        method="GET",
        headers=basic_headers,
        context=context,
    )
    return status == 200


def try_token_auth(
    api_url: str,
    api_user: str,
    api_password: str,
    context: ssl.SSLContext,
) -> dict:
    endpoints = os.environ.get(
        "WALLIX_AUTH_ENDPOINTS", "/api/auth/login,/api/v1/auth/login,/api/login"
    )
    endpoint_list = [item.strip() for item in endpoints.split(",") if item.strip()]

    for endpoint in endpoint_list:
        status, payload = request_url(
            url=f"{api_url}{endpoint}",
            method="POST",
            payload={"username": api_user, "password": api_password},
            context=context,
        )
        print(f"[LOCAL-FALLBACK] Auth endpoint {endpoint} -> {status}")
        if status not in {200, 201}:
            continue

        token = ""
        if isinstance(payload, dict):
            token = (
                str(payload.get("token") or "")
                or str(payload.get("access_token") or "")
                or str(payload.get("jwt") or "")
                or str(payload.get("session_token") or "")
            ).strip()

        if token:
            print("[LOCAL-FALLBACK] Token auth selected")
            return {"Authorization": f"Bearer {token}"}

    return {}


def run_operation(
    api_url: str,
    operation_name: str,
    method: str,
    paths: list[str],
    payload: dict,
    expected_status: set[int],
    preferred_headers: dict,
    basic_headers: dict,
    allow_basic_fallback: bool,
    context: ssl.SSLContext,
) -> bool:
    for path in paths:
        candidates = [preferred_headers]
        if allow_basic_fallback and preferred_headers != basic_headers:
            candidates.append(basic_headers)

        for headers in candidates:
            status, _ = request_url(
                url=f"{api_url}{path}",
                method=method,
                payload=payload,
                headers=headers,
                context=context,
            )
            auth_mode = "basic" if headers == basic_headers else "token"
            print(
                f"[LOCAL-FALLBACK] {operation_name} -> {method} {path} "
                f"[{auth_mode}] => {status}"
            )
            if status in expected_status:
                return True

    return False


def run_rotate_password(
    api_url: str,
    api_user: str,
    current_password: str,
    new_password: str,
    preferred_headers: dict,
    basic_headers: dict,
    allow_basic_fallback: bool,
    context: ssl.SSLContext,
) -> bool:
    candidates = [
        {
            "method": "PUT",
            "path": f"/api/users/{api_user}",
            "payload": {"password": new_password},
            "expected": {200, 204},
        },
        {
            "method": "PUT",
            "path": f"/api/users/{api_user}/",
            "payload": {"password": new_password},
            "expected": {200, 204},
        },
        {
            "method": "POST",
            "path": "/api/v1/users/password",
            "payload": {
                "username": api_user,
                "current_password": current_password,
                "new_password": new_password,
            },
            "expected": {200, 201, 204},
        },
        {
            "method": "POST",
            "path": "/api/users/password",
            "payload": {
                "username": api_user,
                "current_password": current_password,
                "new_password": new_password,
            },
            "expected": {200, 201, 204},
        },
        {
            "method": "POST",
            "path": "/rest/users/password",
            "payload": {
                "username": api_user,
                "current_password": current_password,
                "new_password": new_password,
            },
            "expected": {200, 201, 204},
        },
    ]

    for candidate in candidates:
        headers_to_try = [preferred_headers]
        if allow_basic_fallback and preferred_headers != basic_headers:
            headers_to_try.append(basic_headers)

        for headers in headers_to_try:
            status, _ = request_url(
                url=f"{api_url}{candidate['path']}",
                method=candidate["method"],
                payload=candidate["payload"],
                headers=headers,
                context=context,
            )
            auth_mode = "basic" if headers == basic_headers else "token"
            print(
                "[LOCAL-FALLBACK] Rotate admin password -> "
                f"{candidate['method']} {candidate['path']} [{auth_mode}] => {status}"
            )
            if status in candidate["expected"]:
                return True

    return False


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Direct WALLIX API fallback for local mode when Ansible/WSL is unavailable."
    )
    parser.add_argument(
        "--bastion-url",
        default="",
        help="WALLIX base URL. Defaults to WALLIX_API_URL env var.",
    )
    args = parser.parse_args()

    api_url = (args.bastion_url or os.environ.get("WALLIX_API_URL", "")).strip()
    if not api_url:
        raise RuntimeError("Missing WALLIX_API_URL / --bastion-url.")
    api_url = api_url.rstrip("/")

    api_user = os.environ.get("WALLIX_API_USER", "").strip()
    api_password = os.environ.get("WALLIX_API_PASSWORD", "").strip()
    admin_new_password = os.environ.get("WALLIX_ADMIN_NEW_PASSWORD", "").strip()
    if not api_user or not api_password or not admin_new_password:
        raise RuntimeError(
            "Missing WALLIX_API_USER, WALLIX_API_PASSWORD or WALLIX_ADMIN_NEW_PASSWORD."
        )

    validate_certs = parse_bool(os.environ.get("WALLIX_VALIDATE_CERTS", "false"), False)
    allow_basic_fallback = parse_bool(
        os.environ.get("WALLIX_USE_BASIC_AUTH_FALLBACK", "true"), True
    )
    strict_mode = parse_bool(os.environ.get("WALLIX_LOCAL_STRICT", "false"), False)

    context = ssl.create_default_context()
    if not validate_certs:
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE

    basic_headers = build_basic_headers(api_user=api_user, api_password=api_password)
    active_api_password = api_password
    if not can_auth_with_basic(api_url=api_url, basic_headers=basic_headers, context=context):
        if admin_new_password and admin_new_password != api_password:
            alternate_headers = build_basic_headers(
                api_user=api_user,
                api_password=admin_new_password,
            )
            if can_auth_with_basic(
                api_url=api_url,
                basic_headers=alternate_headers,
                context=context,
            ):
                basic_headers = alternate_headers
                active_api_password = admin_new_password
                print(
                    "[LOCAL-FALLBACK] Active password detected from WALLIX_ADMIN_NEW_PASSWORD "
                    "(rotation already applied previously)"
                )
            else:
                raise RuntimeError(
                    "Cannot authenticate with WALLIX_API_PASSWORD or WALLIX_ADMIN_NEW_PASSWORD."
                )
        else:
            raise RuntimeError("Cannot authenticate with WALLIX_API_PASSWORD.")

    preferred_headers = try_token_auth(
        api_url=api_url,
        api_user=api_user,
        api_password=active_api_password,
        context=context,
    )
    if not preferred_headers:
        if not allow_basic_fallback:
            raise RuntimeError("Token authentication failed and basic fallback is disabled.")
        preferred_headers = basic_headers
        print("[LOCAL-FALLBACK] Token auth unavailable, basic-auth fallback selected")

    timezone = os.environ.get("WALLIX_TIMEZONE", "UTC").strip() or "UTC"
    dns_servers = parse_list(os.environ.get("WALLIX_DNS_SERVERS", ""))
    ntp_servers = parse_list(os.environ.get("WALLIX_NTP_SERVERS", ""))
    backup_target = os.environ.get("WALLIX_BACKUP_TARGET", "").strip()

    operations: list[dict] = [
        {
            "name": "Configure timezone/dns/ntp",
            "method": "PATCH",
            "paths": ["/api/v1/system/settings", "/api/system/settings", "/rest/system/settings"],
            "payload": {
                "timezone": timezone,
                "dns_servers": dns_servers,
                "ntp_servers": ntp_servers,
            },
            "expected": {200, 204},
            "enabled": True,
        },
        {
            "name": "Configure backup target",
            "method": "PATCH",
            "paths": ["/api/v1/backup/settings", "/api/backup/settings"],
            "payload": {"target": backup_target},
            "expected": {200, 204},
            "enabled": bool(backup_target),
        },
    ]

    failed = []
    for operation in operations:
        if not operation["enabled"]:
            print(f"[LOCAL-FALLBACK] Skip: {operation['name']}")
            continue

        ok = run_operation(
            api_url=api_url,
            operation_name=operation["name"],
            method=operation["method"],
            paths=operation["paths"],
            payload=operation["payload"],
            expected_status=operation["expected"],
            preferred_headers=preferred_headers,
            basic_headers=basic_headers,
            allow_basic_fallback=allow_basic_fallback,
            context=context,
        )
        if ok:
            print(f"[LOCAL-FALLBACK] Success: {operation['name']}")
        else:
            print(f"[LOCAL-FALLBACK] Warning: no endpoint accepted {operation['name']}")
            failed.append(operation["name"])

    if admin_new_password == active_api_password:
        print("[LOCAL-FALLBACK] Skip: Rotate admin password (already active)")
    else:
        rotation_ok = run_rotate_password(
            api_url=api_url,
            api_user=api_user,
            current_password=active_api_password,
            new_password=admin_new_password,
            preferred_headers=preferred_headers,
            basic_headers=basic_headers,
            allow_basic_fallback=allow_basic_fallback,
            context=context,
        )
        post_rotation_headers = build_basic_headers(
            api_user=api_user,
            api_password=admin_new_password,
        )
        if rotation_ok or can_auth_with_basic(
            api_url=api_url,
            basic_headers=post_rotation_headers,
            context=context,
        ):
            print("[LOCAL-FALLBACK] Success: Rotate admin password")
        else:
            print("[LOCAL-FALLBACK] Warning: no endpoint accepted Rotate admin password")
            failed.append("Rotate admin password")

    if failed and strict_mode:
        raise RuntimeError(
            "Strict mode enabled and operations failed: " + ", ".join(failed)
        )

    print("[LOCAL-FALLBACK] Completed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        raise SystemExit(1)
