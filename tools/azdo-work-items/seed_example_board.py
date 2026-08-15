#!/usr/bin/env python3

"""Seed a repeatable Scrum hierarchy for Azure DevOps importer testing."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from typing import Any

from azdo_work_items import AzureDevOpsClient, AzureDevOpsError, ImportError, get_token, parent_relation_url, quote, wiql_escape


@dataclass(frozen=True)
class ExampleWorkItem:
    key: str
    work_item_type: str
    title: str
    description: str
    parent_key: str | None


def example_work_items(
    epic_state: str,
    feature_state: str,
    pbi_state: str,
    task_state: str,
) -> list[tuple[ExampleWorkItem, str]]:
    items = [
        ExampleWorkItem("EPIC-PLATFORM", "Epic", "Example: Platform foundation", "Example Epic used for CSV importer testing.", None),
        ExampleWorkItem("FEATURE-DELIVERY", "Feature", "Example: Delivery pipeline", "Example Feature used for CSV importer testing.", "EPIC-PLATFORM"),
        ExampleWorkItem("PBI-VALIDATION", "Product Backlog Item", "Example: Validation workflow", "Example PBI used for CSV importer testing.", "FEATURE-DELIVERY"),
        ExampleWorkItem("TASK-VALIDATION", "Task", "Example: Configure validation", "Example Task used for CSV importer testing.", "PBI-VALIDATION"),
        ExampleWorkItem("TASK-INTEGRATION", "Task", "Example: Run integration checks", "Example Task used for CSV importer testing.", "PBI-VALIDATION"),
        ExampleWorkItem("PBI-PUBLISH", "Product Backlog Item", "Example: Artifact publication", "Example PBI used for CSV importer testing.", "FEATURE-DELIVERY"),
        ExampleWorkItem("TASK-PUBLISH", "Task", "Example: Publish an artifact", "Example Task used for CSV importer testing.", "PBI-PUBLISH"),
        ExampleWorkItem("FEATURE-OBSERVABILITY", "Feature", "Example: Observability", "Example Feature used for CSV importer testing.", "EPIC-PLATFORM"),
        ExampleWorkItem("PBI-DASHBOARDS", "Product Backlog Item", "Example: Operational dashboards", "Example PBI used for CSV importer testing.", "FEATURE-OBSERVABILITY"),
        ExampleWorkItem("TASK-DASHBOARDS", "Task", "Example: Add dashboards", "Example Task used for CSV importer testing.", "PBI-DASHBOARDS"),
        ExampleWorkItem("EPIC-EXPERIENCE", "Epic", "Example: Product experience", "Example Epic used for CSV importer testing.", None),
        ExampleWorkItem("FEATURE-WORKFLOW", "Feature", "Example: Backlog workflow", "Example Feature used for CSV importer testing.", "EPIC-EXPERIENCE"),
        ExampleWorkItem("PBI-WORKFLOW", "Product Backlog Item", "Example: Workflow refinement", "Example PBI used for CSV importer testing.", "FEATURE-WORKFLOW"),
        ExampleWorkItem("TASK-WORKFLOW", "Task", "Example: Define workflow", "Example Task used for CSV importer testing.", "PBI-WORKFLOW"),
    ]
    states = {"Epic": epic_state, "Feature": feature_state, "Product Backlog Item": pbi_state, "Task": task_state}
    return [(item, states[item.work_item_type]) for item in items]


def exact_matches(client: AzureDevOpsClient, project: str, item: ExampleWorkItem) -> list[dict[str, Any]]:
    query = (
        "SELECT [System.Id] FROM WorkItems "
        "WHERE [System.TeamProject] = @project "
        f"AND [System.WorkItemType] = '{wiql_escape(item.work_item_type)}' "
        f"AND [System.Title] = '{wiql_escape(item.title)}'"
    )
    response = client.request("POST", f"/{quote(project)}/_apis/wit/wiql?api-version=7.1", {"query": query})
    return [client.get_work_item(project, int(match["id"])) for match in response.get("workItems", [])]


def current_parent_id(existing: dict[str, Any]) -> int | None:
    for relation in existing.get("relations", []):
        if relation.get("rel") == "System.LinkTypes.Hierarchy-Reverse":
            return int(str(relation["url"]).rsplit("/", 1)[1])
    return None


def patch_for(item: ExampleWorkItem, state: str, parent_id: int | None, existing: dict[str, Any] | None) -> list[dict[str, Any]]:
    fields = {"System.Title": item.title, "System.Description": item.description, "System.State": state}
    patch = []
    existing_fields = existing.get("fields", {}) if existing else {}
    for name, value in fields.items():
        if existing is None or existing_fields.get(name) != value:
            patch.append({"op": "add", "path": f"/fields/{name}", "value": value})
    if existing is None and parent_id is not None:
        patch.append({"op": "add", "path": "/relations/-", "value": {"rel": "System.LinkTypes.Hierarchy-Reverse", "url": parent_relation_url(parent_id)}})
    elif existing is not None and current_parent_id(existing) != parent_id:
        for index, relation in enumerate(existing.get("relations", [])):
            if relation.get("rel") == "System.LinkTypes.Hierarchy-Reverse":
                patch.append({"op": "remove", "path": f"/relations/{index}"})
                break
        if parent_id is not None:
            patch.append({"op": "add", "path": "/relations/-", "value": {"rel": "System.LinkTypes.Hierarchy-Reverse", "url": parent_relation_url(parent_id)}})
    return patch


def verify_process(client: AzureDevOpsClient, project: str, desired_states: dict[str, set[str]]) -> None:
    types = client.request("GET", f"/{quote(project)}/_apis/wit/workitemtypes?api-version=7.1").get("value", [])
    available_types = {item.get("name") for item in types}
    missing_types = set(desired_states) - available_types
    if missing_types:
        raise ImportError(f"Project {project!r} does not provide: {', '.join(sorted(missing_types))}. Use a Scrum-based project.")
    for work_item_type, expected_states in desired_states.items():
        states = client.request("GET", f"/{quote(project)}/_apis/wit/workitemtypes/{quote(work_item_type)}/states?api-version=7.1").get("value", [])
        available_states = {item.get("name") for item in states}
        missing_states = expected_states - available_states
        if missing_states:
            raise ImportError(
                f"{work_item_type} states are missing: {', '.join(sorted(missing_states))}. "
                f"Available states: {', '.join(sorted(available_states))}"
            )


def seed(
    client: AzureDevOpsClient,
    project: str,
    epic_state: str,
    feature_state: str,
    pbi_state: str,
    task_state: str,
    dry_run: bool,
) -> int:
    desired_states = {
        "Epic": {epic_state},
        "Feature": {feature_state},
        "Product Backlog Item": {pbi_state},
        "Task": {task_state},
    }
    verify_process(client, project, desired_states)
    ids: dict[str, int] = {}
    changed = 0
    for item, state in example_work_items(epic_state, feature_state, pbi_state, task_state):
        parent_id = ids.get(item.parent_key) if item.parent_key else None
        matches = exact_matches(client, project, item)
        if len(matches) > 1:
            ids_text = ", ".join(str(match["id"]) for match in matches)
            raise ImportError(f"Fixture item {item.key!r} has multiple exact matches (IDs: {ids_text}). Remove duplicates before seeding.")
        existing = matches[0] if matches else None
        patch = patch_for(item, state, parent_id, existing)
        if existing is None:
            print(f"CREATE {item.key}: {item.title}")
            changed += 1
            if dry_run:
                ids[item.key] = -(len(ids) + 1)
            else:
                created = client.request(
                    "POST",
                    f"/{quote(project)}/_apis/wit/workitems/${quote(item.work_item_type)}?api-version=7.1",
                    patch,
                    content_type="application/json-patch+json",
                )
                ids[item.key] = int(created["id"])
        else:
            ids[item.key] = int(existing["id"])
            action = "UPDATE" if patch else "SKIP  "
            print(f"{action} {item.key} -> work item {existing['id']}")
            if patch:
                changed += 1
                if not dry_run:
                    client.request(
                        "PATCH",
                        f"/{quote(project)}/_apis/wit/workitems/{existing['id']}?api-version=7.1",
                        patch,
                        content_type="application/json-patch+json",
                    )
    print(f"{'Would create or update' if dry_run else 'Created or updated'} {changed} work item(s).")
    return changed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--org-service-url", required=True)
    parser.add_argument("--project", required=True, help="An existing Scrum-based Azure DevOps project.")
    parser.add_argument("--epic-state", default="New")
    parser.add_argument("--feature-state", default="New")
    parser.add_argument("--pbi-state", default="New")
    parser.add_argument("--task-state", default="To Do")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args(argv)
    try:
        seed(
            AzureDevOpsClient(args.org_service_url, get_token()),
            args.project,
            args.epic_state,
            args.feature_state,
            args.pbi_state,
            args.task_state,
            not args.apply,
        )
        return 0
    except (AzureDevOpsError, ImportError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
