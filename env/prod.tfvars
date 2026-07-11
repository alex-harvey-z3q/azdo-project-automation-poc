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
