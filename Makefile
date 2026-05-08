SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := build

IMAGE_NAME := restic-scheduler:local
TEST_ENV := test/.env
TEST_COMPOSE_FILE := test/docker-compose.yml
COMPOSE := $(shell if docker compose version >/dev/null 2>&1; then printf '%s' 'docker compose'; elif command -v docker-compose >/dev/null 2>&1; then printf '%s' 'docker-compose'; fi)
TEST_COMPOSE_ARGS := --env-file $(TEST_ENV) -f $(TEST_COMPOSE_FILE)

.PHONY: build test

build:
	docker build -t $(IMAGE_NAME) .

test:
	if [[ -z "$(COMPOSE)" ]]; then
		echo "docker compose or docker-compose is required" >&2
		exit 1
	fi
	cleanup() {
		$(COMPOSE) $(TEST_COMPOSE_ARGS) down -v --remove-orphans >/dev/null 2>&1 || true
	}
	trap cleanup EXIT
	$(COMPOSE) $(TEST_COMPOSE_ARGS) build restic
	$(COMPOSE) $(TEST_COMPOSE_ARGS) up -d restic
	for attempt in $$(seq 1 30); do
		if $(COMPOSE) $(TEST_COMPOSE_ARGS) exec -T restic restic cat config >/dev/null 2>&1; then
			break
		fi
		if [[ $$attempt -eq 30 ]]; then
			echo "restic service did not initialize in time" >&2
			exit 1
		fi
		sleep 2
	done
	$(COMPOSE) $(TEST_COMPOSE_ARGS) exec -T restic /usr/local/bin/restic-job backup
	$(COMPOSE) $(TEST_COMPOSE_ARGS) exec -T restic /usr/local/bin/restic-job check
	$(COMPOSE) $(TEST_COMPOSE_ARGS) exec -T restic restic ls latest >/dev/null
	echo "Test stack passed"
