# AzDo Project Automation Proof-of-concept

This stack demoes a minimal Azure DevOps project.

## Model

```text
Modelled here:

(Org)
|
+-- Terraform local state
|   |
|   +-- azuredevops_project
|   |   +-- Scrum work item process
|   |   +-- Boards feature enabled
|   |   +-- Repositories feature enabled
|   |   +-- Pipelines feature enabled
|   |   +-- Artifacts feature enabled
|   |   +-- Test Plans feature disabled
|   |
|   +-- azuredevops_project_tags
|   |   +-- managed-by-terraform
|   |   +-- proof-of-concept
|   |
|   +-- azuredevops_project_pipeline_settings
|       +-- scoped job tokens
|       +-- protected referenced repositories
|       +-- private status badges
|   |
|   +-- azuredevops_team
|   |   +-- Platform
|   |   +-- Application
|   |
|   +-- azuredevops_git_repository
|   |   +-- platform
|   |   |   +-- README.md
|   |   |   +-- azure-pipelines.yml
|   |   |   +-- docs/project-space.md
|   |   +-- application
|   |       +-- README.md
|   |       +-- azure-pipelines.yml
|   |       +-- docs/project-space.md
|   |
|   +-- azuredevops_build_folder
|   |   +-- \platform
|   |   +-- \application
|   |
|   +-- azuredevops_environment
|   |   +-- development
|   |   +-- test
|   |   +-- production
|   |
|   +-- azuredevops_feed
|   |   +-- internal-packages
|   |       +-- azuredevops_feed_retention_policy
|   |
|   +-- azuredevops_wiki
|   |   +-- /Home
|   |   +-- /Conventions
|   |
|   +-- azuredevops_variable_group
|   |   +-- shared-non-secret
|   |   +-- shared-runtime-settings
|   |   +-- shared-release-settings
|   |
|   +-- azuredevops_build_definition
|   |   +-- platform-ci
|   |   +-- application-ci
|   |
|   +-- azuredevops_repository_policy_*
|   |   +-- maximum file size
|   |   +-- maximum path length
|   |   +-- reserved names
|   |   +-- consistent case
|   |   +-- file path patterns
|   |   +-- author email patterns
|   |
|   +-- Optional placeholders
|   |   +-- azuredevops_serviceendpoint_generic
|   |   +-- azuredevops_pipeline_authorization
|   |   +-- azuredevops_check_approval
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

`azuredevops_project.this` manages the project, Git version control, the Scrum
work item process, and the enabled project features. Boards, Repositories,
Pipelines, and Artifacts are enabled. Test Plans are disabled by default.

This stack also manages common project-space resources:

- Git repositories declared in `repositories`
- Azure DevOps teams declared in `teams`
- Project tags declared in `project_tags`
- Project-level pipeline security settings declared in `project_pipeline_settings`
- Azure Pipelines folders declared in `build_folders`
- Deployment environments declared in `environments`
- Azure Artifacts feeds and retention policies declared in `artifact_feeds`
- Project wiki pages declared in `wiki_pages`
- Non-secret variable groups declared in `variable_groups`
- Managed repository files declared in `repository_files`
- YAML build definitions declared in `build_definitions`
- Repository push guardrails declared in `repository_policy_guardrails`
- Default-branch pull request policies for managed repositories
- Build-validation branch policies tied to managed build definitions

The `env/prod.tfvars` examples intentionally use generic placeholders only.
Service connections, approval checks, and pipeline authorizations are supported
by the code but left empty because they need real endpoint URLs, identity
descriptors, and secret-handling decisions before they are useful.

The current repository policy set demonstrates defaults and per-repository
overrides:

- All managed repositories require pull request reviews, comment resolution,
  and constrained merge strategies.
- `platform` is stricter, requiring two reviewers and linked work items.
- `application` allows squash and rebase/fast-forward merges, and does not
  require linked work items.

The configuration also exposes optional maps for resource types that often need
external identifiers:

- `generic_service_endpoints` for generic service connections
- `pipeline_authorizations` for protected resource authorization
- `environment_approval_checks` for manual environment checks
- `repository_status_check_policies` for external status checks
- `git_permissions` for group-descriptor-based Git permissions

## Custom Board Provider

An example of a custom provider for AzDo boards is also added but disabled
by default. The official Azure DevOps provider does not expose every board
setting. This is in `providers/terraform-provider-azdoboard`.

Build and test it with:

```sh
make provider-check
```

Note that AzDo boards are not standalone resources with clean create and
destroy semantics. Thus a second solution of an idempotent Python script
that configures the board after Terraform has created the project and teams
is also added.

This is in `scripts/azdo_boards.py`.

It reads the same `boards` map from `env/prod.tfvars`, resolves the
Terraform team keys to Azure DevOps team names, updates team Area Path and
backlog settings, and applies the desired board columns through the Azure
DevOps Work REST API.

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

## Permissions

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
