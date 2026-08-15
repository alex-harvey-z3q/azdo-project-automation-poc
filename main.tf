resource "azuredevops_project" "this" {
  name               = local.project.name
  description        = local.project.description
  visibility         = local.project.visibility
  version_control    = "Git"
  work_item_template = local.project.work_item_template

  features = local.project_features
}

resource "azuredevops_project_tags" "this" {
  count = length(local.project_tags) > 0 ? 1 : 0

  project_id = azuredevops_project.this.id
  tags       = local.project_tags
}

resource "azuredevops_project_pipeline_settings" "this" {
  project_id = azuredevops_project.this.id

  enforce_job_scope                    = var.project_pipeline_settings.enforce_job_scope
  enforce_job_scope_for_release        = var.project_pipeline_settings.enforce_job_scope_for_release
  enforce_referenced_repo_scoped_token = var.project_pipeline_settings.enforce_referenced_repo_scoped_token
  enforce_settable_var                 = var.project_pipeline_settings.enforce_settable_var
  publish_pipeline_metadata            = var.project_pipeline_settings.publish_pipeline_metadata
  status_badges_are_private            = var.project_pipeline_settings.status_badges_are_private
}

resource "azuredevops_git_repository" "this" {
  for_each = local.repositories

  project_id     = azuredevops_project.this.id
  name           = each.value.name
  default_branch = each.value.default_branch
  disabled       = each.value.disabled

  initialization {
    init_type = "Clean"
  }

  lifecycle {
    ignore_changes = [
      initialization,
    ]
  }
}

resource "azuredevops_build_folder" "this" {
  for_each = local.build_folders

  project_id  = azuredevops_project.this.id
  path        = each.value.path
  description = each.value.description
}

resource "azuredevops_team" "this" {
  for_each = local.teams

  project_id = azuredevops_project.this.id
  name       = each.value.name
}

resource "azuredevops_environment" "this" {
  for_each = local.environments

  project_id  = azuredevops_project.this.id
  name        = each.value.name
  description = each.value.description
}

resource "azuredevops_check_approval" "environment" {
  for_each = local.environment_approval_checks

  project_id                 = azuredevops_project.this.id
  target_resource_id         = azuredevops_environment.this[each.value.environment_key].id
  target_resource_type       = "environment"
  approvers                  = each.value.approvers
  instructions               = each.value.instructions
  minimum_required_approvers = each.value.minimum_required_approvers
  requester_can_approve      = each.value.requester_can_approve
  timeout                    = each.value.timeout
}

resource "azuredevops_feed" "this" {
  for_each = local.artifact_feeds

  project_id = azuredevops_project.this.id
  name       = each.value.name

  features {
    permanent_delete = each.value.permanent_delete
    restore          = each.value.restore
  }
}

resource "azuredevops_feed_retention_policy" "this" {
  for_each = local.artifact_feeds

  project_id                                = azuredevops_project.this.id
  feed_id                                   = azuredevops_feed.this[each.key].id
  count_limit                               = each.value.retention_count_limit
  days_to_keep_recently_downloaded_packages = each.value.retention_days_to_keep_recently_downloaded_packages
}

resource "azuredevops_wiki" "project" {
  count = local.wiki_enabled ? 1 : 0

  project_id = azuredevops_project.this.id
  name       = "${local.project.name}.wiki"
  type       = "projectWiki"
}

resource "azuredevops_wiki_page" "this" {
  for_each = local.wiki_pages

  project_id = azuredevops_project.this.id
  wiki_id    = azuredevops_wiki.project[0].id
  path       = each.value.path
  content    = each.value.content
}

// Optional custom-provider PoC only. Azure DevOps boards already exist as team
// work surfaces, so Terraform cannot honestly own their create/destroy lifecycle.
resource "azdoboard_team_settings" "this" {
  for_each = local.board_team_settings

  project                 = azuredevops_project.this.name
  team                    = azuredevops_team.this[each.key].name
  default_area_path       = each.value[0].default_area_path
  include_area_children   = each.value[0].include_area_children
  backlog_iteration_path  = each.value[0].backlog_iteration_path
  default_iteration_macro = each.value[0].default_iteration_macro

  depends_on = [
    azuredevops_team.this,
  ]
}

resource "azdoboard_board_columns" "this" {
  for_each = local.boards

  project = azuredevops_project.this.name
  team    = azuredevops_team.this[each.value.team_key].name
  board   = each.value.board
  columns = each.value.columns

  depends_on = [
    azdoboard_team_settings.this,
  ]
}

resource "azuredevops_variable_group" "this" {
  for_each = local.variable_groups

  project_id   = azuredevops_project.this.id
  name         = each.value.name
  description  = each.value.description
  allow_access = each.value.allow_access

  dynamic "variable" {
    for_each = each.value.variables

    content {
      name  = variable.key
      value = variable.value
    }
  }
}

resource "azuredevops_serviceendpoint_generic" "this" {
  for_each = local.generic_service_endpoints

  project_id            = azuredevops_project.this.id
  service_endpoint_name = each.value.service_endpoint_name
  server_url            = each.value.server_url
  username              = each.value.username
  password              = each.value.password
  description           = each.value.description
}

resource "azuredevops_pipeline_authorization" "this" {
  for_each = local.pipeline_authorizations

  project_id          = azuredevops_project.this.id
  resource_id         = each.value.resource_id
  type                = each.value.type
  pipeline_id         = each.value.pipeline_id
  pipeline_project_id = coalesce(each.value.pipeline_project_id, azuredevops_project.this.id)
}

resource "azuredevops_git_repository_file" "this" {
  for_each = local.repository_files

  repository_id       = azuredevops_git_repository.this[each.value.repository_key].id
  file                = each.value.file
  content             = each.value.content
  branch              = each.value.branch
  commit_message      = each.value.commit_message
  overwrite_on_create = each.value.overwrite_on_create

  depends_on = [
    azuredevops_git_repository.this,
  ]

  lifecycle {
    ignore_changes = [
      content,
      commit_message,
    ]
  }
}

resource "azuredevops_repository_policy_max_file_size" "this" {
  count = local.repository_policy_guardrails.enabled ? 1 : 0

  project_id     = azuredevops_project.this.id
  enabled        = local.repository_policy_guardrails.enabled
  blocking       = local.repository_policy_guardrails.blocking
  repository_ids = local.repository_policy_repository_ids
  max_file_size  = local.repository_policy_guardrails.max_file_size
}

resource "azuredevops_repository_policy_max_path_length" "this" {
  count = local.repository_policy_guardrails.enabled ? 1 : 0

  project_id      = azuredevops_project.this.id
  enabled         = local.repository_policy_guardrails.enabled
  blocking        = local.repository_policy_guardrails.blocking
  repository_ids  = local.repository_policy_repository_ids
  max_path_length = local.repository_policy_guardrails.max_path_length
}

resource "azuredevops_repository_policy_reserved_names" "this" {
  count = local.repository_policy_guardrails.enabled && local.repository_policy_guardrails.enforce_reserved_names ? 1 : 0

  project_id     = azuredevops_project.this.id
  enabled        = local.repository_policy_guardrails.enabled
  blocking       = local.repository_policy_guardrails.blocking
  repository_ids = local.repository_policy_repository_ids
}

resource "azuredevops_repository_policy_case_enforcement" "this" {
  count = local.repository_policy_guardrails.enabled && local.repository_policy_guardrails.enforce_consistent_case ? 1 : 0

  project_id              = azuredevops_project.this.id
  enabled                 = local.repository_policy_guardrails.enabled
  blocking                = local.repository_policy_guardrails.blocking
  repository_ids          = local.repository_policy_repository_ids
  enforce_consistent_case = local.repository_policy_guardrails.enforce_consistent_case
}

resource "azuredevops_repository_policy_file_path_pattern" "this" {
  count = local.repository_policy_guardrails.enabled && length(local.repository_policy_guardrails.filepath_patterns) > 0 ? 1 : 0

  project_id        = azuredevops_project.this.id
  enabled           = local.repository_policy_guardrails.enabled
  blocking          = local.repository_policy_guardrails.blocking
  repository_ids    = local.repository_policy_repository_ids
  filepath_patterns = local.repository_policy_guardrails.filepath_patterns
}

resource "azuredevops_repository_policy_author_email_pattern" "this" {
  count = local.repository_policy_guardrails.enabled && length(local.repository_policy_guardrails.author_email_patterns) > 0 ? 1 : 0

  project_id            = azuredevops_project.this.id
  enabled               = local.repository_policy_guardrails.enabled
  blocking              = local.repository_policy_guardrails.blocking
  repository_ids        = local.repository_policy_repository_ids
  author_email_patterns = local.repository_policy_guardrails.author_email_patterns
}

resource "azuredevops_build_definition" "this" {
  for_each = local.build_definitions

  project_id          = azuredevops_project.this.id
  name                = each.value.name
  path                = each.value.path
  queue_status        = each.value.queue_status
  agent_pool_name     = each.value.agent_pool_name
  agent_specification = each.value.agent_specification
  variable_groups = [
    for key in each.value.variable_group_keys : azuredevops_variable_group.this[key].id
    if contains(keys(azuredevops_variable_group.this), key)
  ]

  ci_trigger {
    use_yaml = true
  }

  features {
    skip_first_run = true
  }

  repository {
    repo_type   = "TfsGit"
    repo_id     = azuredevops_git_repository.this[each.value.repository_key].id
    branch_name = each.value.branch_name
    yml_path    = each.value.yml_path
  }

  dynamic "variable" {
    for_each = each.value.variables

    content {
      name  = variable.key
      value = variable.value
    }
  }

  depends_on = [
    azuredevops_git_repository_file.this,
  ]
}

resource "azuredevops_branch_policy_min_reviewers" "this" {
  for_each = {
    for key, policy in local.repository_branch_policy_settings : key => policy
    if policy.enabled
  }

  project_id = azuredevops_project.this.id
  enabled    = each.value.enabled
  blocking   = each.value.blocking

  settings {
    reviewer_count                         = each.value.reviewer_count
    submitter_can_vote                     = each.value.submitter_can_vote
    last_pusher_cannot_approve             = each.value.last_pusher_cannot_approve
    on_push_reset_approved_votes           = each.value.on_push_reset_approved_votes
    allow_completion_with_rejects_or_waits = false

    scope {
      repository_id  = azuredevops_git_repository.this[each.key].id
      repository_ref = azuredevops_git_repository.this[each.key].default_branch
      match_type     = "Exact"
    }
  }

  depends_on = [
    azuredevops_git_repository_file.this,
  ]
}

resource "azuredevops_branch_policy_build_validation" "this" {
  for_each = local.repository_build_validation_policies

  project_id = azuredevops_project.this.id
  enabled    = each.value.enabled
  blocking   = each.value.blocking

  settings {
    build_definition_id         = azuredevops_build_definition.this[each.value.build_definition_key].id
    display_name                = each.value.display_name
    queue_on_source_update_only = each.value.queue_on_source_update_only
    manual_queue_only           = each.value.manual_queue_only
    valid_duration              = each.value.valid_duration
    filename_patterns           = each.value.filename_patterns

    scope {
      repository_id  = azuredevops_git_repository.this[each.value.repository_key].id
      repository_ref = each.value.branch
      match_type     = "Exact"
    }
  }

  depends_on = [
    azuredevops_build_definition.this,
  ]
}

resource "azuredevops_branch_policy_status_check" "this" {
  for_each = local.repository_status_check_policies

  project_id = azuredevops_project.this.id
  enabled    = each.value.enabled
  blocking   = each.value.blocking

  settings {
    name                 = each.value.name
    display_name         = each.value.display_name
    genre                = each.value.genre
    author_id            = each.value.author_id
    invalidate_on_update = each.value.invalidate_on_update
    applicability        = each.value.applicability
    filename_patterns    = each.value.filename_patterns

    scope {
      repository_id  = azuredevops_git_repository.this[each.value.repository_key].id
      repository_ref = each.value.branch
      match_type     = "Exact"
    }
  }

  depends_on = [
    azuredevops_git_repository_file.this,
  ]
}

resource "azuredevops_git_permissions" "this" {
  for_each = local.git_permissions

  project_id    = azuredevops_project.this.id
  repository_id = each.value.repository_key == null ? null : azuredevops_git_repository.this[each.value.repository_key].id
  branch_name   = each.value.branch_name
  principal     = each.value.principal
  permissions   = each.value.permissions
  replace       = each.value.replace
}

resource "azuredevops_branch_policy_comment_resolution" "this" {
  for_each = {
    for key, policy in local.repository_branch_policy_settings : key => policy
    if policy.enabled && policy.comment_resolution_required
  }

  project_id = azuredevops_project.this.id
  enabled    = each.value.enabled
  blocking   = each.value.blocking

  settings {
    scope {
      repository_id  = azuredevops_git_repository.this[each.key].id
      repository_ref = azuredevops_git_repository.this[each.key].default_branch
      match_type     = "Exact"
    }
  }

  depends_on = [
    azuredevops_git_repository_file.this,
  ]
}

resource "azuredevops_branch_policy_work_item_linking" "this" {
  for_each = {
    for key, policy in local.repository_branch_policy_settings : key => policy
    if policy.enabled && policy.work_item_linking_required
  }

  project_id = azuredevops_project.this.id
  enabled    = each.value.enabled
  blocking   = each.value.blocking

  settings {
    scope {
      repository_id  = azuredevops_git_repository.this[each.key].id
      repository_ref = azuredevops_git_repository.this[each.key].default_branch
      match_type     = "Exact"
    }
  }

  depends_on = [
    azuredevops_git_repository_file.this,
  ]
}

resource "azuredevops_branch_policy_merge_types" "this" {
  for_each = {
    for key, policy in local.repository_branch_policy_settings : key => policy
    if policy.enabled && policy.merge_types.enabled
  }

  project_id = azuredevops_project.this.id
  enabled    = each.value.merge_types.enabled
  blocking   = each.value.merge_types.blocking

  settings {
    allow_squash                  = each.value.merge_types.allow_squash
    allow_rebase_and_fast_forward = each.value.merge_types.allow_rebase_and_fast_forward
    allow_rebase_with_merge       = each.value.merge_types.allow_rebase_with_merge
    allow_basic_no_fast_forward   = each.value.merge_types.allow_basic_no_fast_forward

    scope {
      repository_id  = azuredevops_git_repository.this[each.key].id
      repository_ref = azuredevops_git_repository.this[each.key].default_branch
      match_type     = "Exact"
    }
  }

  depends_on = [
    azuredevops_git_repository_file.this,
  ]
}
