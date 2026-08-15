environment     = "import-test"
org_service_url = "https://dev.azure.com/alexharv074"

project = {
  name               = "azdo-import-poc"
  description        = "Disposable Azure DevOps project used to test Terraform import coverage."
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
  "managed-by-script",
  "import-rehearsal",
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
    name                                                = "internal-packages"
    permanent_delete                                    = false
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

This wiki is managed by the import rehearsal seed script with generic placeholder content.
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

boards = {}

variable_groups = {
  shared = {
    name         = "shared-non-secret"
    description  = "Shared non-secret variables for the project space."
    allow_access = true
    variables = {
      ENVIRONMENT = "import-test"
      OWNER       = "seed-script"
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
}

generic_service_endpoints = {}

pipeline_authorizations = {}

repository_files = {
  platform_readme = {
    repository_key = "platform"
    file           = "README.md"
    content        = "# Platform\n\nSeeded for Terraform import rehearsal.\n"
    commit_message = "Seed platform README"
  }

  platform_pipeline = {
    repository_key = "platform"
    file           = "azure-pipelines.yml"
    content        = "trigger:\n- main\n\npool:\n  vmImage: ubuntu-latest\n\nsteps:\n- script: echo \"Validate platform import rehearsal\"\n  displayName: Validate\n"
    commit_message = "Seed platform pipeline"
  }

  application_readme = {
    repository_key = "application"
    file           = "README.md"
    content        = "# Application\n\nSeeded for Terraform import rehearsal.\n"
    commit_message = "Seed application README"
  }

  application_pipeline = {
    repository_key = "application"
    file           = "azure-pipelines.yml"
    content        = "trigger:\n- main\n\npool:\n  vmImage: ubuntu-latest\n\nsteps:\n- script: echo \"Validate application import rehearsal\"\n  displayName: Validate\n"
    commit_message = "Seed application pipeline"
  }
}

build_definitions = {}

repository_policy_guardrails = {
  enabled                 = false
  blocking                = true
  max_file_size           = 10485760
  max_path_length         = 240
  enforce_reserved_names  = true
  enforce_consistent_case = true
  filepath_patterns       = []
  author_email_patterns   = []
}

repository_branch_policies = {
  enabled = false
}

repository_build_validation_policies = {}

repository_branch_policy_overrides = {}
