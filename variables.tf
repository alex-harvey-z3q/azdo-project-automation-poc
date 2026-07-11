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
  })
  default = {}
}
