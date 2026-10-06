#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_compose
require_command python3

readonly objects_dir="${PROJECT_ROOT}/config/opensearch-dashboards/objects"
readonly timeout_seconds="${OPENSEARCH_DASHBOARD_WAIT:-120}"
if [[ ! "$timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  error "OPENSEARCH_DASHBOARD_WAIT must be a positive integer (seconds)."
  exit 1
fi
if [[ ! -d "$objects_dir" ]]; then
  error "Saved objects directory not found: ${objects_dir}"
  exit 1
fi

# Bash globs sort each group; nullglob prevents importing unmatched patterns.
export LC_ALL=C
shopt -s nullglob
files=("${objects_dir}"/indexpattern*.ndjson "${objects_dir}"/dashboard*.ndjson)
for file in "${objects_dir}"/*.ndjson; do
  case "${file##*/}" in
    indexpattern*|dashboard*) continue ;;
  esac
  files+=("$file")
done
if (( ${#files[@]} == 0 )); then
  log "No NDJSON files found in ${objects_dir}."
  exit 0
fi

# Run curl where the existing admin credentials and curl are already available.
# Explicit project directory also permits invoking the helper from outside the repo.
dashboards_curl() {
  compose --project-directory "$PROJECT_ROOT" exec -T opensearch sh -c \
    'exec curl --silent --show-error --fail-with-body --connect-timeout 10 --max-time 90 --user "admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}" "$@"' \
    sh "$@"
}

log "Waiting for OpenSearch Dashboards."
deadline=$((SECONDS + 10#$timeout_seconds))
until dashboards_curl --max-time 5 'http://opensearch-dashboards:5601/api/status' >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    error "OpenSearch Dashboards did not become ready within ${timeout_seconds} seconds. Check the opensearch and opensearch-dashboards services."
    exit 1
  fi
  sleep 2
done

for file in "${files[@]}"; do
  log "Importing ${file##*/} (overwrite enabled)."
  if ! response="$(dashboards_curl \
    --header 'osd-xsrf: true' \
    --form 'file=@-;filename=objects.ndjson' \
    'http://opensearch-dashboards:5601/api/saved_objects/_import?overwrite=true' <"$file")"; then
    error "Import request failed for ${file##*/}: ${response}"
    exit 1
  fi
  # Import errors (including missing references) can accompany HTTP 200.
  if ! python3 -c 'import json, sys
result = json.load(sys.stdin)
sys.exit(0 if result.get("success") is True and not result.get("errors") else 1)
' <<<"$response"; then
    error "Import failed for ${file##*/}: ${response}"
    exit 1
  fi
  log "Imported ${file##*/}."
done

log "Imported all ${#files[@]} saved-object files."
