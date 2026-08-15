#!/usr/bin/env python3

"""Create or update Azure DevOps work items from CSV with discoverable local state."""

from __future__ import annotations

import argparse
import base64
import csv
import json
import os
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REQUIRED_COLUMNS = {"ExternalId", "WorkItemType", "Title", "Description", "ParentExternalId"}
STATE_VERSION = 1


class ImportError(ValueError):
    """Raised when the CSV or state file does not form a safe import."""


class AzureDevOpsError(RuntimeError):
    """Raised when Azure DevOps rejects an API request."""


@dataclass(frozen=True)
class WorkItemRow:
    external_id: str
    work_item_type: str
    title: str
    description: str
    parent_external_id: str | None
    parent_work_item_type: str | None = None
    parent_title: str | None = None


class AzureDevOpsClient:
    def __init__(self, org_service_url: str, personal_access_token: str) -> None:
        self.org_service_url = org_service_url.rstrip("/")
        self.token = personal_access_token

    def request(self, method: str, path: str, payload: Any | None = None, *, content_type: str = "application/json") -> Any:
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        headers = {
            "Accept": "application/json",
            "Authorization": "Basic " + base64.b64encode(f":{self.token}".encode("utf-8")).decode("ascii"),
        }
        if data is not None:
            headers["Content-Type"] = content_type

        url = self.org_service_url + path
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                body = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace").strip()
            raise AzureDevOpsError(f"{method} {url} failed with {error.code}: {detail}") from error

        return json.loads(body) if body else None

    def get_work_item(self, project: str, work_item_id: int) -> dict[str, Any] | None:
        try:
            return self.request("GET", f"/{quote(project)}/_apis/wit/workitems/{work_item_id}?$expand=relations&api-version=7.1")
        except AzureDevOpsError as error:
            if " failed with 404:" in str(error):
                return None
            raise

    def find_exact_work_item(
        self, project: str, work_item_type: str, title: str, description: str
    ) -> dict[str, Any] | None:
        query = (
            "SELECT [System.Id] FROM WorkItems "
            "WHERE [System.TeamProject] = @project "
            f"AND [System.WorkItemType] = '{wiql_escape(work_item_type)}' "
            f"AND [System.Title] = '{wiql_escape(title)}'"
        )
        response = self.request("POST", f"/{quote(project)}/_apis/wit/wiql?api-version=7.1", {"query": query})
        matches = response.get("workItems", [])
        if len(matches) > 1:
            ids = ", ".join(str(item["id"]) for item in matches)
            raise ImportError(
                f"Cannot discover {description}: {len(matches)} work items match type {work_item_type!r} "
                f"and title {title!r} (IDs: {ids}). Use a unique title or add the work item ID to the state file explicitly."
            )
        return self.get_work_item(project, int(matches[0]["id"])) if matches else None

    def find_work_item(self, project: str, row: WorkItemRow) -> dict[str, Any] | None:
        return self.find_exact_work_item(project, row.work_item_type, row.title, repr(row.external_id))

    def create_work_item(self, project: str, row: WorkItemRow, parent_id: int | None) -> dict[str, Any]:
        return self.request(
            "POST",
            f"/{quote(project)}/_apis/wit/workitems/${quote(row.work_item_type)}?api-version=7.1",
            work_item_patch(row, parent_id, existing=None),
            content_type="application/json-patch+json",
        )

    def update_work_item(self, project: str, work_item_id: int, row: WorkItemRow, parent_id: int | None, existing: dict[str, Any]) -> dict[str, Any] | None:
        patch = work_item_patch(row, parent_id, existing)
        if not patch:
            return None
        return self.request(
            "PATCH",
            f"/{quote(project)}/_apis/wit/workitems/{work_item_id}?api-version=7.1",
            patch,
            content_type="application/json-patch+json",
        )


def quote(value: str) -> str:
    return urllib.parse.quote(value, safe="")


def wiql_escape(value: str) -> str:
    return value.replace("'", "''")


def get_token() -> str:
    token = os.environ.get("AZDO_PERSONAL_ACCESS_TOKEN") or os.environ.get("TF_VAR_personal_access_token")
    if not token:
        raise ImportError("Set AZDO_PERSONAL_ACCESS_TOKEN or TF_VAR_personal_access_token before running the importer.")
    return token


def read_csv(path: Path) -> list[WorkItemRow]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        headers = set(reader.fieldnames or [])
        missing = sorted(REQUIRED_COLUMNS - headers)
        if missing:
            raise ImportError(f"{path} is missing required columns: {', '.join(missing)}")
        rows = [
            WorkItemRow(
                external_id=(source["ExternalId"] or "").strip(),
                work_item_type=(source["WorkItemType"] or "").strip(),
                title=(source["Title"] or "").strip(),
                description=(source["Description"] or "").strip(),
                parent_external_id=(source["ParentExternalId"] or "").strip() or None,
                parent_work_item_type=(source.get("ParentWorkItemType") or "").strip() or None,
                parent_title=(source.get("ParentTitle") or "").strip() or None,
            )
            for source in reader
        ]
    validate_rows(rows)
    return topological_rows(rows)


def validate_rows(rows: list[WorkItemRow]) -> None:
    if any(not row.external_id or not row.work_item_type or not row.title for row in rows):
        raise ImportError("ExternalId, WorkItemType, and Title must be non-empty for every row.")
    identifiers = [row.external_id for row in rows]
    duplicates = sorted({identifier for identifier in identifiers if identifiers.count(identifier) > 1})
    if duplicates:
        raise ImportError(f"Duplicate ExternalId values: {', '.join(duplicates)}")
    incomplete_parent_lookups = [
        row.external_id
        for row in rows
        if bool(row.parent_work_item_type) != bool(row.parent_title)
    ]
    if incomplete_parent_lookups:
        raise ImportError(
            "ParentWorkItemType and ParentTitle must be provided together for: "
            + ", ".join(incomplete_parent_lookups)
        )


def topological_rows(rows: list[WorkItemRow]) -> list[WorkItemRow]:
    by_external_id = {row.external_id: row for row in rows}
    ordered: list[WorkItemRow] = []
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(external_id: str) -> None:
        if external_id in visited:
            return
        if external_id in visiting:
            raise ImportError(f"Parent relationship cycle includes {external_id!r}.")
        visiting.add(external_id)
        parent = by_external_id[external_id].parent_external_id
        if parent in by_external_id:
            visit(parent)
        visiting.remove(external_id)
        visited.add(external_id)
        ordered.append(by_external_id[external_id])

    for row in rows:
        visit(row.external_id)
    return ordered


def read_state(path: Path, org_service_url: str, project: str) -> dict[str, int]:
    if not path.exists():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        if payload.get("version") != STATE_VERSION or not isinstance(payload.get("work_items"), dict):
            raise ValueError("unsupported format")
        context = payload.get("context", {})
        expected = {"org_service_url": org_service_url.rstrip("/"), "project": project}
        if context != expected:
            raise ValueError(f"belongs to {context!r}, not {expected!r}")
        return {external_id: int(work_item_id) for external_id, work_item_id in payload["work_items"].items()}
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as error:
        raise ImportError(f"Cannot read state file {path}: {error}") from error


def write_state(path: Path, org_service_url: str, project: str, work_items: dict[str, int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": STATE_VERSION,
        "context": {"org_service_url": org_service_url.rstrip("/"), "project": project},
        "work_items": dict(sorted(work_items.items())),
    }
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")
        temporary_path = Path(handle.name)
    temporary_path.replace(path)


def parent_relation_url(parent_id: int) -> str:
    return f"vstfs:///WorkItemTracking/WorkItem/{parent_id}"


def current_parent_id(existing: dict[str, Any]) -> int | None:
    for relation in existing.get("relations", []):
        if relation.get("rel") == "System.LinkTypes.Hierarchy-Reverse":
            try:
                return int(str(relation["url"]).rsplit("/", 1)[1])
            except (KeyError, ValueError):
                raise ImportError(f"Cannot parse existing parent relation: {relation!r}") from None
    return None


def work_item_patch(row: WorkItemRow, parent_id: int | None, existing: dict[str, Any] | None) -> list[dict[str, Any]]:
    desired_fields = {"System.Title": row.title, "System.Description": row.description}
    patch: list[dict[str, Any]] = []
    existing_fields = existing.get("fields", {}) if existing else {}
    for name, value in desired_fields.items():
        if existing is None or existing_fields.get(name) != value:
            patch.append({"op": "add", "path": f"/fields/{name}", "value": value})

    if existing is None and parent_id is not None:
        patch.append({"op": "add", "path": "/relations/-", "value": {"rel": "System.LinkTypes.Hierarchy-Reverse", "url": parent_relation_url(parent_id)}})
    elif existing is not None:
        old_parent_id = current_parent_id(existing)
        if old_parent_id != parent_id:
            for index, relation in enumerate(existing.get("relations", [])):
                if relation.get("rel") == "System.LinkTypes.Hierarchy-Reverse":
                    patch.append({"op": "remove", "path": f"/relations/{index}"})
                    break
            if parent_id is not None:
                patch.append({"op": "add", "path": "/relations/-", "value": {"rel": "System.LinkTypes.Hierarchy-Reverse", "url": parent_relation_url(parent_id)}})
    return patch


def resolve_work_item(client: AzureDevOpsClient, project: str, row: WorkItemRow, state: dict[str, int]) -> dict[str, Any] | None:
    work_item_id = state.get(row.external_id)
    if work_item_id is not None:
        existing = client.get_work_item(project, work_item_id)
        if existing is not None:
            return existing
        del state[row.external_id]
    return client.find_work_item(project, row)


def resolve_parent(
    client: AzureDevOpsClient, project: str, row: WorkItemRow, state: dict[str, int]
) -> tuple[int | None, bool]:
    if not row.parent_external_id and not row.parent_work_item_type:
        return None, False

    parent_id = state.get(row.parent_external_id) if row.parent_external_id else None
    if parent_id is not None:
        # Dry-runs assign negative IDs to planned parents so dependent rows can be previewed.
        if parent_id < 0:
            return parent_id, False
        existing = client.get_work_item(project, parent_id)
        if existing is not None:
            return parent_id, False
        del state[row.parent_external_id]

    if not row.parent_work_item_type or not row.parent_title:
        raise ImportError(
            f"Parent {row.parent_external_id!r} for {row.external_id!r} has no work item ID. "
            "Include that parent in the CSV or provide ParentWorkItemType and ParentTitle for exact remote lookup."
        )

    parent = client.find_exact_work_item(
        project,
        row.parent_work_item_type,
        row.parent_title,
        f"parent of {row.external_id!r}",
    )
    if parent is None:
        raise ImportError(
            f"Cannot find parent for {row.external_id!r}: no {row.parent_work_item_type!r} "
            f"with title {row.parent_title!r} exists in project {project!r}."
        )

    parent_id = int(parent["id"])
    if row.parent_external_id and state.get(row.parent_external_id) != parent_id:
        state[row.parent_external_id] = parent_id
        return parent_id, True
    return parent_id, False


def import_rows(client: AzureDevOpsClient, project: str, rows: list[WorkItemRow], state_path: Path, dry_run: bool) -> int:
    state = read_state(state_path, client.org_service_url, project)
    changed = 0
    state_changed = False
    for row in rows:
        parent_id, parent_state_changed = resolve_parent(client, project, row, state)
        state_changed = state_changed or parent_state_changed

        existing = resolve_work_item(client, project, row, state)
        if existing is None:
            print(f"CREATE {row.external_id} ({row.work_item_type}): {row.title}")
            changed += 1
            if dry_run:
                state[row.external_id] = -(len(state) + 1)
            else:
                created = client.create_work_item(project, row, parent_id)
                state[row.external_id] = int(created["id"])
                write_state(state_path, client.org_service_url, project, state)
            continue

        work_item_id = int(existing["id"])
        if state.get(row.external_id) != work_item_id:
            state[row.external_id] = work_item_id
            state_changed = True
            print(f"ADOPT  {row.external_id} -> work item {work_item_id}")
        existing_type = existing.get("fields", {}).get("System.WorkItemType")
        if existing_type and existing_type != row.work_item_type:
            raise ImportError(
                f"Work item {work_item_id} for {row.external_id!r} is type {existing_type!r}, "
                f"not {row.work_item_type!r}. Azure DevOps work item types cannot be changed by this importer."
            )
        patch = work_item_patch(row, parent_id, existing)
        action = "UPDATE" if patch else "SKIP  "
        print(f"{action} {row.external_id} -> work item {work_item_id}")
        if patch:
            changed += 1
            if not dry_run:
                client.update_work_item(project, work_item_id, row, parent_id, existing)

        if not dry_run and state_changed:
            write_state(state_path, client.org_service_url, project, state)
            state_changed = False

    print(f"{'Would change' if dry_run else 'Changed'} {changed} work item(s).")
    return changed


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    importer = parser.add_subparsers(dest="command", required=True).add_parser("import", help="Create or update work items from CSV.")
    importer.add_argument("--org-service-url", required=True, help="For example: https://dev.azure.com/example")
    importer.add_argument("--project", required=True)
    importer.add_argument("--team", help="Optional operator context; it is not written to work items.")
    importer.add_argument("--csv", required=True, type=Path)
    importer.add_argument("--state-file", required=True, type=Path)
    importer.add_argument("--apply", action="store_true", help="Perform changes and update the state file.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        rows = read_csv(args.csv)
        client = AzureDevOpsClient(args.org_service_url, get_token())
        import_rows(client, args.project, rows, args.state_file, dry_run=not args.apply)
        return 0
    except (AzureDevOpsError, ImportError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
