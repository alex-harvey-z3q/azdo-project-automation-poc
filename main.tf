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
  for_each = local.repository_branch_policies.enabled ? local.branch_policy_repository_keys : toset([])

  project_id = azuredevops_project.this.id
  enabled    = local.repository_branch_policies.enabled
  blocking   = local.repository_branch_policies.blocking

  settings {
    reviewer_count                         = local.repository_branch_policies.reviewer_count
    submitter_can_vote                     = local.repository_branch_policies.submitter_can_vote
    last_pusher_cannot_approve             = local.repository_branch_policies.last_pusher_cannot_approve
    on_push_reset_approved_votes           = local.repository_branch_policies.on_push_reset_approved_votes
    allow_completion_with_rejects_or_waits = false

    scope {
      repository_id  = azuredevops_git_repository.this[each.key].id
      repository_ref = azuredevops_git_repository.this[each.key].default_branch
      match_type     = "Exact"
    }
  }
}

resource "azuredevops_branch_policy_comment_resolution" "this" {
  for_each = local.repository_branch_policies.comment_resolution_required ? local.branch_policy_repository_keys : toset([])

  project_id = azuredevops_project.this.id
  enabled    = local.repository_branch_policies.enabled
  blocking   = local.repository_branch_policies.blocking

  settings {
    scope {
      repository_id  = azuredevops_git_repository.this[each.key].id
      repository_ref = azuredevops_git_repository.this[each.key].default_branch
      match_type     = "Exact"
    }
  }
}

resource "azuredevops_branch_policy_work_item_linking" "this" {
  for_each = local.repository_branch_policies.work_item_linking_required ? local.branch_policy_repository_keys : toset([])

  project_id = azuredevops_project.this.id
  enabled    = local.repository_branch_policies.enabled
  blocking   = local.repository_branch_policies.blocking

  settings {
    scope {
      repository_id  = azuredevops_git_repository.this[each.key].id
      repository_ref = azuredevops_git_repository.this[each.key].default_branch
      match_type     = "Exact"
    }
  }
}
