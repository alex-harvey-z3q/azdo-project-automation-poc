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
  work_item_linking_required  = false
}
