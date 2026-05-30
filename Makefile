# Makefile — dev tasks for the toolkit itself.
.DEFAULT_GOAL := help
SHELL := bash

SH_FILES := scripts/*.sh home/*.sh install.sh uninstall.sh tests/smoke.sh \
            repo-template/.codex/skills/lab-research/scripts/*.sh

.PHONY: help test lint check doctor install install-dry uninstall bump release-check

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

test: ## Run the smoke test
	@bash tests/smoke.sh

lint: ## Run shellcheck (warning severity) if available
	@if command -v shellcheck >/dev/null; then \
		shellcheck -S warning $(SH_FILES) && echo "shellcheck clean"; \
	else echo "shellcheck not installed; skipping"; fi

check: lint test ## What CI runs: lint + test

doctor: ## Run the health check against this environment
	@bash scripts/codex-doctor.sh

install-dry: ## Preview a full install
	@bash install.sh --all --dry-run

install: ## Install global config + scripts onto this machine
	@bash install.sh --home --scripts

uninstall: ## Remove installed files (keeps your data)
	@bash uninstall.sh --all

bump: ## Bump version + seed CHANGELOG (make bump V=patch|minor|major|X.Y.Z)
	@bash scripts/bump-version.sh "$(or $(V),patch)"

release-check: ## Verify VERSION and CHANGELOG are in sync before tagging
	@ver="$$(tr -d '[:space:]' < VERSION)"; \
	if grep -q "## \[$$ver\]" CHANGELOG.md; then \
		echo "ok: VERSION $$ver has a matching CHANGELOG section"; \
	else echo "FAIL: no '## [$$ver]' section in CHANGELOG.md" >&2; exit 1; fi
