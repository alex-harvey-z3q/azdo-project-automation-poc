# Azure DevOps Work Item CSV Importer

`azdo_work_items.py` is a standalone command-line tool for creating and updating Azure DevOps work items from CSV. It does not depend on the Terraform configuration in this repository and does not add tags, comments, custom fields, or other metadata to work items.

## Prerequisites

- Python 3.10 or later.
- An Azure DevOps PAT with **Work Items: Read & write** scope.
- `AZDO_PERSONAL_ACCESS_TOKEN` or `TF_VAR_personal_access_token` set in the environment.

## CSV Format

The import CSV must contain these columns:

```csv
ExternalId,WorkItemType,Title,Description,ParentExternalId
EPIC-001,Epic,Project foundation,Initial platform capability,
FEATURE-001,Feature,Provision project space,Create the baseline project space,EPIC-001
```

- `ExternalId`: stable CSV-local key. It is used to identify the row in local state and to resolve `ParentExternalId`. It is not written to Azure DevOps.
- `WorkItemType`, `Title`, `Description`: desired work item values. Existing items are updated only when title, description, or parent differs. Azure DevOps does not allow changing a work item type, so a type mismatch fails safely.
- `ParentExternalId`: optional stable key for a parent elsewhere in the same CSV or an already-known parent in local state. Parents included in the CSV are processed before children even when rows are unordered.

To add cards below a parent that already exists on the board, add these optional columns:

```csv
ExternalId,WorkItemType,Title,Description,ParentExternalId,ParentWorkItemType,ParentTitle
FEATURE-002,Feature,Improve delivery quality,Make delivery evidence visible,,Epic,Project foundation
```

- `ParentWorkItemType` and `ParentTitle`: an exact remote parent lookup. They must be supplied together. This is the useful mode for an additions-only CSV: the parent need not be in the CSV or state file.
- When both a `ParentExternalId` and the remote-parent fields are present, the importer uses the state mapping first and falls back to the exact remote lookup. A discovered parent ID is then cached under `ParentExternalId`.

## Identity Resolution

For every row, the importer follows this sequence:

1. Look up `ExternalId` in the specified local state file.
2. If it is absent or points to a deleted item, search Azure DevOps using an exact project, work-item-type, and title match.
3. If exactly one remote item matches, record its ID in state and update it as needed.
4. If no remote item matches, create it and record the new ID in state.
5. If more than one remote item matches, stop rather than guessing.

The state file is a recoverable cache, not a prerequisite. It contains the organisation URL, project, and `ExternalId` to work-item-ID mappings, so it cannot accidentally be reused against another Azure DevOps project.

## Import

Run a dry-run first. It calls Azure DevOps to resolve existing items but makes no Azure DevOps or state-file changes:

```sh
export AZDO_PERSONAL_ACCESS_TOKEN="your-pat"

python3 azdo_work_items.py import \
  --org-service-url https://dev.azure.com/example \
  --project example-project \
  --team Platform \
  --csv example-backlog.csv \
  --state-file .azdo-work-items/state.json
```

Apply after reviewing the dry run:

```sh
python3 azdo_work_items.py import \
  --org-service-url https://dev.azure.com/example \
  --project example-project \
  --team Platform \
  --csv example-backlog.csv \
  --state-file .azdo-work-items/state.json \
  --apply
```

State is updated after each successful discovery or create. An interrupted import can therefore be rerun safely; completed rows are resolved from state and remaining rows continue normally.

## Add Cards to an Existing Board

After seeding the example board below, `example-board-additions.csv` adds eight realistic cards to it. It creates a Feature under the existing `Example: Platform foundation` Epic, a PBI and two Tasks beneath that Feature, and two further PBIs with Tasks beneath the existing Observability and Backlog workflow Features.

Preview the additions against the project created by this proof of concept:

```sh
python3 azdo_work_items.py import \
  --org-service-url https://dev.azure.com/alexharv074 \
  --project azdo-project-automation-poc \
  --csv example-board-additions.csv \
  --state-file .azdo-work-items/example-additions-state.json
```

Apply them after reviewing the preview:

```sh
python3 azdo_work_items.py import \
  --org-service-url https://dev.azure.com/alexharv074 \
  --project azdo-project-automation-poc \
  --csv example-board-additions.csv \
  --state-file .azdo-work-items/example-additions-state.json \
  --apply
```

Run the same command again to verify idempotency: it should report `SKIP` for all eight cards and `Changed 0 work item(s).` The state file is created during this first apply; no separate state-generation pass is necessary.

## Seed a Test Board

`seed_example_board.py` seeds an existing Scrum-based project with a stable example backlog for importer tests: two Epics, three Features, four Product Backlog Items, and five Tasks. All Tasks use the configured initial state (`To Do` by default). The team board is the built-in Azure DevOps surface for these work items; this script does not create a separate custom board.

Preview the fixture:

```sh
python3 seed_example_board.py \
  --org-service-url https://dev.azure.com/example \
  --project example-project
```

Create or reconcile it:

```sh
python3 seed_example_board.py \
  --org-service-url https://dev.azure.com/example \
  --project example-project \
  --apply
```

The fixture is represented by `example-seeded-board.csv`, which can then be passed to `azdo_work_items.py import` to test API discovery and state-file creation. This project uses `New` for Epics, Features, and PBIs, and `To Do` for Tasks. Supply the individual state options when an inherited process uses different names.
