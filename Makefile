SHELL := /usr/bin/env bash

.PHONY: compose-install up down setup health atomic demo coverage reset logs status test validate vm-up vm-ssh vm-destroy vm-validate

COMPOSE := ./scripts/compose.sh
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

atomic:
	$(COMPOSE) --profile tools run --rm atomic-runner

demo: health atomic coverage

coverage:
	./scripts/generate-coverage.sh

reset:
	./scripts/reset.sh

logs:
	$(COMPOSE) logs --follow

status:
	$(COMPOSE) ps

test:
	python3 -m pytest -q

validate:
	python3 -c 'import pathlib, yaml; [yaml.safe_load(p.read_text()) for p in pathlib.Path(".").rglob("*.yml")]; [yaml.safe_load(p.read_text()) for p in pathlib.Path(".").rglob("*.yaml")]'
	for script in scripts/*.sh vm/*.sh; do bash -n "$$script" || exit 1; done
	$(COMPOSE) config --quiet

vm-up:
	VM_PROVIDER="$(VM_PROVIDER)" VAGRANT_CWD="$(VM_DIR)" vagrant up --provider="$(VM_PROVIDER)"

vm-ssh:
	VM_PROVIDER="$(VM_PROVIDER)" VAGRANT_CWD="$(VM_DIR)" vagrant ssh

vm-destroy:
	VM_PROVIDER="$(VM_PROVIDER)" VAGRANT_CWD="$(VM_DIR)" vagrant destroy

vm-validate:
	VM_PROVIDER="$(VM_PROVIDER)" VAGRANT_CWD="$(VM_DIR)" vagrant validate
