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

// Managed Git repository web URLs exported for operator access.
output "repository_urls" {
  description = "Managed Azure DevOps Git repository URLs."
  value = {
    for key, repository in azuredevops_git_repository.this : key => repository.web_url
  }
}

// Managed team descriptors exported for future membership and permission work.
output "team_descriptors" {
  description = "Managed Azure DevOps team descriptors."
  value = {
    for key, team in azuredevops_team.this : key => team.descriptor
  }
}
