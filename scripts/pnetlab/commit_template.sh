#!/usr/bin/env bash
set -euo pipefail

LAB_ID="${1:-}"
NODE_ID="${2:-}"
IMAGE_NAME="${3:-}"
POD_ID="${4:-0}"

if [[ -z "${LAB_ID}" || -z "${NODE_ID}" || -z "${IMAGE_NAME}" ]]; then
  echo "Usage: $0 <lab_id> <node_id> <image_name> [pod_id]" >&2
  exit 2
fi

: "${PNET_SSH_HOST:?PNET_SSH_HOST is required}"
PNET_SSH_USER="${PNET_SSH_USER:-root}"
PNET_SSH_PORT="${PNET_SSH_PORT:-22}"
PNET_SSH_PASSWORD="${PNET_SSH_PASSWORD:-}"
PNET_SSH_KEY_PATH="${PNET_SSH_KEY_PATH:-}"

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

remote_dir="/opt/unetlab/addons/qemu/${IMAGE_NAME}"
marker="${remote_dir}/.template_ready"
PNET_SESSION_ID="${PNET_SESSION_ID:-1}"

if ! [[ "${PNET_SESSION_ID}" =~ ^[0-9]+$ ]]; then
  echo "PNET_SESSION_ID must be an integer (got: ${PNET_SESSION_ID})" >&2
  exit 2
fi

# PNETLab's runtime workspace is keyed by session id and node id.
# In practice, unl_wrapper starts QEMU with CWD like: /opt/unetlab/tmp/<session>/<node>
overlay_dir="/opt/unetlab/tmp/${PNET_SESSION_ID}/${NODE_ID}"

echo "==> Committing overlay to template (image=${IMAGE_NAME}, lab=${LAB_ID}, node=${NODE_ID}, session=${PNET_SESSION_ID}, pod=${POD_ID})"

if "${ssh_base[@]}" "${PNET_SSH_USER}@${PNET_SSH_HOST}" "test -f '${marker}'"; then
  echo "Template marker exists (${marker}) -> skip commit."
  exit 0
fi

remote_commit_cmd='
set -euo pipefail
if [ ! -d "'"${overlay_dir}"'" ]; then
  echo "Overlay dir not found: '"${overlay_dir}"'" >&2
  exit 1
fi

QEMU_IMG="/opt/qemu/bin/qemu-img"
if [ ! -x "$QEMU_IMG" ]; then
  QEMU_IMG="$(command -v qemu-img || true)"
fi
if [ -z "$QEMU_IMG" ]; then
  echo "qemu-img not found on PNETLab." >&2
  exit 1
fi

cd "'"${overlay_dir}"'"
if [ ! -f virtioa.qcow2 ]; then
  echo "Overlay disk not found: virtioa.qcow2" >&2
  exit 1
fi

"$QEMU_IMG" info virtioa.qcow2 >/dev/null 2>&1 || true
"$QEMU_IMG" commit -f qcow2 virtioa.qcow2 -p
sync
mkdir -p "'"${remote_dir}"'"
touch "'"${marker}"'"
/opt/unetlab/wrappers/unl_wrapper -a fixpermissions >/dev/null 2>&1 || true
'

retries=10
delay=10
for i in $(seq 1 "${retries}"); do
  if "${ssh_base[@]}" "${PNET_SSH_USER}@${PNET_SSH_HOST}" "bash -lc $(printf '%q' "${remote_commit_cmd}")"; then
    echo "==> Commit succeeded."
    exit 0
  fi
  echo "==> Commit failed (attempt ${i}/${retries}), retry in ${delay}s..."
  sleep "${delay}"
done

echo "Commit failed after ${retries} attempts." >&2
exit 1
