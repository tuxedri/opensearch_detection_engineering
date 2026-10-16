#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_compose
[[ -f "${PROJECT_ROOT}/runtime/latest.json" ]] || {
  error "No execution manifest found. This legacy coverage helper is not part of the supported Make workflow."
  exit 1
}

compose --profile tools run --rm coverage-analyzer
