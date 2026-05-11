build:
	docker build -t restic-scheduler:local .

test:
	lua test/test.lua

.DEFAULT_GOAL := build
.PHONY: build test
