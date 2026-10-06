#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_compose
require_command python3

readonly templates_dir="${PROJECT_ROOT}/config/opensearch/index-templates"
export LC_ALL=C
shopt -s nullglob
templates=("${templates_dir}"/*.json)
if (( ${#templates[@]} == 0 )); then
  error "No index templates found in ${templates_dir}."
  exit 1
fi

# Validate every file before making any changes to OpenSearch.
for template_path in "${templates[@]}"; do
  template_name="${template_path##*/}"
  template_name="${template_name%.json}"
  if [[ ! "$template_name" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    error "Invalid template filename: ${template_path##*/}. Use lowercase letters, digits, dots, underscores, or hyphens."
    exit 1
  fi
  if ! python3 -m json.tool "$template_path" >/dev/null; then
    error "Invalid JSON in ${template_path}."
    exit 1
  fi
done

put_json() {
  local endpoint="$1"
  local response
  if ! response="$(compose exec -T opensearch sh -c \
    'curl --silent --show-error --fail-with-body --insecure --connect-timeout 10 --max-time 90 --user "admin:${OPENSEARCH_INITIAL_ADMIN_PASSWORD}" --header "Content-Type: application/json" --request PUT "https://localhost:9200/$1" --data-binary @-' \
    sh "$endpoint")"; then
    error "OpenSearch PUT ${endpoint} failed: ${response}"
    return 1
  fi
  if ! python3 -c 'import json, sys; sys.exit(0 if json.load(sys.stdin).get("acknowledged") is True else 1)' <<<"$response"; then
    error "OpenSearch did not acknowledge PUT ${endpoint}: ${response}"
    return 1
  fi
}

# Retain the existing additive container mapping update when Auditbeat is present.
template_path="${templates_dir}/default-auditbeat-8.12.json"
if [[ -f "$template_path" ]]; then
  container_mapping="$(python3 - "$template_path" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as template_file:
    template = json.load(template_file)
container = template["template"]["mappings"]["properties"]["container"]
print(json.dumps({"properties": {"container": container}}))
PY
)"

  # OpenSearch validates compatibility across the matched indexes before merging.
  # An empty match is valid on the first startup, before Auditbeat creates an index.
  log "Applying container mappings to existing security-auditbeat indexes."
  if ! put_json 'security-auditbeat-*/_mapping?allow_no_indices=true&expand_wildcards=open,closed' <<<"$container_mapping"; then
    error "Inspect existing container field types with GET security-auditbeat-*/_mapping/field/container.* before retrying."
    exit 1
  fi
fi

for template_path in "${templates[@]}"; do
  template_name="${template_path##*/}"
  template_name="${template_name%.json}"
  # Preserve the deployed name to avoid overlapping templates at equal priority.
  [[ "$template_name" == "default-auditbeat-8.12" ]] && template_name="security-auditbeat"
  log "Installing ${template_path##*/} as ${template_name}."
  put_json "_index_template/${template_name}" <"$template_path"
done
log "All ${#templates[@]} index templates are active."
