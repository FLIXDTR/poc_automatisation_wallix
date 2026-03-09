#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import subprocess
import sys
from urllib.parse import urlparse


def read_terraform_outputs(terraform_dir: pathlib.Path) -> dict:
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


def extract_value(outputs: dict, key: str):
    value = outputs.get(key)
    if isinstance(value, dict) and "value" in value:
        return value["value"]
    return value


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate Ansible inventory from terraform output -json."
    )
    parser.add_argument(
        "--terraform-dir",
        default="terraform",
        help="Directory containing Terraform state (default: terraform).",
    )
    parser.add_argument(
        "--output",
        default="ansible/inventory/generated/hosts.yml",
        help="Output inventory file path.",
    )
    parser.add_argument(
        "--host-alias",
        default="wallix-bastion",
        help="Host alias used in generated inventory.",
    )
    parser.add_argument(
        "--api-url",
        default="",
        help="Override wallix_api_url value in inventory vars.",
    )
    parser.add_argument(
        "--bastion-host",
        default="",
        help="Use explicit Bastion host/IP and skip terraform output lookup.",
    )
    parser.add_argument(
        "--bastion-url",
        default="",
        help="Use explicit Bastion base URL and skip terraform output lookup.",
    )
    args = parser.parse_args()

    output_path = pathlib.Path(args.output).resolve()

    bastion_ip = args.bastion_host.strip()
    bastion_url = args.bastion_url.strip()

    if not bastion_ip and not bastion_url:
        terraform_dir = pathlib.Path(args.terraform_dir).resolve()
        outputs = read_terraform_outputs(terraform_dir)
        bastion_ip = str(extract_value(outputs, "bastion_ip") or "").strip()
        bastion_url = str(extract_value(outputs, "bastion_url") or "").strip()

    if not bastion_ip and bastion_url:
        parsed = urlparse(bastion_url)
        bastion_ip = parsed.hostname or ""

    if not bastion_ip:
        raise RuntimeError(
            "Cannot determine bastion IP/hostname from Terraform outputs."
        )

    wallix_api_url = (
        args.api_url.strip()
        or os.environ.get("WALLIX_API_URL", "").strip()
        or bastion_url
        or f"https://{bastion_ip}"
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    yaml_content = f"""all:
  children:
    wallix_bastion:
      hosts:
        {args.host_alias}:
          ansible_host: {bastion_ip}
      vars:
        wallix_api_url: "{wallix_api_url}"
"""
    output_path.write_text(yaml_content, encoding="utf-8")

    print(f"Inventory written to: {output_path}")
    print(f"Host: {args.host_alias} -> {bastion_ip}")
    print(f"wallix_api_url: {wallix_api_url}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        raise SystemExit(1)
