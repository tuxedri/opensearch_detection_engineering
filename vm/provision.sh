#!/usr/bin/env bash

set -Eeuo pipefail

readonly repo_mount_path="${1:-/workspace/opensearch-detection-lab}"
readonly docker_keyring="/etc/apt/keyrings/docker.asc"
readonly docker_source="/etc/apt/sources.list.d/docker.list"
readonly sysctl_config="/etc/sysctl.d/99-opensearch-detection-lab.conf"

log() {
  printf '%s [INFO] %s\n' "$(date --iso-8601=seconds)" "$*"
}

export DEBIAN_FRONTEND=noninteractive

log "Installing base VM packages."
apt-get update
apt-get install --yes --no-install-recommends \
  auditd \
  ca-certificates \
  curl \
  git \
  jq \
  make

install -d -m 0755 /etc/apt/keyrings
if [[ ! -s "$docker_keyring" ]]; then
  log "Installing Docker repository signing key."
  curl --fail --location --silent --show-error \
    https://download.docker.com/linux/ubuntu/gpg \
    --output "$docker_keyring"
  chmod 0644 "$docker_keyring"
fi

source /etc/os-release
docker_repository="deb [arch=$(dpkg --print-architecture) signed-by=${docker_keyring}] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable"
if [[ ! -f "$docker_source" ]] || [[ "$(<"$docker_source")" != "$docker_repository" ]]; then
  log "Configuring the Docker apt repository."
  printf '%s\n' "$docker_repository" >"$docker_source"
fi

log "Installing Docker Engine and Compose plugin."
apt-get update
apt-get install --yes --no-install-recommends \
  containerd.io \
  docker-buildx-plugin \
  docker-ce \
  docker-ce-cli \
  docker-compose-plugin \
  python3-venv

systemctl enable --now docker
usermod -aG docker vagrant

log "Configuring OpenSearch kernel requirements."
printf '%s\n' \
  'vm.max_map_count=262144' \
  'fs.file-max=65536' \
  >"$sysctl_config"
sysctl --system >/dev/null

log "Stopping host auditd so the Auditbeat container can own the audit connection."
if systemctl is-active --quiet auditd; then
  service auditd stop
fi
systemctl disable auditd >/dev/null 2>&1 || true
systemctl mask auditd >/dev/null

if [[ ! -d "$repo_mount_path" ]]; then
  printf '%s [ERROR] Repository mount is unavailable at %s\n' \
    "$(date --iso-8601=seconds)" "$repo_mount_path" >&2
  exit 1
fi

ln -sfn "$repo_mount_path" /home/vagrant/opensearch-detection-lab
chown --no-dereference vagrant:vagrant /home/vagrant/opensearch-detection-lab

log "Verifying installed tooling."
docker --version
docker compose version

log "VM provisioning completed. Reconnect SSH for Docker group membership to apply."
