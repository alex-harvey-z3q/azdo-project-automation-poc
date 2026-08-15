# Terraform Import Rehearsal

This is a disposable test path for learning how hard it is to bring an existing
Azure DevOps project under Terraform management.

The fixture uses generic placeholder names only. It does not copy any client,
project, package, service connection, variable, or pipeline names from real
Azure DevOps spaces.

## Test Plan

1. Seed a throwaway Azure DevOps project through the REST API.
2. Write the discovered remote IDs to `.terraform/import-seed.json`.
3. Import the core resources into the Terraform addresses used by this PoC.
4. Run a plan against `env/import-test.tfvars`.
5. Record which resources import cleanly, which need hand-built import IDs, and
   which are better reconciled by scripts or recreated by Terraform.

## Seed

Set a PAT with enough rights to create and manage projects:

```sh
export AZDO_PERSONAL_ACCESS_TOKEN="..."
```

Create or update the disposable project:

```sh
make seed-import-candidate
```

Override the defaults if needed:

```sh
make seed-import-candidate \
  ORG_SERVICE_URL="https://dev.azure.com/example-org" \
  IMPORT_PROJECT="azdo-import-poc"
```

The seed script creates a small project shape:

- Project using the Scrum work item process
- `platform` and `application` repositories
- `Platform` and `Application` teams
- `\platform` and `\application` build folders
- Generic non-secret variable groups
- `development`, `test`, and `production` environments
- One generic Azure Artifacts feed
- A project wiki with generic pages

## Import

Import the resources that have predictable provider import IDs:

```sh
make import-seeded
```

Then inspect the drift:

```sh
terraform plan \
  -var-file="env/import-test.tfvars" \
  -var="enable_boards=false"
```

## Expected Findings

The first pass deliberately imports the resources with the cleanest lifecycle:

- Project
- Project pipeline settings
- Project tags
- Git repositories
- Build folders
- Teams
- Variable groups
- Environments
- Artifact feed
- Project wiki

The next layer to test is more fiddly:

- Repository files
- Wiki pages
- Feed retention policy
- Repository guardrail policies
- Branch policies
- Build definitions
- Pipeline authorizations
- Service connections
- Environment approval checks

These usually require exact remote IDs, pre-existing identities, or API details
that are harder to infer from names alone. That friction is the point of this
rehearsal: it tells us which resources are realistic to import and which are
better recreated, reconciled by a script, or kept outside Terraform state.
