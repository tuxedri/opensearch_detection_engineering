SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help
.PHONY: help up down setup health objects findings reset logs status test unit-test validate

COMPOSE := ./scripts/compose.sh
help:
	@printf '%s\n' 'Run inside the lab VM. See docs/commands.md for details.' \
	  'setup, up   Start and configure the telemetry stack' \
	  'down, reset Stop the stack; preserve data volumes' \
	  'health      Check core service health' \
	  'status      Show container status' \
	  'logs        Follow service logs (Ctrl-C to stop following)' \
	  'objects     Import saved dashboards (overwrite matching IDs)' \
	  'findings    Import enriched Security Analytics findings' \
	  'test        Run Atomic simulations; accepts ARGS="..."' \
	  'unit-test   Run Python regression tests' \
	  'validate    Check YAML, JSON, shell syntax and Compose'

up:
	./scripts/setup.sh

down:
	$(COMPOSE) down

setup:
	./scripts/setup.sh

health:
	./scripts/health.sh

objects:
	bash ./scripts/install-saved-objects.sh

findings:
	python3 scripts/import-findings.py

reset:
	./scripts/reset.sh

logs:
	$(COMPOSE) logs --follow

status:
	$(COMPOSE) ps

test:
	./tests/atomic/invoke-atomic.sh $(ARGS)

unit-test:
	python3 -m pytest -q tests/unit

validate:
	python3 scripts/validate-files.py
	for script in scripts/*.sh vm/*.sh tests/atomic/*.sh; do bash -n "$$script" || exit 1; done
	$(COMPOSE) config --quiet
