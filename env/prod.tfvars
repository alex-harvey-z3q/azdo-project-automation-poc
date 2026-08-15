environment     = "prod"
org_service_url = "https://dev.azure.com/alexharv074"

project = {
  name               = "azdo-project-automation-poc"
  description        = "Proof of concept for automated Azure DevOps project provisioning."
  visibility         = "private"
  work_item_template = "Scrum"
  features = {
    boards       = "enabled"
    repositories = "enabled"
    pipelines    = "enabled"
    testplans    = "disabled"
    artifacts    = "enabled"
  }
}

project_tags = [
  "managed-by-terraform",
  "proof-of-concept",
]

project_pipeline_settings = {
  enforce_job_scope                    = true
  enforce_job_scope_for_release        = true
  enforce_referenced_repo_scoped_token = true
  enforce_settable_var                 = true
  publish_pipeline_metadata            = true
  status_badges_are_private            = true
}

repositories = {
  platform = {
    name = "platform"
  }
  application = {
    name = "application"
  }
}

build_folders = {
  platform = {
    path        = "\\platform"
    description = "Build definitions for platform examples."
  }
  application = {
    path        = "\\application"
    description = "Build definitions for application examples."
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

environments = {
  development = {
    name        = "development"
    description = "Placeholder deployment environment for early validation."
  }
  test = {
    name        = "test"
    description = "Placeholder deployment environment for pre-production validation."
  }
  production = {
    name        = "production"
    description = "Placeholder deployment environment for production release gates."
  }
}

environment_approval_checks = {}

artifact_feeds = {
  internal_packages = {
    name                                                = "internal-packages-scrum-poc"
    permanent_delete                                    = true
    restore                                             = false
    retention_count_limit                               = 30
    retention_days_to_keep_recently_downloaded_packages = 30
  }
}

wiki_pages = {
  home = {
    path    = "/Home"
    content = <<EOT
# Project Space

This wiki is managed by Terraform with generic placeholder content.
EOT
  }

  conventions = {
    path    = "/Conventions"
    content = <<EOT
# Conventions

- Use repository-specific pipelines for CI.
- Store non-secret settings in managed variable groups.
- Store secrets outside this repository and inject them at deploy time.
- Treat board layouts as reconciled configuration rather than Terraform-owned infrastructure.
EOT
  }
}

boards = {
  platform_backlog_items = {
    team_key               = "platform"
    board                  = "Backlog items"
    default_area_path      = "azdo-project-automation-poc"
    backlog_iteration_path = "azdo-project-automation-poc"

    columns = [
      {
        name        = "New"
        column_type = "incoming"
        state_mappings = {
          "Product Backlog Item" = "New"
          Bug                    = "New"
        }
      },
      {
        name        = "Approved"
        column_type = "inProgress"
        item_limit  = 5
        state_mappings = {
          "Product Backlog Item" = "Approved"
          Bug                    = "Approved"
        }
      },
      {
        name        = "Committed"
        column_type = "inProgress"
        state_mappings = {
          "Product Backlog Item" = "Committed"
          Bug                    = "Committed"
        }
      },
      {
        name        = "Done"
        column_type = "outgoing"
        state_mappings = {
          "Product Backlog Item" = "Done"
          Bug                    = "Done"
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

  shared_runtime = {
    name         = "shared-runtime-settings"
    description  = "Generic runtime placeholders shared by example pipelines."
    allow_access = true
    variables = {
      LOG_LEVEL         = "info"
      SERVICE_NAMESPACE = "example"
      DEPLOYMENT_RING   = "placeholder"
    }
  }

  shared_release = {
    name         = "shared-release-settings"
    description  = "Generic release placeholders shared by example pipelines."
    allow_access = false
    variables = {
      CHANGE_REFERENCE_REQUIRED = "true"
      RELEASE_NOTES_REQUIRED    = "true"
    }
  }
}

generic_service_endpoints = {}

pipeline_authorizations = {}

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

  platform_docs = {
    repository_key = "platform"
    file           = "docs/project-space.md"
    content        = <<EOT
# Platform Project Space

This placeholder document captures conventions that can be made project-specific later.
EOT
    commit_message = "Add platform project-space conventions"
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

  application_docs = {
    repository_key = "application"
    file           = "docs/project-space.md"
    content        = <<EOT
# Application Project Space

This placeholder document captures conventions that can be made project-specific later.
EOT
    commit_message = "Add application project-space conventions"
  }
}

build_definitions = {
  platform_ci = {
    name                = "platform-ci"
    repository_key      = "platform"
    yml_path            = "azure-pipelines.yml"
    path                = "\\platform"
    variable_group_keys = ["shared"]
  }

  application_ci = {
    name                = "application-ci"
    repository_key      = "application"
    yml_path            = "azure-pipelines.yml"
    path                = "\\application"
    variable_group_keys = ["shared"]
  }
}

repository_policy_guardrails = {
  enabled                 = true
  blocking                = true
  max_file_size           = 10
  max_path_length         = 240
  enforce_reserved_names  = true
  enforce_consistent_case = true
  filepath_patterns       = []
  author_email_patterns   = []
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
