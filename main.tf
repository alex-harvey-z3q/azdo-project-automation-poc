resource "azuredevops_project" "this" {
  name               = local.project.name
  description        = local.project.description
  visibility         = local.project.visibility
  version_control    = "Git"
  work_item_template = local.project.work_item_template

  features = local.project_features
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

resource "azuredevops_team" "this" {
  for_each = local.teams

  project_id = azuredevops_project.this.id
  name       = each.value.name
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
}
