terraform {
  // Workspace-scoped remote state key for the Azure DevOps project automation state.
  backend "azurerm" {
    key = "stacks/azdo-project-automation-poc/terraform.tfstate"
  }
}
