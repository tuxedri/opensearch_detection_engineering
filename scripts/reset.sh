#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_compose
log "Stopping containers without deleting persistent volumes."
compose down
