# AzDo Project Automation Proof-of-concept

This stack owns a minimal Azure DevOps project inside the existing
`https://dev.azure.com/alexharv074` organisation. The organisation itself is
bootstrap state and is not created by this configuration.

Terraform state is kept local for this proof-of-concept. Do not commit
`terraform.tfstate`, plan files, or local Terraform working directories.

## Managed Resources

`azuredevops_project.this` manages the project, Git version control, the Basic
work item process, and the enabled project features. Boards, Repositories, and
Pipelines are enabled. Test Plans and Artifacts are disabled.

This stack also manages common project-space resources:

- Git repositories declared in `repositories`
- Azure DevOps teams declared in `teams`
- Non-secret variable groups declared in `variable_groups`
- Board column layouts declared in `boards`
- Managed repository files declared in `repository_files`
- YAML build definitions declared in `build_definitions`
- Default-branch pull request policies for managed repositories
- Build-validation branch policies tied to managed build definitions

The current repository policy set demonstrates defaults and per-repository
overrides:

- All managed repositories require pull request reviews, comment resolution,
  and constrained merge strategies.
- `platform` is stricter, requiring two reviewers and linked work items.
- `application` allows squash and rebase/fast-forward merges, and does not
  require linked work items.

The configuration also exposes optional maps for resource types that often need
external identifiers:

- `repository_status_check_policies` for external status checks
- `git_permissions` for group-descriptor-based Git permissions

Service endpoints, agent pools, external package feeds, and inherited process
customisation are intentionally not enabled in the default PoC because they are
organisation-scoped, credential-heavy, or require identifiers that should be
designed before being committed to state.

## Custom Board Provider

Repository files are treated as bootstrap seed files. Terraform creates them
before branch policies exist, then ignores later content drift so protected
branches are not updated directly outside pull requests.

The official Azure DevOps provider does not expose every board setting. This
repository includes a small local provider proof-of-concept at
`providers/terraform-provider-azdoboard`.

It currently configures team Area Path and backlog settings, then manages the
columns of an existing Azure DevOps team board through the Azure DevOps Work
REST API. The root stack wires this provider into the normal `make init`,
`make check`, `make plan`, and `make apply` workflow. `examples/azdoboard-board`
is retained only as a standalone reference.

The Makefile writes a local `.terraformrc` that points Terraform at the provider
binary under `providers/terraform-provider-azdoboard/bin`. Terraform will warn
that provider development overrides are active; that is expected for this PoC.

Build and test it with:

```sh
make provider-check
```

## Outside This State

Keep personal access tokens, repository contents, pipelines, service
connections, variable groups, and organisation-level policy out of this state
unless a reviewed design explicitly accounts for ownership and secret handling.

The Azure DevOps provider requires a PAT at plan and apply time. Prefer passing
it through the current shell instead of writing it to a tfvars file:

```sh
export TF_VAR_personal_access_token="your-pat"
```

For this stack, the PAT needs at least:

- Project and Team: read, write, and manage
- Boards or Work Items: read and write, for board column layout updates
- Code: read, write, and manage
- Build: read and execute
- Variable Groups: read, create, and manage
- Security: manage, if using `git_permissions`

Additional Azure DevOps resources will need matching scopes.

## Make Targets

Common Terraform commands are wrapped by `make`. The default environment is
`prod`, which maps to `env/prod.tfvars`.

```sh
make help
```

Initialise Terraform with local state:

```sh
make init
```

Run local checks:

```sh
make check
```

Create and apply a saved plan:

```sh
make plan
make apply
```

Use another environment by overriding `ENV`:

```sh
make plan ENV=prod
```

## Raw Terraform Commands

The equivalent raw Terraform workflow is kept here for troubleshooting.

## Validate

Initialise Terraform, then run formatting and validation checks:

```sh
terraform init
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

## License

MIT.
