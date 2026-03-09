#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SECRETS_FILE=""
MODE=""
AUTO_APPROVE="false"

usage() {
  cat <<EOF
Usage: $0 [--secrets-file PATH] [--mode vsphere|local] [--auto-approve]

Defaults:
  --secrets-file: ./secrets_local.env if present, else ./.secrets.env
  --mode:         value from POC_MODE in secrets file (default: vsphere)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --secrets-file)
      SECRETS_FILE="${2:-}"; shift 2 ;;
    --mode)
      MODE="${2:-}"; shift 2 ;;
    --auto-approve)
      AUTO_APPROVE="true"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${SECRETS_FILE}" ]]; then
  if [[ -f "${REPO_ROOT}/secrets_local.env" ]]; then
    SECRETS_FILE="${REPO_ROOT}/secrets_local.env"
  else
    SECRETS_FILE="${REPO_ROOT}/.secrets.env"
  fi
fi

if [[ ! -f "${SECRETS_FILE}" ]]; then
  echo "Secrets file not found: ${SECRETS_FILE}" >&2
  echo "Create one from ${REPO_ROOT}/.secrets.env.example" >&2
  exit 1
fi

echo "==> Loading secrets: ${SECRETS_FILE}"
set -a
# shellcheck disable=SC1090
source "${SECRETS_FILE}"
set +a

if [[ -z "${MODE}" ]]; then
  MODE="${POC_MODE:-vsphere}"
fi
MODE="$(echo "${MODE}" | tr '[:upper:]' '[:lower:]')"

if [[ "${MODE}" != "vsphere" && "${MODE}" != "local" ]]; then
  echo "Invalid mode: ${MODE} (expected vsphere|local)" >&2
  exit 2
fi

INVENTORY_PATH="${REPO_ROOT}/ansible/inventory/generated/hosts.yml"

if [[ "${MODE}" == "vsphere" ]]; then
  echo "==> Terraform (vSphere)"
  pushd "${REPO_ROOT}/terraform" >/dev/null
  terraform init
  terraform fmt -check
  terraform validate
  terraform plan -out=tfplan
  if [[ "${AUTO_APPROVE}" == "true" ]]; then
    terraform apply -auto-approve tfplan
  else
    terraform apply tfplan
  fi
  popd >/dev/null

  echo "==> Generate dynamic Ansible inventory from Terraform outputs"
  python3 "${REPO_ROOT}/scripts/generate_inventory.py" \
    --terraform-dir "${REPO_ROOT}/terraform" \
    --output "${INVENTORY_PATH}"
else
  if [[ -z "${LOCAL_BASTION_HOST:-}" ]]; then
    echo "LOCAL_BASTION_HOST is required in local mode." >&2
    exit 1
  fi
  API_URL="${WALLIX_API_URL:-}"
  if [[ -z "${API_URL}" ]]; then
    API_URL="https://${LOCAL_BASTION_HOST}"
  fi

  echo "==> Local mode: skip Terraform and target existing Bastion (${LOCAL_BASTION_HOST})"
  python3 "${REPO_ROOT}/scripts/generate_inventory.py" \
    --output "${INVENTORY_PATH}" \
    --bastion-host "${LOCAL_BASTION_HOST}" \
    --api-url "${API_URL}"
fi

echo "==> Ansible (API configuration)"
pushd "${REPO_ROOT}/ansible" >/dev/null
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i "${INVENTORY_PATH}" playbooks/bootstrap.yml
ansible-playbook -i "${INVENTORY_PATH}" playbooks/configure.yml

# After configure.yml, the admin password is expected to be rotated to WALLIX_ADMIN_NEW_PASSWORD.
if [[ -n "${WALLIX_ADMIN_NEW_PASSWORD:-}" ]]; then
  export WALLIX_API_PASSWORD="${WALLIX_ADMIN_NEW_PASSWORD}"
fi

if [[ "${WALLIX_ASSETS_ENABLED:-false}" == "true" ]]; then
  ansible-playbook -i "${INVENTORY_PATH}" playbooks/assets.yml
else
  echo "WALLIX_ASSETS_ENABLED=false -> skipping assets (devices/groups/authorizations)"
fi
popd >/dev/null

echo "==> Smoke tests"
if [[ "${MODE}" == "vsphere" ]]; then
  python3 "${REPO_ROOT}/scripts/smoke_test.py" --terraform-dir "${REPO_ROOT}/terraform"
else
  python3 "${REPO_ROOT}/scripts/smoke_test.py" --bastion-url "${API_URL}"
fi

echo "PoC completed successfully."
