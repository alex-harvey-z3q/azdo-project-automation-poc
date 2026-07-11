SHELL := /bin/sh

ENV ?= prod
VAR_FILE ?= env/$(ENV).tfvars
PLAN_FILE ?= .terraform/$(ENV).tfplan

.DEFAULT_GOAL := help

.PHONY: help init fmt fmt-check validate check plan apply destroy output clean

help: ## Show available targets.
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <target> [ENV=prod]\n\nTargets:\n"} /^[a-zA-Z_-]+:.*##/ {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialise Terraform with local state.
	terraform init

fmt: ## Format Terraform files.
	terraform fmt -recursive

fmt-check: ## Check Terraform formatting.
	terraform fmt -recursive -check

validate: ## Validate Terraform configuration.
	terraform validate

check: fmt-check validate ## Run local static checks.

plan: ## Write a Terraform plan for the selected environment.
	terraform plan -var-file="$(VAR_FILE)" -out="$(PLAN_FILE)"

apply: ## Apply the saved Terraform plan for the selected environment.
	terraform apply "$(PLAN_FILE)"

destroy: ## Destroy resources for the selected environment.
	terraform destroy -var-file="$(VAR_FILE)"

output: ## Show Terraform outputs.
	terraform output

clean: ## Remove local Terraform plan files.
	rm -f .terraform/*.tfplan
