resource "azuredevops_project" "this" {
  name               = local.project.name
  description        = local.project.description
  visibility         = local.project.visibility
  version_control    = "Git"
  work_item_template = local.project.work_item_template

  features = local.project_features
}
