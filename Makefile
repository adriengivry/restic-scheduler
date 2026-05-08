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
	@docker build -t $(IMAGE_NAME) .

test:
	@if [[ -z "$(COMPOSE)" ]]; then
		echo "docker compose or docker-compose is required" >&2
		exit 1
	fi
	export TEST_IMAGE="$(IMAGE_NAME)"
	cleanup() {
		$(COMPOSE) $(TEST_COMPOSE_ARGS) down -v --remove-orphans >/dev/null 2>&1 || true
	}
	reset_ping_logs() {
		$(COMPOSE) $(TEST_COMPOSE_ARGS) exec -T ping sh -c ': > /state/backup.log && : > /state/check.log'
	}
	restic_container() {
		$(COMPOSE) $(TEST_COMPOSE_ARGS) ps -q restic
	}
	restic_logs() {
		docker logs "$$(restic_container)" 2>&1
	}
	wait_for_scheduler() {
		for attempt in $$(seq 1 30); do
			if $(COMPOSE) $(TEST_COMPOSE_ARGS) exec -T restic sh -c 'restic cat config >/dev/null 2>&1 && test -f /etc/restic-scheduler.crontab'; then
				return 0
			fi
			if [[ $$attempt -eq 30 ]]; then
				echo "restic service did not initialize in time" >&2
				return 1
			fi
			sleep 2
		done
	}
	wait_for_job() {
		local label="$$1"
		local path="$$2"
		local marker="$$3"
		echo "Waiting for scheduled $$label job"
		for attempt in $$(seq 1 40); do
			if restic_logs | grep -Fq "$$marker" \
				&& $(COMPOSE) $(TEST_COMPOSE_ARGS) exec -T ping test -s "/state/$$path.log"; then
				return 0
			fi
			if [[ $$attempt -eq 40 ]]; then
				echo "Scheduled $$label job did not complete in time" >&2
				$(COMPOSE) $(TEST_COMPOSE_ARGS) logs restic ping >&2 || true
				return 1
			fi
			sleep 2
		done
	}
	assert_existing_repository_startup() {
		local logs
		logs="$$(restic_logs)"
		if grep -Fq 'created restic repository' <<<"$$logs"; then
			echo "Container recreated an existing repository" >&2
			printf '%s\n' "$$logs" >&2
			return 1
		fi
		if grep -Fq 'Fatal:' <<<"$$logs"; then
			echo "Container hit a fatal error when starting with an existing repository" >&2
			printf '%s\n' "$$logs" >&2
			return 1
		fi
	}
	show_phase_logs() {
		local label="$$1"
		local path="$$2"
		echo "--- $$label restic logs ---"
		restic_logs
		echo "--- $$label ping callbacks ---"
		$(COMPOSE) $(TEST_COMPOSE_ARGS) exec -T ping cat "/state/$$path.log"
	}
	trap cleanup EXIT
	echo "Building image $(IMAGE_NAME)"
	docker build -t "$(IMAGE_NAME)" .
	echo "Starting ping receiver"
	$(COMPOSE) $(TEST_COMPOSE_ARGS) up -d ping
	echo "Testing scheduled backup configuration"
	reset_ping_logs
	BACKUP_CRON='* * * * *' CHECK_CRON='' $(COMPOSE) $(TEST_COMPOSE_ARGS) up -d --force-recreate restic
	wait_for_scheduler
	$(COMPOSE) $(TEST_COMPOSE_ARGS) exec -T restic grep -F '* * * * * /usr/local/bin/restic-job backup' /etc/restic-scheduler.crontab >/dev/null
	wait_for_job backup backup '### END BACKUP'
	$(COMPOSE) $(TEST_COMPOSE_ARGS) exec -T restic restic ls latest >/dev/null
	show_phase_logs backup backup
	echo "Testing existing repository startup and scheduled check"
	reset_ping_logs
	BACKUP_CRON='' CHECK_CRON='* * * * *' $(COMPOSE) $(TEST_COMPOSE_ARGS) up -d --force-recreate restic
	wait_for_scheduler
	assert_existing_repository_startup
	$(COMPOSE) $(TEST_COMPOSE_ARGS) exec -T restic grep -F '* * * * * /usr/local/bin/restic-job check' /etc/restic-scheduler.crontab >/dev/null
	wait_for_job check check '### END CHECK'
	show_phase_logs check check
	echo "Test stack passed"
