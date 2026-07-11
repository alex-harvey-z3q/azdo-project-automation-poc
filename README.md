# AzDo Project Automation Proof-of-concept

This stack owns a minimal Azure DevOps project inside the existing
`https://dev.azure.com/alexharv074` organisation. The organisation itself is
bootstrap state and is not created by this configuration.

## Managed Resources

`azuredevops_project.this` manages the project, Git version control, the Basic
work item process, and the enabled project features. Boards, Repositories, and
Pipelines are enabled. Test Plans and Artifacts are disabled.

## Outside This State

Keep personal access tokens, repository contents, pipelines, service
connections, variable groups, and organisation-level policy out of this state
unless a reviewed design explicitly accounts for ownership and secret handling.

The Azure DevOps provider requires a PAT at plan and apply time. Prefer passing
it through the current shell instead of writing it to a tfvars file:

```sh
export TF_VAR_personal_access_token="your-pat"
```

For this stack, the PAT needs at least Project and Team read, write, and manage
permission. Additional Azure DevOps resources will need matching scopes.

## Validate

Initialise Terraform with the same backend configuration pattern used by the
Keystone stacks, then run formatting and validation checks:

```sh
terraform init \
  -backend-config="resource_group_name=<state-resource-group>" \
  -backend-config="storage_account_name=<state-storage-account>" \
  -backend-config="container_name=<state-container>"
terraform fmt -check
terraform validate
```

## Plan And Apply

```sh
terraform plan -var-file=env/prod.tfvars
terraform apply -var-file=env/prod.tfvars
```

After apply completes, open the emitted `project_url` output.

## Tear Down

For a disposable project only:

```sh
terraform destroy -var-file=env/prod.tfvars
```

Do not destroy this state once the project contains useful repositories, boards,
pipelines, service connections, or other project assets.
