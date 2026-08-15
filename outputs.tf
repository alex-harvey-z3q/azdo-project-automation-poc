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

// Managed pipeline folder IDs exported for pipeline organisation review.
output "build_folder_ids" {
  description = "Managed Azure Pipelines folder IDs."
  value = {
    for key, folder in azuredevops_build_folder.this : key => folder.id
  }
}

// Managed environment IDs exported for checks and deployment review.
output "environment_ids" {
  description = "Managed Azure Pipelines environment IDs."
  value = {
    for key, environment in azuredevops_environment.this : key => environment.id
  }
}

// Managed feed IDs exported for artifact and permission review.
output "artifact_feed_ids" {
  description = "Managed Azure Artifacts feed IDs."
  value = {
    for key, feed in azuredevops_feed.this : key => feed.id
  }
}

// Managed project wiki URL exported for operator access.
output "wiki_url" {
  description = "Managed project wiki URL."
  value       = length(azuredevops_wiki.project) == 0 ? null : azuredevops_wiki.project[0].url
}

// Managed board column resources exported for review.
output "board_column_ids" {
  description = "Managed Azure DevOps board column resource IDs."
  value = {
    for key, board in azdoboard_board_columns.this : key => board.id
  }
}

// Managed board team settings exported for review.
output "board_team_setting_ids" {
  description = "Managed Azure DevOps board team setting resource IDs."
  value = {
    for key, settings in azdoboard_team_settings.this : key => settings.id
  }
}

// Managed variable group IDs exported for pipeline and permission review.
output "variable_group_ids" {
  description = "Managed Azure DevOps variable group IDs."
  value = {
    for key, group in azuredevops_variable_group.this : key => group.id
  }
}

// Managed generic service endpoint IDs exported for authorization review.
output "generic_service_endpoint_ids" {
  description = "Managed generic service endpoint IDs."
  value = {
    for key, endpoint in azuredevops_serviceendpoint_generic.this : key => endpoint.id
  }
}

// Managed build definition IDs exported for branch policy and operator review.
output "build_definition_ids" {
  description = "Managed Azure DevOps build definition IDs."
  value = {
    for key, definition in azuredevops_build_definition.this : key => definition.id
  }
}
