#!/usr/bin/env bash
set -euo pipefail

LOCAL_LAB_FILE="${1:-}"
LAB_REL_PATH="${2:-}"

if [[ -z "${LOCAL_LAB_FILE}" || -z "${LAB_REL_PATH}" ]]; then
  echo "Usage: $0 <local_lab_file.unl> <lab_rel_path>" >&2
  echo "Example: $0 ./build_lab.generated.unl User1/Wallix-Auto.unl" >&2
  exit 2
fi

if [[ ! -f "${LOCAL_LAB_FILE}" ]]; then
  echo "Local lab file not found: ${LOCAL_LAB_FILE}" >&2
  exit 1
fi

: "${PNET_SSH_HOST:?PNET_SSH_HOST is required}"
PNET_SSH_USER="${PNET_SSH_USER:-root}"
PNET_SSH_PORT="${PNET_SSH_PORT:-22}"
PNET_SSH_PASSWORD="${PNET_SSH_PASSWORD:-}"
PNET_SSH_KEY_PATH="${PNET_SSH_KEY_PATH:-}"

ssh_base=(ssh -p "${PNET_SSH_PORT}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
scp_base=(scp -P "${PNET_SSH_PORT}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

if [[ -n "${PNET_SSH_KEY_PATH}" ]]; then
  ssh_base+=(-i "${PNET_SSH_KEY_PATH}")
  scp_base+=(-i "${PNET_SSH_KEY_PATH}")
elif [[ -n "${PNET_SSH_PASSWORD}" ]]; then
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "PNET_SSH_PASSWORD is set but sshpass is missing. Install sshpass on the runner." >&2
    exit 1
  fi
  ssh_base=(sshpass -p "${PNET_SSH_PASSWORD}" "${ssh_base[@]}")
  scp_base=(sshpass -p "${PNET_SSH_PASSWORD}" "${scp_base[@]}")
else
  echo "Provide either PNET_SSH_KEY_PATH or PNET_SSH_PASSWORD." >&2
  exit 1
fi

remote_lab="/opt/unetlab/labs/${LAB_REL_PATH}"
remote_dir="$(dirname "${remote_lab}")"

echo "==> Uploading lab: ${LAB_REL_PATH}"
echo "  -> ${remote_lab}"

"${ssh_base[@]}" "${PNET_SSH_USER}@${PNET_SSH_HOST}" "mkdir -p '${remote_dir}'"

local_sha="$(sha256sum "${LOCAL_LAB_FILE}" | awk '{print $1}')"
remote_sha="$("${ssh_base[@]}" "${PNET_SSH_USER}@${PNET_SSH_HOST}" "sha256sum '${remote_lab}' 2>/dev/null | awk '{print \$1}' || true" | tr -d '\r\n')"

if [[ -n "${remote_sha}" && "${remote_sha}" == "${local_sha}" ]]; then
  echo "==> Remote lab already up-to-date (sha256 match) -> skip upload"
else
  tmp="${remote_lab}.tmp.$(date +%s)"
  echo "==> Copying lab file"
  "${scp_base[@]}" "${LOCAL_LAB_FILE}" "${PNET_SSH_USER}@${PNET_SSH_HOST}:${tmp}"
  "${ssh_base[@]}" "${PNET_SSH_USER}@${PNET_SSH_HOST}" "mv -f '${tmp}' '${remote_lab}'"
fi

echo "==> Fixing permissions"
"${ssh_base[@]}" "${PNET_SSH_USER}@${PNET_SSH_HOST}" "/opt/unetlab/wrappers/unl_wrapper -a fixpermissions >/dev/null 2>&1 || true"

echo "==> Done."
