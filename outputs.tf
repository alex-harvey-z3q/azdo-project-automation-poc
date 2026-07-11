// Azure DevOps project ID exported for cross-state references and review.
output "project_id" {
  description = "Azure DevOps project ID."
  value       = azuredevops_project.this.id
}

// Azure DevOps project URL exported for operator access after apply.
output "project_url" {
  description = "Azure DevOps project URL."
  value       = "${local.org_service_url}/${azuredevops_project.this.name}"
}
