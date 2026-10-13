#!/usr/bin/env bash
#
# Run Atomic Red Team techniques from a YAML list, one container per test.
#
# For every enabled technique it starts a fresh container from
# redcanary/invoke-atomicredteam:latest and runs
#   Invoke-AtomicTest <technique> [<args>]
# Container name and the com.redcanary.atomic.* labels are derived from the
# technique argument so Auditbeat tags the generated events accordingly.
#
# Defaults to non-interactive use (no TTY) so it works under `make` and in
# scripts. Set ATOMIC_INTERACTIVE=1 for an attached terminal (`-it`).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

source "${PROJECT_ROOT}/scripts/lib.sh"

CONFIG="${ATOMIC_CONFIG:-${PROJECT_ROOT}/tests/atomic/invoke.yml}"
LIMIT=""
DRY_RUN=0
INTERACTIVE=0
[[ -n "${ATOMIC_INTERACTIVE:-}" ]] && INTERACTIVE=1

usage() {
  cat <<'EOF'
Usage: invoke-atomic.sh [--config PATH] [--limit N] [--dry-run] [--interactive]

Options:
  -c, --config PATH   YAML file with the technique list (default: tests/atomic/invoke.yml)
  -l, --limit N       Run at most N enabled techniques (default: all)
  -n, --dry-run       Print the docker commands instead of running them
  -i, --interactive   Attach a TTY (-it) for manual terminal sessions
                        (equivalent to ATOMIC_INTERACTIVE=1)

Environment:
  ATOMIC_CONFIG       Same as --config
  ATOMIC_INTERACTIVE  Non-empty enables interactive mode
  ATOMIC_DRY_RUN     Non-empty enables dry-run mode
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config) CONFIG="$2"; shift 2 ;;
    -l|--limit) LIMIT="$2"; shift 2 ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -i|--interactive) INTERACTIVE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $1"; exit 2 ;;
  esac
done

[[ -n "${ATOMIC_DRY_RUN:-}" ]] && DRY_RUN=1
[[ -n "${ATOMIC_LIMIT:-}" ]] && LIMIT="${ATOMIC_LIMIT}"
require_command python3

if [[ ! -f "$CONFIG" ]]; then
  error "Config not found: $CONFIG"
  exit 1
fi

# Parse + filter enabled techniques here once, applying the optional limit.
mapfile -t ROWS < <(python3 - "$CONFIG" "$LIMIT" <<'PY'
import sys, yaml

path, raw_limit = sys.argv[1], sys.argv[2]
try:
    limit = max(1, int(raw_limit)) if str(raw_limit).strip() not in ("", "0") else 0
except ValueError:
    limit = 0

with open(path, encoding="utf-8") as fh:
    cfg = yaml.safe_load(fh) or {}
items = cfg.get("techniques") if isinstance(cfg, dict) else None
if items is None:
    items = cfg.get("tests") if isinstance(cfg, dict) else None
items = items or []

count = 0
for item in items:
    if not isinstance(item, dict):
        continue
    technique = str(item.get("technique", "")).strip()
    if not technique:
        continue
    if item.get("enabled", True) is False:
        continue
    if limit and count >= limit:
        break
    count += 1
    guid = str(item.get("atomic_guid", "")).strip()
    name = str(item.get("name") or technique).replace("\x1f", " ").strip()
    source = str(item.get("source") or "").strip()
    timeout = str(int(item.get("timeout_seconds", 120))).strip()
    args = str(item.get("args", "")).strip()
    # Field separator is a control char (not IFS-whitespace) so empty fields
    # do not collapse during 'read'.
    print("\x1f".join([technique, guid, name, timeout, args, source]))
PY
)

if [[ ${#ROWS[@]} -eq 0 ]]; then
  error "No enabled techniques found in $CONFIG"
  exit 1
fi

sanitize_name() {
  # T1059.004 -> t1059-004
  printf 'art-%s' "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '.' '_')"
}

run_count=${#ROWS[@]}
failed=0
seq=0
testrun="$(python3 -c 'import secrets; print(secrets.token_hex(3))')"
log "Running ${run_count} Atomic technique(s) from ${CONFIG} (testrun=${testrun})"
for row in "${ROWS[@]}"; do

  IFS=$'\x1f' read -r technique guid name timeout args source <<<"$row"
  seq=$((seq + 1))
  # Preserve the human-readable technique name before it is shadowed by the
  # generated container name below; it becomes the atomic.name label.
  display="${name}"
  name="$(sanitize_name "$technique")-${seq}"

  docker_args=(--rm --name "$name" --label "com.redcanary.atomic.test=${technique}"
               --label "com.redcanary.atomic.name=${display}"
               --label "com.redcanary.atomic.link=${source}"
               --label "com.redcanary.atomic.testrun=${testrun}")
  [[ -n "$guid" ]] && docker_args+=(--label "com.redcanary.atomic.guid=${guid}")

  inner=(Invoke-AtomicTest "$technique")
  if [[ -n "$args" ]]; then
    read -r -a _extra <<<"$args"
    inner+=("${_extra[@]}")
  fi

  ps_command="$(IFS=' '; echo "${inner[*]}")"

  # No -NoProfile: the image registers Invoke-AtomicTest via $PROFILE, which must
  # be loaded for the command to resolve.
  pwsh_flags=(-NonInteractive)
  [[ "$INTERACTIVE" -eq 1 ]] && pwsh_flags=()

  run_cmd=(docker run "${docker_args[@]}" \
           redcanary/invoke-atomicredteam:latest \
           pwsh "${pwsh_flags[@]}" -Command "$ps_command")
  [[ "$INTERACTIVE" -eq 1 ]] && run_cmd=(docker run -ti "${docker_args[@]}" \
           redcanary/invoke-atomicredteam:latest \
           pwsh "${pwsh_flags[@]}" -Command "$ps_command")

  log "[$seq/$run_count] ${technique} (${name})${guid:+ guid=${guid}}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '    %s\n' "${run_cmd[*]}"
    continue
  fi

  require_command docker
  start_epoch=$(date +%s)
  if timeout --signal=TERM --kill-after=10s "${timeout}s" "${run_cmd[@]}"; then
    rc=0
  else
    rc=$?
  fi
  end_epoch=$(date +%s)
  if [[ $rc -eq 124 || $rc -eq 137 ]]; then
    error "[$seq/$run_count] ${technique} timed out after ${timeout}s"
  elif [[ $rc -ne 0 ]]; then
    error "[$seq/$run_count] ${technique} exited with code ${rc}"
  fi
  log "[$seq/$run_count] ${technique} finished ($(($end_epoch - $start_epoch))s)"

  (( rc != 0 )) && failed=$((failed + 1))
done

if [[ $failed -eq 0 ]]; then
  log "All techniques completed successfully."
  exit 0
fi
error "${failed} of ${run_count} technique(s) did not complete successfully."
exit 1
