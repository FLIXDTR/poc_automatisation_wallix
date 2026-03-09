#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SECRETS_FILE="${1:-${REPO_ROOT}/secrets_pnetlab.env}"

if [[ ! -f "${SECRETS_FILE}" ]]; then
  echo "Secrets file not found: ${SECRETS_FILE}" >&2
  echo "Create it from: ${REPO_ROOT}/secrets_pnetlab.env.example" >&2
  exit 1
fi

echo "==> Loading secrets: ${SECRETS_FILE}"
set -a
# shellcheck disable=SC1090
source "${SECRETS_FILE}"
set +a

# Provide env vars expected by SSH helper scripts (prepare_image/commit_template)
export PNET_SSH_HOST="${PNET_SSH_HOST:-${TF_VAR_pnet_ssh_host:-}}"
export PNET_SSH_USER="${PNET_SSH_USER:-${TF_VAR_pnet_ssh_user:-root}}"
export PNET_SSH_PASSWORD="${PNET_SSH_PASSWORD:-${TF_VAR_pnet_ssh_password:-}}"
export PNET_SSH_KEY_PATH="${PNET_SSH_KEY_PATH:-${TF_VAR_pnet_ssh_key_path:-}}"
export PNET_SSH_PORT="${PNET_SSH_PORT:-22}"
export PNET_SESSION_ID="${PNET_SESSION_ID:-${TF_VAR_pnet_session_id:-1}}"

if [[ -z "${PNET_SSH_HOST}" ]]; then
  echo "Missing PNET SSH host. Set TF_VAR_pnet_ssh_host (or PNET_SSH_HOST)." >&2
  exit 1
fi

echo "==> Terraform apply (PNETLab)"
terraform -chdir="${REPO_ROOT}/terraform/pnetlab" init
terraform -chdir="${REPO_ROOT}/terraform/pnetlab" fmt -check
terraform -chdir="${REPO_ROOT}/terraform/pnetlab" validate
terraform -chdir="${REPO_ROOT}/terraform/pnetlab" apply -auto-approve ${TF_APPLY_ARGS:-}

echo "==> Terraform outputs (summary)"
if command -v jq >/dev/null 2>&1; then
  terraform -chdir="${REPO_ROOT}/terraform/pnetlab" output -json | jq -r '
    def v($k): .[$k].value // .[$k] // "";
    "bastion_ip=" + (v("bastion_ip")|tostring),
    "bastion_url=" + (v("bastion_url")|tostring),
    "wallix_template_ready=" + (v("wallix_template_ready")|tostring),
    "wallix_build_skipped=" + (v("wallix_build_skipped")|tostring)
  '
else
  terraform -chdir="${REPO_ROOT}/terraform/pnetlab" output
fi

echo "==> Generate Ansible inventory from Terraform outputs"
if [[ "${SKIP_INVENTORY:-false}" == "true" ]]; then
  echo "SKIP_INVENTORY=true -> skipping inventory generation"
else
  python3 "${REPO_ROOT}/scripts/generate_inventory.py" \
    --terraform-dir "${REPO_ROOT}/terraform/pnetlab" \
    --output "${REPO_ROOT}/ansible/inventory/generated/hosts.yml"
fi

echo "==> Ansible (API configuration)"
if [[ "${SKIP_ANSIBLE:-false}" == "true" ]]; then
  echo "SKIP_ANSIBLE=true -> skipping Ansible"
else
  pushd "${REPO_ROOT}/ansible" >/dev/null
  ansible-galaxy collection install -r requirements.yml
  ansible-playbook -i inventory/generated/hosts.yml playbooks/bootstrap.yml
  ansible-playbook -i inventory/generated/hosts.yml playbooks/configure.yml

  # After configure.yml, the admin password is expected to be rotated to WALLIX_ADMIN_NEW_PASSWORD.
  # Reuse it as WALLIX_API_PASSWORD for subsequent playbooks in the same run to avoid manual edits.
  if [[ -n "${WALLIX_ADMIN_NEW_PASSWORD:-}" ]]; then
    export WALLIX_API_PASSWORD="${WALLIX_ADMIN_NEW_PASSWORD}"
  fi

  if [[ "${WALLIX_ASSETS_ENABLED:-false}" == "true" ]]; then
    ansible-playbook -i inventory/generated/hosts.yml playbooks/assets.yml
  else
    echo "WALLIX_ASSETS_ENABLED=false -> skipping assets (devices/groups/authorizations)"
  fi
  popd >/dev/null
fi

echo "==> Smoke tests"
if [[ "${SKIP_SMOKE:-false}" == "true" ]]; then
  echo "SKIP_SMOKE=true -> skipping smoke tests"
else
  python3 "${REPO_ROOT}/scripts/smoke_test.py" --terraform-dir "${REPO_ROOT}/terraform/pnetlab"
fi

echo "Done."
