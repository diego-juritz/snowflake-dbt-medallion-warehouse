.PHONY: help venv data data-check deps debug seed build test strict-test docs analyses clean

PYTHON ?= python3
VENV   ?= .venv
DBT    := $(VENV)/bin/dbt

help:  ## List targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

venv:  ## Create the virtualenv and install pinned dependencies
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip
	$(VENV)/bin/pip install -r requirements.txt

data:  ## Regenerate the deterministic sample CSVs
	$(PYTHON) scripts/generate_sample_data.py

data-check:  ## Offline checks: CSVs match the generator and pass integrity rules
	$(PYTHON) scripts/generate_sample_data.py --check
	$(PYTHON) scripts/validate_sample_data.py

deps:  ## Install dbt packages
	$(DBT) deps

debug:  ## Check profile and Snowflake connectivity
	$(DBT) debug

seed:  ## Load the raw CSVs into BRONZE
	$(DBT) seed

build: deps  ## Seed, run, and test everything in DAG order
	$(DBT) build

test:  ## Run data and unit tests against already-built models
	$(DBT) test

strict-test:  ## Controlled failure demo: referential warnings become errors
	$(DBT) test --select stg_orders --vars '{strict_referential_integrity: true}'

docs:  ## Generate and serve dbt docs locally
	$(DBT) docs generate
	$(DBT) docs serve

analyses:  ## Compile the business-question queries to target/compiled
	$(DBT) compile --select business_questions

clean:  ## Remove local dbt artifacts
	$(DBT) clean
