# Terraform Provider AzDO Board

This is a small proof-of-concept Terraform provider for Azure DevOps board
settings that are not currently modelled in the main
`microsoft/azuredevops` provider.

It currently exposes two resources:

```hcl
resource "azdoboard_team_settings" "platform" {
  project                 = "azdo-project-automation-poc"
  team                    = "Platform"
  default_area_path       = "azdo-project-automation-poc"
  include_area_children   = true
  backlog_iteration_path  = "azdo-project-automation-poc"
  default_iteration_macro = "@CurrentIteration"
}
```

```hcl
resource "azdoboard_board_columns" "platform_issues" {
  project = "azdo-project-automation-poc"
  team    = "Platform"
  board   = "Issues"
  columns = [
    {
      name        = "To Do"
      column_type = "incoming"
      state_mappings = {
        Issue = "To Do"
      }
    },
    {
      name        = "Doing"
      column_type = "inProgress"
      item_limit  = 5
      state_mappings = {
        Issue = "Doing"
      }
    },
    {
      name        = "Done"
      column_type = "outgoing"
      state_mappings = {
        Issue = "Done"
      }
    }
  ]
}
```

For an Agile-process project, the board is commonly `Stories` and the mapping
key is commonly `User Story`.

## Authentication

The provider accepts:

```hcl
provider "azdoboard" {
  org_service_url       = "https://dev.azure.com/alexharv074"
  personal_access_token = var.personal_access_token
}
```

or these environment variables:

```sh
export AZDOBOARD_ORG_SERVICE_URL="https://dev.azure.com/alexharv074"
export AZDOBOARD_PERSONAL_ACCESS_TOKEN="$TF_VAR_personal_access_token"
```

The PAT needs enough access to read and update Azure Boards settings.

## Important Limitation

Azure DevOps creates boards from the project process and team. This provider
does not create or delete the underlying board. It manages board columns for an
existing team board.

Deleting the Terraform resource removes it from Terraform state only; it does
not reset the remote Azure DevOps board columns.
