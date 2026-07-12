environment     = "prod"
org_service_url = "https://dev.azure.com/alexharv074"

project = {
  name               = "azdo-project-automation-poc"
  description        = "Proof of concept for automated Azure DevOps project provisioning."
  visibility         = "private"
  work_item_template = "Basic"
}

repositories = {
  platform = {
    name = "platform"
  }
  application = {
    name = "application"
  }
}

teams = {
  platform = {
    name = "Platform"
  }
  application = {
    name = "Application"
  }
}

boards = {
  platform_issues = {
    team_key               = "platform"
    board                  = "Issues"
    default_area_path      = "azdo-project-automation-poc"
    backlog_iteration_path = "azdo-project-automation-poc"

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
}

variable_groups = {
  shared = {
    name         = "shared-non-secret"
    description  = "Shared non-secret variables for the project space."
    allow_access = true
    variables = {
      ENVIRONMENT = "prod"
      OWNER       = "terraform"
    }
  }
}

repository_files = {
  platform_readme = {
    repository_key = "platform"
    file           = "README.md"
    content        = <<EOT
# Platform

Managed by Terraform as part of the Azure DevOps project automation proof-of-concept.
EOT
    commit_message = "Add platform README"
  }

  platform_pipeline = {
    repository_key = "platform"
    file           = "azure-pipelines.yml"
    content        = <<EOT
trigger:
- main

pool:
  vmImage: ubuntu-latest

steps:
- script: echo "Validate platform project space"
  displayName: Validate
EOT
    commit_message = "Add platform pipeline"
  }

  application_readme = {
    repository_key = "application"
    file           = "README.md"
    content        = <<EOT
# Application

Managed by Terraform as part of the Azure DevOps project automation proof-of-concept.
EOT
    commit_message = "Add application README"
  }

  application_pipeline = {
    repository_key = "application"
    file           = "azure-pipelines.yml"
    content        = <<EOT
trigger:
- main

pool:
  vmImage: ubuntu-latest

steps:
- script: echo "Validate application project space"
  displayName: Validate
EOT
    commit_message = "Add application pipeline"
  }
}

build_definitions = {
  platform_ci = {
    name                = "platform-ci"
    repository_key      = "platform"
    yml_path            = "azure-pipelines.yml"
    variable_group_keys = ["shared"]
  }

  application_ci = {
    name                = "application-ci"
    repository_key      = "application"
    yml_path            = "azure-pipelines.yml"
    variable_group_keys = ["shared"]
  }
}

repository_branch_policies = {
  reviewer_count              = 1
  last_pusher_cannot_approve  = true
  comment_resolution_required = true
  work_item_linking_required  = true

  merge_types = {
    allow_squash                  = true
    allow_rebase_and_fast_forward = false
    allow_rebase_with_merge       = false
    allow_basic_no_fast_forward   = false
  }
}

repository_build_validation_policies = {
  platform_ci = {
    repository_key       = "platform"
    build_definition_key = "platform_ci"
    display_name         = "platform-ci"
    filename_patterns    = ["/src/*", "/azure-pipelines.yml"]
  }

  application_ci = {
    repository_key       = "application"
    build_definition_key = "application_ci"
    display_name         = "application-ci"
    filename_patterns    = ["/src/*", "/azure-pipelines.yml"]
  }
}

repository_branch_policy_overrides = {
  platform = {
    reviewer_count             = 2
    work_item_linking_required = true

    merge_types = {
      allow_squash                  = true
      allow_rebase_and_fast_forward = false
      allow_rebase_with_merge       = false
      allow_basic_no_fast_forward   = false
    }
  }

  application = {
    reviewer_count             = 1
    work_item_linking_required = false

    merge_types = {
      allow_squash                  = true
      allow_rebase_and_fast_forward = true
      allow_rebase_with_merge       = false
      allow_basic_no_fast_forward   = false
    }
  }
}
