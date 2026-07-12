SHELL := /bin/sh

ENV ?= prod
VAR_FILE ?= env/$(ENV).tfvars
PLAN_FILE ?= .terraform/$(ENV).tfplan
ENABLE_BOARDS ?= false
TF_CLI_CONFIG_FILE := $(CURDIR)/.terraformrc
AZDOBOARD_PROVIDER_DIR := providers/terraform-provider-azdoboard
GO_CACHE_DIR := $(CURDIR)/$(AZDOBOARD_PROVIDER_DIR)/.gocache
GO_MOD_CACHE_DIR := $(CURDIR)/$(AZDOBOARD_PROVIDER_DIR)/.gomodcache
GO_ENV := GOCACHE=$(GO_CACHE_DIR) GOMODCACHE=$(GO_MOD_CACHE_DIR)
export TF_CLI_CONFIG_FILE

.DEFAULT_GOAL := help

.PHONY: help init fmt fmt-check validate check plan apply destroy output clean provider-devrc provider-tidy provider-build provider-test provider-check

help: ## Show available targets.
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <target> [ENV=prod]\n\nTargets:\n"} /^[a-zA-Z_-]+:.*##/ {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: provider-build provider-devrc ## Initialise Terraform with local state and the local board provider.
	terraform init

fmt: provider-devrc ## Format Terraform files.
	terraform fmt -recursive

fmt-check: provider-devrc ## Check Terraform formatting.
	terraform fmt -recursive -check

validate: provider-build provider-devrc ## Validate Terraform configuration.
	terraform validate

check: provider-check fmt-check validate ## Run local static checks.

plan: provider-build provider-devrc ## Write a Terraform plan for the selected environment.
	terraform plan -input=false -var-file="$(VAR_FILE)" -var="enable_boards=$(ENABLE_BOARDS)" -out="$(PLAN_FILE)"

apply: provider-build provider-devrc ## Apply the saved Terraform plan for the selected environment.
	terraform apply "$(PLAN_FILE)"

destroy: provider-build provider-devrc ## Destroy resources for the selected environment.
	terraform destroy -input=false -var-file="$(VAR_FILE)" -var="enable_boards=$(ENABLE_BOARDS)"

output: provider-devrc ## Show Terraform outputs.
	terraform output

clean: ## Remove local Terraform plan files.
	rm -f .terraform/*.tfplan

provider-devrc: ## Write Terraform CLI config for the local AzDO board provider.
	@printf '%s\n' 'provider_installation {' '  dev_overrides {' '    "local/azdoboard" = "$(CURDIR)/$(AZDOBOARD_PROVIDER_DIR)/bin"' '  }' '' '  direct {}' '}' > "$(TF_CLI_CONFIG_FILE)"

provider-tidy: ## Resolve custom AzDO board provider Go dependencies.
	cd $(AZDOBOARD_PROVIDER_DIR) && $(GO_ENV) go mod tidy

provider-build: ## Build the custom AzDO board provider locally.
	cd $(AZDOBOARD_PROVIDER_DIR) && $(GO_ENV) go build -o bin/terraform-provider-azdoboard

provider-test: ## Run custom AzDO board provider tests.
	cd $(AZDOBOARD_PROVIDER_DIR) && $(GO_ENV) go test ./...

provider-check: provider-tidy provider-build provider-test ## Build and test the custom AzDO board provider.
