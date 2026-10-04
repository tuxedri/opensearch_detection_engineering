#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_compose

failed=0
for service in opensearch opensearch-dashboards logstash auditbeat; do
  container_id="$(compose ps --quiet "$service")"
  status=""
  if [[ -n "$container_id" ]]; then
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id")"
  fi
  if [[ "$status" == "healthy" || "$status" == "running" ]]; then
    log "${service}: ${status}"
  else
    error "${service}: ${status:-not running}"
    failed=1
  fi
done

exit "$failed"
