locals {
  // Static organisation URL and environment-specific project configuration for this state.
  environment     = var.environment
  org_service_url = trim(var.org_service_url, "/")
  project         = var.project

  // Azure DevOps project features owned by this stack.
  project_features = {
    boards       = "enabled"
    repositories = "enabled"
    pipelines    = "enabled"
    testplans    = "disabled"
    artifacts    = "disabled"
  }
}
