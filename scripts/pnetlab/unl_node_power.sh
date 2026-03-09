#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
LAB_REL_PATH="${2:-}"
TENANT_ID="${3:-}"
NODE_ID="${4:-}"

if [[ -z "${ACTION}" || -z "${LAB_REL_PATH}" || -z "${TENANT_ID}" ]]; then
  echo "Usage: $0 <start|stop|wipe> <lab_rel_path> <tenant_id> [node_id]" >&2
  echo "Example: $0 start User1/Wallix-Auto.unl 1 1" >&2
  exit 2
fi

case "${ACTION}" in
start|stop|wipe) ;;
*)
  echo "Unsupported action: ${ACTION} (expected start|stop|wipe)" >&2
  exit 2
  ;;
esac

if ! [[ "${TENANT_ID}" =~ ^[0-9]+$ ]]; then
  echo "tenant_id must be an integer (got: ${TENANT_ID})" >&2
  exit 2
fi

if [[ -n "${NODE_ID}" ]] && ! [[ "${NODE_ID}" =~ ^[0-9]+$ ]]; then
  echo "node_id must be an integer (got: ${NODE_ID})" >&2
  exit 2
fi

: "${PNET_SSH_HOST:?PNET_SSH_HOST is required}"
PNET_SSH_USER="${PNET_SSH_USER:-root}"
PNET_SSH_PORT="${PNET_SSH_PORT:-22}"
PNET_SSH_PASSWORD="${PNET_SSH_PASSWORD:-}"
PNET_SSH_KEY_PATH="${PNET_SSH_KEY_PATH:-}"
PNET_SESSION_ID="${PNET_SESSION_ID:-1}"

if ! [[ "${PNET_SESSION_ID}" =~ ^[0-9]+$ ]]; then
  echo "PNET_SESSION_ID must be an integer (got: ${PNET_SESSION_ID})" >&2
  exit 2
fi

ssh_base=(ssh -p "${PNET_SSH_PORT}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

if [[ -n "${PNET_SSH_KEY_PATH}" ]]; then
  ssh_base+=(-i "${PNET_SSH_KEY_PATH}")
elif [[ -n "${PNET_SSH_PASSWORD}" ]]; then
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "PNET_SSH_PASSWORD is set but sshpass is missing. Install sshpass on the runner." >&2
    exit 1
  fi
  ssh_base=(sshpass -p "${PNET_SSH_PASSWORD}" "${ssh_base[@]}")
else
  echo "Provide either PNET_SSH_KEY_PATH or PNET_SSH_PASSWORD." >&2
  exit 1
fi

remote_lab="/opt/unetlab/labs/${LAB_REL_PATH}"

echo "==> PNETLab unl_wrapper: ${ACTION} (tenant=${TENANT_ID}, lab=${LAB_REL_PATH}, node=${NODE_ID:-all})"

cmd="/opt/unetlab/wrappers/unl_wrapper -a ${ACTION} -T ${TENANT_ID} -F '${remote_lab}'"
cmd="${cmd} -S ${PNET_SESSION_ID}"
if [[ -n "${NODE_ID}" ]]; then
  cmd="${cmd} -D ${NODE_ID}"
fi

"${ssh_base[@]}" "${PNET_SSH_USER}@${PNET_SSH_HOST}" "test -f '${remote_lab}' && ${cmd}"

echo "==> Done."
