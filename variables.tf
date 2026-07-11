variable "environment" {
  description = "Environment represented by this stack workspace."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "org_service_url" {
  description = "Azure DevOps organisation URL used by the stack."
  type        = string

  validation {
    condition     = can(regex("^https://dev[.]azure[.]com/[^/]+$", var.org_service_url))
    error_message = "org_service_url must use the https://dev.azure.com/{organisation} format without a trailing slash."
  }
}

variable "personal_access_token" {
  description = "Azure DevOps personal access token with permission to create and manage projects."
  type        = string
  sensitive   = true
}

variable "project" {
  description = "Environment-specific Azure DevOps project configuration for this stack."
  type = object({
    name               = string
    description        = string
    visibility         = string
    work_item_template = string
  })

  validation {
    condition     = contains(["private", "public"], var.project.visibility)
    error_message = "project.visibility must be either private or public."
  }

  validation {
    condition     = contains(["Agile", "Basic", "CMMI", "Scrum"], var.project.work_item_template)
    error_message = "project.work_item_template must be one of Agile, Basic, CMMI, or Scrum."
  }
}

variable "repositories" {
  description = "Git repositories owned by this project space."
  type = map(object({
    name           = string
    default_branch = optional(string, "refs/heads/main")
    disabled       = optional(bool, false)
  }))
  default = {}
}

variable "teams" {
  description = "Azure DevOps teams owned by this project space."
  type = map(object({
    name = string
  }))
  default = {}
}

variable "variable_groups" {
  description = "Non-secret Azure DevOps variable groups owned by this project space."
  type = map(object({
    name         = string
    description  = optional(string, "Managed by Terraform.")
    allow_access = optional(bool, false)
    variables    = optional(map(string), {})
  }))
  default = {}
}

variable "repository_files" {
  description = "Files committed into managed Git repositories."
  type = map(object({
    repository_key      = string
    file                = string
    content             = string
    branch              = optional(string, "refs/heads/main")
    commit_message      = optional(string, "Manage file with Terraform")
    overwrite_on_create = optional(bool, true)
  }))
  default = {}
}

variable "build_definitions" {
  description = "YAML build definitions backed by managed Azure Repos repositories."
  type = map(object({
    name                = string
    repository_key      = string
    yml_path            = string
    path                = optional(string, "\\")
    branch_name         = optional(string, "refs/heads/main")
    queue_status        = optional(string, "enabled")
    agent_pool_name     = optional(string, "Azure Pipelines")
    agent_specification = optional(string, "ubuntu-latest")
    variable_group_keys = optional(set(string), [])
    variables           = optional(map(string), {})
  }))
  default = {}
}

variable "repository_branch_policies" {
  description = "Default branch pull request policies applied to managed repositories."
  type = object({
    enabled                      = optional(bool, true)
    blocking                     = optional(bool, true)
    reviewer_count               = optional(number, 1)
    submitter_can_vote           = optional(bool, false)
    last_pusher_cannot_approve   = optional(bool, true)
    on_push_reset_approved_votes = optional(bool, true)
    comment_resolution_required  = optional(bool, true)
    work_item_linking_required   = optional(bool, false)
    repositories                 = optional(set(string), [])
    merge_types = optional(object({
      enabled                       = optional(bool, true)
      blocking                      = optional(bool, true)
      allow_squash                  = optional(bool, true)
      allow_rebase_and_fast_forward = optional(bool, false)
      allow_rebase_with_merge       = optional(bool, false)
      allow_basic_no_fast_forward   = optional(bool, false)
    }), {})
  })
  default = {}
}

variable "repository_build_validation_policies" {
  description = "Build validation branch policies keyed by policy name."
  type = map(object({
    repository_key              = string
    build_definition_key        = string
    display_name                = string
    enabled                     = optional(bool, true)
    blocking                    = optional(bool, true)
    branch                      = optional(string, "refs/heads/main")
    queue_on_source_update_only = optional(bool, true)
    manual_queue_only           = optional(bool, false)
    valid_duration              = optional(number, 720)
    filename_patterns           = optional(list(string), [])
  }))
  default = {}
}

variable "repository_status_check_policies" {
  description = "External status check branch policies keyed by policy name."
  type = map(object({
    repository_key       = string
    name                 = string
    display_name         = optional(string)
    genre                = optional(string)
    author_id            = optional(string)
    enabled              = optional(bool, true)
    blocking             = optional(bool, true)
    branch               = optional(string, "refs/heads/main")
    invalidate_on_update = optional(bool, true)
    applicability        = optional(string, "default")
    filename_patterns    = optional(list(string), [])
  }))
  default = {}
}

variable "git_permissions" {
  description = "Optional Git permissions. Principals must be Azure DevOps group descriptors."
  type = map(object({
    principal      = string
    permissions    = map(string)
    repository_key = optional(string)
    branch_name    = optional(string)
    replace        = optional(bool, false)
  }))
  default = {}
}

variable "repository_branch_policy_overrides" {
  description = "Repository-specific pull request policy overrides keyed by repository map key."
  type = map(object({
    enabled                      = optional(bool)
    blocking                     = optional(bool)
    reviewer_count               = optional(number)
    submitter_can_vote           = optional(bool)
    last_pusher_cannot_approve   = optional(bool)
    on_push_reset_approved_votes = optional(bool)
    comment_resolution_required  = optional(bool)
    work_item_linking_required   = optional(bool)
    merge_types = optional(object({
      enabled                       = optional(bool)
      blocking                      = optional(bool)
      allow_squash                  = optional(bool)
      allow_rebase_and_fast_forward = optional(bool)
      allow_rebase_with_merge       = optional(bool)
      allow_basic_no_fast_forward   = optional(bool)
    }))
  }))
  default = {}
}
