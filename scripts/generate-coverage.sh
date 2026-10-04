#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_compose
[[ -f "${PROJECT_ROOT}/runtime/latest.json" ]] || {
  error "No execution manifest found. Run 'make atomic' first."
  exit 1
}

compose --profile tools run --rm coverage-analyzer
