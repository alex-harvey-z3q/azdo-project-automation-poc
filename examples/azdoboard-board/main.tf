terraform {
  required_providers {
    azdoboard = {
      source  = "local/azdoboard"
      version = "0.1.0"
    }
  }
}

variable "org_service_url" {
  type    = string
  default = "https://dev.azure.com/alexharv074"
}

variable "personal_access_token" {
  type      = string
  sensitive = true
}

provider "azdoboard" {
  org_service_url       = var.org_service_url
  personal_access_token = var.personal_access_token
}

# Basic-process projects usually use an Issues board and Issue state mappings:
# To Do -> Doing -> Done.
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
      is_split    = true
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
