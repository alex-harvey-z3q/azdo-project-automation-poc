# AzDO Board Provider Example

This example uses the local `local/azdoboard` provider to manage columns on an
existing Azure DevOps team board.

The main PoC stack now wires this provider into the root Terraform project.
Prefer the root `make plan` and `make apply` workflow for real deployment; this
directory is just a standalone provider reference.

The example assumes the main PoC has already created:

- Project: `azdo-project-automation-poc`
- Team: `Platform`
- Basic-process board: `Issues`

## Build The Provider

From the repository root:

```sh
make provider-build
```

## Configure Terraform To Use The Local Provider

Create or update `~/.terraformrc`:

```hcl
provider_installation {
  dev_overrides {
    "local/azdoboard" = "/Users/alexharvey/git/home/azdo-project-automation-poc/providers/terraform-provider-azdoboard/bin"
  }

  direct {}
}
```

Terraform will emit a warning about provider development overrides. That is
expected for local provider development.

## Deploy

Use the same PAT as the main PoC:

```sh
export TF_VAR_personal_access_token="<your-azdo-pat>"
```

Then from this example directory:

```sh
terraform init
terraform plan
terraform apply
```

If your project uses Agile instead of Basic, change:

```hcl
board = "Issues"
Issue = "To Do"
```

to the board/work item states for that process, such as:

```hcl
board = "Stories"
"User Story" = "New"
```
