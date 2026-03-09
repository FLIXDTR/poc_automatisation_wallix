#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${1:-}"
ISO_PATH="${2:-}"
DISK_SIZE="${3:-}"

if [[ -z "${IMAGE_NAME}" || -z "${ISO_PATH}" || -z "${DISK_SIZE}" ]]; then
  echo "Usage: $0 <image_name> <iso_path> <disk_size>" >&2
  exit 2
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo "ssh is required on the runner." >&2
  exit 1
fi

if ! command -v scp >/dev/null 2>&1; then
  echo "scp is required on the runner." >&2
  exit 1
fi

if ! command -v xorriso >/dev/null 2>&1; then
  echo "xorriso is required on the runner (for auto-boot ISO patching). Install it (ex: sudo apt-get install -y xorriso)." >&2
  exit 1
fi

ISO_ABS="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${ISO_PATH}")"
if [[ ! -f "${ISO_ABS}" ]]; then
  echo "ISO not found: ${ISO_ABS}" >&2
  exit 1
fi

: "${HOME:=/tmp}"
CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/wallix"
mkdir -p "${CACHE_DIR}"

ISO_BASE="$(basename "${ISO_ABS}")"
ISO_FOR_XORRISO="${ISO_ABS}"

# xorriso can fail with "Input/output error" when reading files directly from VMware HGFS.
# Cache the ISO on the guest filesystem first to make the patching step reliable.
if [[ "${ISO_ABS}" == /mnt/hgfs/* ]]; then
  ISO_CACHED="${CACHE_DIR}/${ISO_BASE}"
  src_size="$(python3 -c 'import os,sys; print(os.path.getsize(sys.argv[1]))' "${ISO_ABS}")"
  dst_size="$(python3 -c 'import os,sys; print(os.path.getsize(sys.argv[1])) if os.path.exists(sys.argv[1]) else print(0)' "${ISO_CACHED}")"
  if [[ "${dst_size}" != "${src_size}" ]]; then
    echo "==> Caching ISO locally for xorriso (HGFS -> ext4)"
    echo "  src: ${ISO_ABS} (${src_size} bytes)"
    echo "  dst: ${ISO_CACHED}"
    cp -f "${ISO_ABS}" "${ISO_CACHED}"
  fi
  ISO_FOR_XORRISO="${ISO_CACHED}"
fi

ISO_SHA256="$(sha256sum "${ISO_FOR_XORRISO}" | awk '{print $1}')"
ISO_SHA_SHORT="${ISO_SHA256:0:12}"
AUTO_ISO="${CACHE_DIR}/${ISO_BASE%.iso}.autoboot.${ISO_SHA_SHORT}.iso"

patch_iso_autoboot() {
  local src_iso="$1"
  local dst_iso="$2"

  if [[ -f "${dst_iso}" && -s "${dst_iso}" ]]; then
    echo "==> Auto-boot ISO already exists -> ${dst_iso}"
    return 0
  fi

  echo "==> Creating auto-boot ISO (no manual keypress at boot)"
  echo "  src: ${src_iso}"
  echo "  dst: ${dst_iso}"

  local workdir
  workdir="$(mktemp -d)"
  trap 'rm -rf "${workdir}"' RETURN

  mkdir -p "${workdir}/patched/isolinux"
  mkdir -p "${workdir}/patched/boot/grub"

  # Extract only the files we need to patch.
  xorriso -osirrox on -indev "${src_iso}" -extract /isolinux/isolinux.cfg "${workdir}/patched/isolinux/isolinux.cfg" >/dev/null 2>&1
  xorriso -osirrox on -indev "${src_iso}" -extract /boot/grub/grub.cfg "${workdir}/patched/boot/grub/grub.cfg" >/dev/null 2>&1

  local isolinux_cfg="${workdir}/patched/isolinux/isolinux.cfg"
  local grub_cfg="${workdir}/patched/boot/grub/grub.cfg"

  if [[ ! -f "${isolinux_cfg}" ]]; then
    echo "isolinux.cfg not found in ISO: /isolinux/isolinux.cfg" >&2
    exit 1
  fi
  if [[ ! -f "${grub_cfg}" ]]; then
    echo "grub.cfg not found in ISO: /boot/grub/grub.cfg" >&2
    exit 1
  fi

  # Files extracted from the ISO can be read-only (0444). Make them writable before patching.
  chmod u+w "${isolinux_cfg}" "${grub_cfg}"

  # Patch BIOS bootloader: boot label 'install' automatically (the ISO defines that label).
  python3 - "${isolinux_cfg}" <<'PY'
import pathlib
import re
import sys

cfg = pathlib.Path(sys.argv[1])
lines = cfg.read_text(encoding="utf-8", errors="replace").splitlines()

out = []
have_timeout = False
have_default = False
for line in lines:
    if re.match(r"^\s*timeout\s+\d+\s*$", line, re.IGNORECASE):
        out.append("timeout 10")
        have_timeout = True
        continue
    if re.match(r"^\s*default\s+.+$", line, re.IGNORECASE):
        out.append("default install")
        have_default = True
        continue
    out.append(line)

if not have_timeout:
    out.insert(0, "timeout 10")
if not have_default:
    out.append("default install")

cfg.write_text("\n".join(out) + "\n", encoding="utf-8")
PY

  # Patch UEFI bootloader (GRUB): hide menu and auto-boot entry id 'install'.
  python3 - "${grub_cfg}" <<'PY'
import pathlib
import sys

cfg = pathlib.Path(sys.argv[1])
text = cfg.read_text(encoding="utf-8", errors="replace")

lines = text.splitlines()
header = [
    'set default="install"',
    "set timeout=1",
    "set timeout_style=hidden",
    "",
]

# Avoid duplicating if already patched
if any(line.strip().startswith("set default=") for line in lines[:10]):
    cfg.write_text(text if text.endswith("\n") else text + "\n", encoding="utf-8")
else:
    cfg.write_text("\n".join(header + lines) + "\n", encoding="utf-8")
PY

  local tmp_iso="${dst_iso}.tmp"
  # Replay original boot settings (BIOS+UEFI) and overwrite only the patched files.
  xorriso \
    -indev "${src_iso}" \
    -outdev "${tmp_iso}" \
    -boot_image any replay \
    -overwrite on \
    -map "${isolinux_cfg}" /isolinux/isolinux.cfg \
    -map "${grub_cfg}" /boot/grub/grub.cfg >/dev/null 2>&1

  mv -f "${tmp_iso}" "${dst_iso}"
  test -s "${dst_iso}"
}

patch_iso_autoboot "${ISO_FOR_XORRISO}" "${AUTO_ISO}"

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

remote_dir="/opt/unetlab/addons/qemu/${IMAGE_NAME}"
remote_iso="${remote_dir}/cdrom.iso"
remote_disk="${remote_dir}/virtioa.qcow2"
marker="${remote_dir}/.template_ready"

echo "==> Preparing image folder on PNETLab: ${remote_dir}"

if "${ssh_base[@]}" "${PNET_SSH_USER}@${PNET_SSH_HOST}" "test -f '${marker}'"; then
  echo "Template marker exists (${marker}) -> skip prepare."
  exit 0
fi

"${ssh_base[@]}" "${PNET_SSH_USER}@${PNET_SSH_HOST}" "mkdir -p '${remote_dir}'"

local_size="$(python3 -c 'import os,sys; print(os.path.getsize(sys.argv[1]))' "${AUTO_ISO}")"
remote_size="$("${ssh_base[@]}" "${PNET_SSH_USER}@${PNET_SSH_HOST}" "stat -c %s '${remote_iso}' 2>/dev/null || echo 0" | tr -d '\r\n')"

if [[ "${remote_size}" != "${local_size}" ]]; then
  echo "==> Uploading ISO (${local_size} bytes) to ${remote_iso}"
  tmp="${remote_iso}.tmp"
  "${scp_base[@]}" "${AUTO_ISO}" "${PNET_SSH_USER}@${PNET_SSH_HOST}:${tmp}"
  "${ssh_base[@]}" "${PNET_SSH_USER}@${PNET_SSH_HOST}" "mv -f '${tmp}' '${remote_iso}'"
else
  echo "==> ISO already present with matching size -> skip upload"
fi

echo "==> Ensuring base disk exists (${DISK_SIZE})"
"${ssh_base[@]}" "${PNET_SSH_USER}@${PNET_SSH_HOST}" "test -f '${remote_disk}' || (qemu-img create -f qcow2 '${remote_disk}' '${DISK_SIZE}')"

echo "==> Fixing permissions"
"${ssh_base[@]}" "${PNET_SSH_USER}@${PNET_SSH_HOST}" "/opt/unetlab/wrappers/unl_wrapper -a fixpermissions >/dev/null 2>&1 || true"

echo "==> Done."
