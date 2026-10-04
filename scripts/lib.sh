#!/usr/bin/env bash

set -Eeuo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
  printf '%s [INFO] %s\n' "$(date --iso-8601=seconds)" "$*"
}

error() {
  printf '%s [ERROR] %s\n' "$(date --iso-8601=seconds)" "$*" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    error "Required command not found: $1"
    return 1
  }
}

require_compose() {
  require_command docker
  if docker compose version >/dev/null 2>&1; then
    return 0
  fi

  local local_config="${PROJECT_ROOT}/.tools/docker-config"
  if [[ -x "${local_config}/cli-plugins/docker-compose" ]] && \
    DOCKER_CONFIG="$local_config" docker compose version >/dev/null 2>&1; then
    return 0
  fi

  error "Docker Compose v2 or newer is required. Run 'make compose-install'."
  return 1
}

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
    return
  fi

  local local_config="${PROJECT_ROOT}/.tools/docker-config"
  DOCKER_CONFIG="$local_config" docker compose "$@"
}
