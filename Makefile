SHELL := /usr/bin/env bash

.PHONY: compose-install up down setup health objects atomic demo coverage reset logs status test unit-test validate vm-up vm-ssh vm-destroy vm-validate

COMPOSE := ./scripts/compose.sh
.PHONY: findings
VM_DIR := $(CURDIR)/vm
VM_PROVIDER ?= virtualbox

compose-install:
	./scripts/install-compose.sh

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

validate:
	python3 -c 'import pathlib, yaml; [yaml.safe_load(p.read_text()) for p in pathlib.Path(".").rglob("*.yml")]; [yaml.safe_load(p.read_text()) for p in pathlib.Path(".").rglob("*.yaml")]'
	for script in scripts/*.sh vm/*.sh; do bash -n "$$script" || exit 1; done
	$(COMPOSE) config --quiet
