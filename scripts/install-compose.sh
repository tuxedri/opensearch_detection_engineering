#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly compose_version="v5.5.1"
readonly machine="$(uname -m)"

case "$machine" in
  x86_64)
    readonly compose_arch="x86_64"
    readonly expected_sha256="db1889184726840f75c4f9c001048430d4f25b3be3cb084d3ddd762bc0aed576"
    ;;
  aarch64|arm64)
    readonly compose_arch="aarch64"
    readonly expected_sha256="732e3a84c1a0f67256ce80bc2598a24546b10ca05f9faa97efceb1171ece2ef7"
    ;;
  *)
    error "Unsupported architecture for the project-local Compose installer: ${machine}"
    exit 1
    ;;
esac

require_command curl
require_command sha256sum

readonly plugin_dir="${PROJECT_ROOT}/.tools/docker-config/cli-plugins"
readonly plugin_path="${plugin_dir}/docker-compose"
readonly download_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-${compose_arch}"

mkdir -p "$plugin_dir"
temporary_file="$(mktemp "${plugin_dir}/docker-compose.XXXXXX")"
trap 'rm -f "$temporary_file"' EXIT

log "Downloading Docker Compose ${compose_version} for linux/${compose_arch}."
curl --fail --location --silent --show-error --output "$temporary_file" "$download_url"

actual_sha256="$(sha256sum "$temporary_file")"
actual_sha256="${actual_sha256%% *}"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  error "Docker Compose checksum verification failed."
  exit 1
fi

chmod 0755 "$temporary_file"
mv "$temporary_file" "$plugin_path"
trap - EXIT

DOCKER_CONFIG="${PROJECT_ROOT}/.tools/docker-config" docker compose version
