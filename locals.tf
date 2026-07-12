locals {
  // Static organisation URL and environment-specific project configuration for this state.
  environment     = var.environment
  org_service_url = trim(var.org_service_url, "/")
  project         = var.project
  repositories    = var.repositories
  teams           = var.teams
  boards = {
    for key, board in var.boards : key => board
    if var.enable_boards && contains(keys(local.teams), board.team_key)
  }
  board_team_settings = {
    for key, board in local.boards : board.team_key => {
      default_area_path       = coalesce(board.default_area_path, local.project.name)
      include_area_children   = board.include_area_children
      backlog_iteration_path  = coalesce(board.backlog_iteration_path, local.project.name)
      default_iteration_macro = board.default_iteration_macro
    }...
  }
  variable_groups = var.variable_groups

  repository_files = {
    for key, file in var.repository_files : key => file
    if contains(keys(local.repositories), file.repository_key)
  }

  build_definitions = {
    for key, definition in var.build_definitions : key => definition
    if contains(keys(local.repositories), definition.repository_key)
  }

  // Azure DevOps project features owned by this stack.
  project_features = {
    boards       = "enabled"
    repositories = "enabled"
    pipelines    = "enabled"
    testplans    = "disabled"
    artifacts    = "disabled"
  }

  repository_branch_policies = var.repository_branch_policies
  repository_branch_policy_overrides = {
    for key, policy in var.repository_branch_policy_overrides : key => policy
    if contains(keys(local.repositories), key)
  }

  branch_policy_repository_keys = length(local.repository_branch_policies.repositories) > 0 ? (
    local.repository_branch_policies.repositories
  ) : toset(keys(local.repositories))

  default_branch_policy_settings = {
    for key in local.branch_policy_repository_keys : key => {
      enabled                      = local.repository_branch_policies.enabled
      blocking                     = local.repository_branch_policies.blocking
      reviewer_count               = local.repository_branch_policies.reviewer_count
      submitter_can_vote           = local.repository_branch_policies.submitter_can_vote
      last_pusher_cannot_approve   = local.repository_branch_policies.last_pusher_cannot_approve
      on_push_reset_approved_votes = local.repository_branch_policies.on_push_reset_approved_votes
      comment_resolution_required  = local.repository_branch_policies.comment_resolution_required
      work_item_linking_required   = local.repository_branch_policies.work_item_linking_required
      merge_types                  = local.repository_branch_policies.merge_types
    }
  }

  repository_branch_policy_settings = merge(
    local.default_branch_policy_settings,
    {
      for key, policy in local.repository_branch_policy_overrides : key => {
        enabled                      = coalesce(policy.enabled, local.repository_branch_policies.enabled)
        blocking                     = coalesce(policy.blocking, local.repository_branch_policies.blocking)
        reviewer_count               = coalesce(policy.reviewer_count, local.repository_branch_policies.reviewer_count)
        submitter_can_vote           = coalesce(policy.submitter_can_vote, local.repository_branch_policies.submitter_can_vote)
        last_pusher_cannot_approve   = coalesce(policy.last_pusher_cannot_approve, local.repository_branch_policies.last_pusher_cannot_approve)
        on_push_reset_approved_votes = coalesce(policy.on_push_reset_approved_votes, local.repository_branch_policies.on_push_reset_approved_votes)
        comment_resolution_required  = coalesce(policy.comment_resolution_required, local.repository_branch_policies.comment_resolution_required)
        work_item_linking_required   = coalesce(policy.work_item_linking_required, local.repository_branch_policies.work_item_linking_required)
        merge_types = {
          enabled                       = coalesce(try(policy.merge_types.enabled, null), local.repository_branch_policies.merge_types.enabled)
          blocking                      = coalesce(try(policy.merge_types.blocking, null), local.repository_branch_policies.merge_types.blocking)
          allow_squash                  = coalesce(try(policy.merge_types.allow_squash, null), local.repository_branch_policies.merge_types.allow_squash)
          allow_rebase_and_fast_forward = coalesce(try(policy.merge_types.allow_rebase_and_fast_forward, null), local.repository_branch_policies.merge_types.allow_rebase_and_fast_forward)
          allow_rebase_with_merge       = coalesce(try(policy.merge_types.allow_rebase_with_merge, null), local.repository_branch_policies.merge_types.allow_rebase_with_merge)
          allow_basic_no_fast_forward   = coalesce(try(policy.merge_types.allow_basic_no_fast_forward, null), local.repository_branch_policies.merge_types.allow_basic_no_fast_forward)
        }
      }
    }
  )

  repository_build_validation_policies = {
    for key, policy in var.repository_build_validation_policies : key => policy
    if contains(keys(local.repositories), policy.repository_key) && contains(keys(local.build_definitions), policy.build_definition_key)
  }

  repository_status_check_policies = {
    for key, policy in var.repository_status_check_policies : key => policy
    if contains(keys(local.repositories), policy.repository_key)
  }

  git_permissions = {
    for key, permission in var.git_permissions : key => permission
    if permission.repository_key == null || contains(keys(local.repositories), permission.repository_key)
  }
}
