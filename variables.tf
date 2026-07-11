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
