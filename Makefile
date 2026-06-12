.PHONY: lint test install

SHELL := /bin/bash

lint:
	@./tests/shellcheck.sh

test: lint
	@./tests/bats/run.sh

install:
	@chmod +x install.sh bin/xray-cli tests/shellcheck.sh tests/bats/run.sh
	@echo "Run: sudo ./install.sh"
