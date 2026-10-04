#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly timeout_seconds="${OPENSEARCH_WAIT_TIMEOUT:-300}"
readonly deadline=$((SECONDS + timeout_seconds))

while (( SECONDS < deadline )); do
  if compose exec -T opensearch sh -c \
    'curl --silent --fail --insecure --user "admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}" https://localhost:9200/_cluster/health' \
    >/dev/null; then
    log "OpenSearch is ready."
    exit 0
  fi
  sleep 5
done

error "OpenSearch did not become ready within ${timeout_seconds} seconds."
exit 1
