#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

write_step() {
  echo "==> $*"
}

write_step "Installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  fuse3 \
  git \
  gnupg \
  jq \
  lsb-release \
  open-vm-tools \
  openssh-client \
  sshpass \
  xorriso \
  python3 \
  python3-pip \
  python3-paramiko \
  python3-venv

write_step "Installing Ansible"
apt-get install -y --no-install-recommends ansible

if ! command -v terraform >/dev/null 2>&1; then
  write_step "Installing Terraform (HashiCorp APT repo)"
  install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" >/etc/apt/sources.list.d/hashicorp.list
  apt-get update -y
  apt-get install -y --no-install-recommends terraform
else
  write_step "Terraform already installed"
fi

write_step "Enabling VMware tools service (best-effort)"
systemctl enable --now open-vm-tools 2>/dev/null || true
systemctl enable --now vmtoolsd 2>/dev/null || true

REPO_SHARE_NAME="${REPO_SHARE_NAME:-WallixRepo}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/hgfs/${REPO_SHARE_NAME}}"

write_step "Trying to mount VMware Shared Folder '${REPO_SHARE_NAME}' (optional)"
mkdir -p /mnt/hgfs
mkdir -p "${MOUNT_POINT}"
if command -v vmhgfs-fuse >/dev/null 2>&1; then
  if mountpoint -q "${MOUNT_POINT}"; then
    echo "Already mounted: ${MOUNT_POINT}"
  else
    vmhgfs-fuse ".host:/${REPO_SHARE_NAME}" "${MOUNT_POINT}" -o allow_other 2>/dev/null || true
  fi
else
  echo "vmhgfs-fuse not found; shared folders may not work (open-vm-tools not fully installed?)"
fi

write_step "Versions"
terraform -version | head -n 1 || true
ansible-playbook --version | head -n 1 || true
python3 --version || true

cat <<EOF

Runner bootstrap complete.

Next:
- If you used VMware Shared Folders, the repo should be at: ${MOUNT_POINT}
- Then run the PoC from inside the repo:
    ./scripts/runner/run-poc.sh --secrets-file ./secrets_local.env --mode local --auto-approve
EOF
