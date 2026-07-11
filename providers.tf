terraform {
  // Terraform and provider versions are pinned for repeatable project automation plans.
  required_version = "= 1.15.6"

  required_providers {
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "= 1.15.1"
    }
  }
}

provider "azuredevops" {
  org_service_url       = local.org_service_url
  personal_access_token = var.personal_access_token
}
