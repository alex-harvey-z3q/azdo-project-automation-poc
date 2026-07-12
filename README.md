# AzDo Project Automation Proof-of-concept

This stack demoes a minimal Azure DevOps project. The organisation itself is
bootstrap state and is not created by this configuration.

Terraform state is kept local for this proof-of-concept.

## Model

```text
Modelled here:

(Org)
|
+-- Terraform local state
|   |
|   +-- azuredevops_project
|   |   +-- Basic work item process
|   |   +-- Boards feature enabled
|   |   +-- Repositories feature enabled
|   |   +-- Pipelines feature enabled
|   |
|   +-- azuredevops_team
|   |   +-- Platform
|   |   +-- Application
|   |
|   +-- azuredevops_git_repository
|   |   +-- platform
|   |   |   +-- README.md
|   |   |   +-- azure-pipelines.yml
|   |   +-- application
|   |       +-- README.md
|   |       +-- azure-pipelines.yml
|   |
|   +-- azuredevops_variable_group
|   |   +-- shared-non-secret
|   |
|   +-- azuredevops_build_definition
|   |   +-- platform-ci
|   |   +-- application-ci
|   |
|   +-- azuredevops_branch_policy_*
|       +-- minimum reviewers
|       +-- comment resolution
|       +-- work item linking
|       +-- merge strategy
|       +-- build validation
|
+-- Board reconciliation outside Terraform
    |
    +-- scripts/azdo_boards.py
        +-- team Area Path settings
        +-- team backlog iteration settings
        +-- board columns for declared team boards
```

## Managed Resources

`azuredevops_project.this` manages the project, Git version control, the Basic
work item process, and the enabled project features. Boards, Repositories, and
Pipelines are enabled. Test Plans and Artifacts are disabled.

This stack also manages common project-space resources:

- Git repositories declared in `repositories`
- Azure DevOps teams declared in `teams`
- Non-secret variable groups declared in `variable_groups`
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

It can configure team Area Path and backlog settings, then manage the columns
of an existing Azure DevOps team board through the Azure DevOps Work REST API.
This is disabled by default because Azure DevOps boards are built-in team
surfaces and do not have useful destroy semantics. Set `ENABLE_BOARDS=true`
when planning to opt in to this part of the PoC. `examples/azdoboard-board` is
retained only as a standalone reference.

The Makefile writes a local `.terraformrc` that points Terraform at the provider
binary under `providers/terraform-provider-azdoboard/bin`. Terraform will warn
that provider development overrides are active; that is expected for this PoC.

Build and test it with:

```sh
make provider-check
```

## Note about modeling AzDo boards

Azure DevOps team boards are not standalone resources with clean create and
destroy semantics. The better fit for board setup is an idempotent
reconciliation step that configures the board after Terraform has
created the project and teams.

This repository includes that parallel path in `scripts/azdo_boards.py`. It
reads the same `boards` map from `env/prod.tfvars`, resolves the Terraform team
keys to Azure DevOps team names, updates team Area Path and backlog settings,
and applies the desired board columns through the Azure DevOps Work REST API.

Run a dry-run first:

```sh
make boards-plan
```

Apply the board settings:

```sh
make boards-apply
```

The reconciler uses `AZDO_PERSONAL_ACCESS_TOKEN` or
`TF_VAR_personal_access_token`. It does not use Terraform state, provider
development overrides, or `~/.terraformrc`.

## Outside This State

The Azure DevOps provider expects a PAT at plan and apply time:

```sh
export TF_VAR_personal_access_token="your-pat"
```

For this stack, the PAT needs at least:

- Project and Team: read, write, and manage
- Code: read, write, and manage
- Build: read and execute
- Variable Groups: read, create, and manage
- Security: manage, if using `git_permissions`

When `ENABLE_BOARDS=true`, the PAT also needs Boards or Work Items read/write
access for board layout updates.

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

Board management is off by default. Opt in explicitly:

```sh
make plan ENABLE_BOARDS=true
make apply
```

Use another environment by overriding `ENV`:

```sh
make plan ENV=prod
```

## License

MIT.
