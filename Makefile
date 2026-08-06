SHELL := /usr/bin/env bash
EVALS_DIR := evals

# Specific fixtures to run, e.g. `make evals-setup FIXTURES="ctl-010-deep-nesting nam-010-missing-prefix"`.
# Empty means all fixtures.
FIXTURES ?=

# Parallel skill runs during `evals-run` / `evals`.
JOBS ?= 3

# Results directory. Defaults to the newest one under evals/results so that
# `evals-run` / `evals-grade` target the same run `evals-setup` just created.
RESULTS_DIR ?= $(shell ls -1dt $(EVALS_DIR)/results/*/ 2>/dev/null | head -1)

.DEFAULT_GOAL := help

.PHONY: help evals evals-setup evals-run evals-grade evals-clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

evals: ## Full pipeline: set up fixtures, run the skill headlessly, grade (JOBS=N, FIXTURES="...")
	@set -e; \
	rd="$(EVALS_DIR)/results/$$(date +%Y%m%d-%H%M%S)"; \
	RESULTS_DIR="$$rd" bash $(EVALS_DIR)/run-evals.sh $(FIXTURES); \
	JOBS=$(JOBS) bash $(EVALS_DIR)/run-skill.sh "$$rd"; \
	bash $(EVALS_DIR)/grade-results.sh "$$rd"

evals-setup: ## Create fixture repos and review dirs (FIXTURES="..." to scope)
	bash $(EVALS_DIR)/run-evals.sh $(FIXTURES)

evals-run: ## Run the skill headlessly over the latest (or RESULTS_DIR=...) fixtures
	@test -n "$(RESULTS_DIR)" || { echo "no results dir found; run 'make evals-setup' first" >&2; exit 1; }
	JOBS=$(JOBS) bash $(EVALS_DIR)/run-skill.sh $(RESULTS_DIR)

evals-grade: ## Grade skill outputs in the latest (or RESULTS_DIR=...) results dir
	@test -n "$(RESULTS_DIR)" || { echo "no results dir found; run 'make evals-setup' first" >&2; exit 1; }
	bash $(EVALS_DIR)/grade-results.sh $(RESULTS_DIR)

evals-clean: ## Remove all generated eval results
	rm -rf $(EVALS_DIR)/results/*
