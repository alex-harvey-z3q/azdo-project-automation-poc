locals {
  // Static organisation URL and environment-specific project configuration for this state.
  environment     = var.environment
  org_service_url = trim(var.org_service_url, "/")
  project         = var.project
  repositories    = var.repositories
  teams           = var.teams

  // Azure DevOps project features owned by this stack.
  project_features = {
    boards       = "enabled"
    repositories = "enabled"
    pipelines    = "enabled"
    testplans    = "disabled"
    artifacts    = "disabled"
  }

  repository_branch_policies = var.repository_branch_policies

  branch_policy_repository_keys = length(local.repository_branch_policies.repositories) > 0 ? (
    local.repository_branch_policies.repositories
  ) : toset(keys(local.repositories))
}
