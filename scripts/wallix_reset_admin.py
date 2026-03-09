#!/usr/bin/env python3
import argparse
import sys
import time
from dataclasses import dataclass


def sh_single_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


@dataclass(frozen=True)
class SshTarget:
    host: str
    port: int
    username: str
    ssh_password: str
    super_password: str


def run_wabrestore_default_admin(target: SshTarget, new_admin_password: str) -> None:
    try:
        import paramiko  # type: ignore
    except Exception as exc:  # pragma: no cover
        raise RuntimeError(
            "Missing dependency: paramiko. Install it (e.g. python3-paramiko) on the runner."
        ) from exc

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        target.host,
        port=target.port,
        username=target.username,
        password=target.ssh_password,
        timeout=10,
        auth_timeout=10,
        banner_timeout=10,
    )

    admin_pw_quoted = sh_single_quote(new_admin_password)
    inner = (
        f"printf '%s\\n' {admin_pw_quoted} | "
        "/opt/wab/bin/WABRestoreDefaultAdmin -c -q --unsafe-no-password-change"
    )
    inner_escaped = inner.replace('"', '\\"')
    command = f'/opt/wab/bin/WABSuper "{inner_escaped}"'

    stdin, stdout, stderr = client.exec_command(command, get_pty=True)

    sent_password = False
    output = ""
    start = time.time()
    while True:
        if stdout.channel.recv_ready():
            output += stdout.channel.recv(4096).decode("utf-8", errors="ignore")

        if (not sent_password) and ("password" in output.lower()):
            stdin.write(target.super_password + "\n")
            stdin.flush()
            sent_password = True

        if stdout.channel.exit_status_ready():
            break

        if time.time() - start > 45:
            raise RuntimeError("Timed out while running WABRestoreDefaultAdmin over SSH.")

        time.sleep(0.1)

    exit_status = int(stdout.channel.recv_exit_status())
    output += stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    client.close()

    combined = (output + "\n" + err).strip()
    if exit_status != 0:
        raise RuntimeError(
            "Failed to reset WALLIX 'admin' account via WABRestoreDefaultAdmin.\n"
            f"Exit status: {exit_status}\n"
            f"Output:\n{combined}"
        )

    if "authentication failure" in combined.lower() or "sorry" in combined.lower():
        raise RuntimeError(
            "WABSuper sudo authentication failed (wrong WALLIX super password?).\n"
            f"Output:\n{combined}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Reset WALLIX Bastion web/API 'admin' password using management SSH (port 2242) "
            "and the built-in WABRestoreDefaultAdmin command."
        )
    )
    parser.add_argument("--host", required=True, help="WALLIX Bastion IP/hostname.")
    parser.add_argument("--port", type=int, default=2242, help="SSH port (default: 2242).")
    parser.add_argument(
        "--user",
        default="wabadmin",
        help="SSH username (default: wabadmin).",
    )
    parser.add_argument("--ssh-password", required=True, help="SSH password for --user.")
    parser.add_argument(
        "--super-password",
        default="",
        help="Password used when WABSuper prompts for sudo (defaults to --ssh-password).",
    )
    parser.add_argument(
        "--admin-password",
        required=True,
        help="New password to set for the WALLIX web/API account 'admin'.",
    )
    args = parser.parse_args()

    super_password = args.super_password or args.ssh_password
    target = SshTarget(
        host=args.host,
        port=int(args.port),
        username=args.user,
        ssh_password=args.ssh_password,
        super_password=super_password,
    )

    run_wabrestore_default_admin(target=target, new_admin_password=args.admin_password)
    print("OK: admin password reset applied")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        raise SystemExit(1)

