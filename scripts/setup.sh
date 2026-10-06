#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ "$(uname -s)" == "Linux" ]] || {
  error "This lab requires Linux inside a disposable VM."
  exit 1
}

if command -v systemd-detect-virt >/dev/null 2>&1; then
  virtualization="$(systemd-detect-virt 2>/dev/null || true)"
  if [[ "$virtualization" == "none" && "${ALLOW_UNSAFE_HOST:-no}" != "yes" ]]; then
    error "No VM was detected. Refusing to start host-audit collection and attack simulations."
    error "Use a disposable VM, or set ALLOW_UNSAFE_HOST=yes only if this host is intentionally disposable."
    exit 1
  fi
fi

require_compose

if (( $(awk '/MemTotal/ {print $2}' /proc/meminfo) < 6000000 )); then
  error "At least 6 GB RAM is required; 8 GB is recommended."
  exit 1
fi

if (( $(sysctl -n vm.max_map_count) < 262144 )); then
  error "vm.max_map_count must be at least 262144. Configure it on the VM first."
  exit 1
fi

log "Validating Compose configuration."
compose config --quiet

log "Starting OpenSearch, Dashboards, and Logstash."
compose up --detach --build opensearch opensearch-dashboards logstash
"${PROJECT_ROOT}/scripts/wait-for-opensearch.sh"

bash "${PROJECT_ROOT}/scripts/install-index-template.sh"

log "Starting Auditbeat after the index template is active."
compose up --detach auditbeat

log "Core telemetry stack setup completed."
