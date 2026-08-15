#!/usr/bin/env python3

"""Seed a disposable Azure DevOps project for Terraform import rehearsal."""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


ZERO_OBJECT_ID = "0000000000000000000000000000000000000000"


class AzureDevOpsError(RuntimeError):
    pass


class AzureDevOpsClient:
    def __init__(self, org_service_url: str, token: str) -> None:
        self.org_service_url = org_service_url.rstrip("/")
        parsed = urllib.parse.urlparse(self.org_service_url)
        self.org_name = parsed.path.strip("/").split("/")[0]
        self.token = token

    def request(
        self,
        method: str,
        path: str,
        payload: Any | None = None,
        *,
        base_url: str | None = None,
        ok_statuses: set[int] | None = None,
    ) -> Any:
        ok_statuses = ok_statuses or {200, 201, 202, 203, 204}
        data = None
        headers = {
            "Accept": "application/json",
            "Authorization": "Basic "
            + base64.b64encode(f":{self.token}".encode("utf-8")).decode("ascii"),
        }
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"

        url = (base_url or self.org_service_url) + path
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                body = response.read()
                status = response.status
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace").strip()
            if error.code in ok_statuses:
                return json.loads(detail) if detail else None
            raise AzureDevOpsError(f"{method} {url} failed with {error.code}: {detail}") from error

        if status not in ok_statuses:
            raise AzureDevOpsError(f"{method} {url} returned unexpected status {status}")
        if not body:
            return None
        return json.loads(body)

    def packaging_request(self, method: str, project: str, path: str, payload: Any | None = None) -> Any:
        base_url = f"https://feeds.dev.azure.com/{self.org_name}/{quote(project)}"
        return self.request(method, path, payload, base_url=base_url)


def quote(value: str) -> str:
    return urllib.parse.quote(value, safe="")


def get_token() -> str:
    token = os.environ.get("AZDO_PERSONAL_ACCESS_TOKEN") or os.environ.get("TF_VAR_personal_access_token")
    if not token:
        raise SystemExit("Set AZDO_PERSONAL_ACCESS_TOKEN or TF_VAR_personal_access_token before running this script.")
    return token


def get_process_template_id(client: AzureDevOpsClient, process_name: str) -> str:
    response = client.request("GET", "/_apis/process/processes?api-version=7.1")
    for process in response.get("value", []):
        if process.get("name") == process_name:
            return process["id"]
    names = ", ".join(sorted(process.get("name", "") for process in response.get("value", [])))
    raise AzureDevOpsError(f"Process template {process_name!r} was not found. Available: {names}")


def get_project(client: AzureDevOpsClient, project_name: str) -> dict[str, Any] | None:
    try:
        return client.request("GET", f"/_apis/projects/{quote(project_name)}?api-version=7.1")
    except AzureDevOpsError as error:
        if "failed with 404" in str(error):
            return None
        raise


def wait_for_operation(client: AzureDevOpsClient, operation_id: str) -> None:
    for _ in range(60):
        operation = client.request("GET", f"/_apis/operations/{quote(operation_id)}?api-version=7.1")
        status = operation.get("status")
        if status == "succeeded":
            return
        if status in {"failed", "cancelled"}:
            raise AzureDevOpsError(f"Project operation {operation_id} ended with {status}: {operation}")
        time.sleep(5)
    raise AzureDevOpsError(f"Timed out waiting for operation {operation_id}")


def ensure_project(client: AzureDevOpsClient, project_name: str) -> dict[str, Any]:
    project = get_project(client, project_name)
    if project:
        print(f"Project exists: {project_name}")
        return project

    template_id = get_process_template_id(client, "Scrum")
    payload = {
        "name": project_name,
        "description": "Disposable Azure DevOps project used to test Terraform import coverage.",
        "visibility": "private",
        "capabilities": {
            "versioncontrol": {"sourceControlType": "Git"},
            "processTemplate": {"templateTypeId": template_id},
        },
    }
    operation = client.request("POST", "/_apis/projects?api-version=7.1", payload)
    wait_for_operation(client, operation["id"])
    print(f"Created project: {project_name}")
    project = get_project(client, project_name)
    if not project:
        raise AzureDevOpsError(f"Project {project_name!r} was created but could not be fetched.")
    return project


def list_by_name(values: list[dict[str, Any]], name: str) -> dict[str, Any] | None:
    for value in values:
        if value.get("name") == name:
            return value
    return None


def ensure_team(client: AzureDevOpsClient, project: dict[str, Any], name: str) -> dict[str, Any]:
    project_id = project["id"]
    response = client.request("GET", f"/_apis/projects/{quote(project_id)}/teams?api-version=7.1")
    existing = list_by_name(response.get("value", []), name)
    if existing:
        print(f"Team exists: {name}")
        return existing
    team = client.request("POST", f"/_apis/projects/{quote(project_id)}/teams?api-version=7.1", {"name": name})
    print(f"Created team: {name}")
    return team


def ensure_repository(client: AzureDevOpsClient, project_name: str, project_id: str, name: str) -> dict[str, Any]:
    response = client.request("GET", f"/{quote(project_name)}/_apis/git/repositories?api-version=7.1")
    existing = list_by_name(response.get("value", []), name)
    if existing:
        print(f"Repository exists: {name}")
        return existing
    repo = client.request(
        "POST",
        f"/{quote(project_name)}/_apis/git/repositories?api-version=7.1",
        {"name": name, "project": {"id": project_id}},
    )
    print(f"Created repository: {name}")
    return repo


def get_main_ref(client: AzureDevOpsClient, project_name: str, repo_id: str) -> dict[str, Any] | None:
    refs = client.request(
        "GET",
        f"/{quote(project_name)}/_apis/git/repositories/{quote(repo_id)}/refs?filter=heads/main&api-version=7.1",
    )
    values = refs.get("value", [])
    return values[0] if values else None


def seed_repository_files(client: AzureDevOpsClient, project_name: str, repo: dict[str, Any], label: str) -> None:
    repo_id = repo["id"]
    main_ref = get_main_ref(client, project_name, repo_id)
    old_object_id = main_ref["objectId"] if main_ref else ZERO_OBJECT_ID
    change_type = "edit" if main_ref else "add"
    content_label = "platform" if label == "platform" else "application"
    payload = {
        "refUpdates": [{"name": "refs/heads/main", "oldObjectId": old_object_id}],
        "commits": [
            {
                "comment": f"Seed {content_label} import rehearsal files",
                "changes": [
                    {
                        "changeType": change_type,
                        "item": {"path": "/README.md"},
                        "newContent": {
                            "content": f"# {content_label.title()}\n\nSeeded for Terraform import rehearsal.\n",
                            "contentType": "rawtext",
                        },
                    },
                    {
                        "changeType": change_type,
                        "item": {"path": "/azure-pipelines.yml"},
                        "newContent": {
                            "content": (
                                "trigger:\n"
                                "- main\n\n"
                                "pool:\n"
                                "  vmImage: ubuntu-latest\n\n"
                                "steps:\n"
                                f"- script: echo \"Validate {content_label} import rehearsal\"\n"
                                "  displayName: Validate\n"
                            ),
                            "contentType": "rawtext",
                        },
                    },
                ],
            }
        ],
    }
    client.request(
        "POST",
        f"/{quote(project_name)}/_apis/git/repositories/{quote(repo_id)}/pushes?api-version=7.1",
        payload,
    )
    print(f"Seeded repository files: {repo['name']}")


def ensure_variable_group(client: AzureDevOpsClient, project_name: str, project_id: str, name: str, variables: dict[str, str]) -> dict[str, Any]:
    response = client.request("GET", f"/{quote(project_name)}/_apis/distributedtask/variablegroups?api-version=7.1-preview.2")
    for group in response.get("value", []):
        if group.get("name") == name:
            print(f"Variable group exists: {name}")
            return group
    variable_payload = {key: {"value": value, "isSecret": False} for key, value in variables.items()}
    payload = {
        "type": "Vsts",
        "name": name,
        "description": "Generic non-secret variables for import rehearsal.",
        "variables": variable_payload,
        "variableGroupProjectReferences": [
            {
                "name": name,
                "projectReference": {"id": project_id, "name": project_name},
            }
        ],
    }
    group = client.request("POST", f"/{quote(project_name)}/_apis/distributedtask/variablegroups?api-version=7.1-preview.2", payload)
    print(f"Created variable group: {name}")
    return group


def ensure_environment(client: AzureDevOpsClient, project_name: str, name: str, description: str) -> dict[str, Any]:
    response = client.request("GET", f"/{quote(project_name)}/_apis/distributedtask/environments?api-version=7.1-preview.1")
    existing = list_by_name(response.get("value", []), name)
    if existing:
        print(f"Environment exists: {name}")
        return existing
    environment = client.request(
        "POST",
        f"/{quote(project_name)}/_apis/distributedtask/environments?api-version=7.1-preview.1",
        {"name": name, "description": description},
    )
    print(f"Created environment: {name}")
    return environment


def ensure_build_folder(client: AzureDevOpsClient, project_name: str, path: str, description: str) -> dict[str, Any]:
    encoded_path = urllib.parse.quote(path, safe="")
    folder = client.request(
        "PUT",
        f"/{quote(project_name)}/_apis/build/folders/{encoded_path}?api-version=7.1",
        {"path": path, "description": description},
    )
    print(f"Ensured build folder: {path}")
    return folder


def ensure_feed(client: AzureDevOpsClient, project_name: str, name: str) -> dict[str, Any]:
    response = client.packaging_request("GET", project_name, "/_apis/packaging/feeds?api-version=7.1-preview.1")
    existing = list_by_name(response.get("value", []), name)
    if existing:
        print(f"Feed exists: {name}")
        return existing
    feed = client.packaging_request(
        "POST",
        project_name,
        "/_apis/packaging/feeds?api-version=7.1-preview.1",
        {"name": name},
    )
    print(f"Created feed: {name}")
    return feed


def ensure_project_wiki(client: AzureDevOpsClient, project_name: str, name: str) -> dict[str, Any]:
    response = client.request("GET", f"/{quote(project_name)}/_apis/wiki/wikis?api-version=7.1")
    existing = list_by_name(response.get("value", []), name)
    if existing:
        print(f"Wiki exists: {name}")
        return existing
    wiki = client.request(
        "POST",
        f"/{quote(project_name)}/_apis/wiki/wikis?api-version=7.1",
        {"name": name, "type": "projectWiki"},
    )
    print(f"Created wiki: {name}")
    return wiki


def put_wiki_page(client: AzureDevOpsClient, project_name: str, wiki_id: str, path: str, content: str) -> None:
    encoded_path = urllib.parse.quote(path, safe="")
    client.request(
        "PUT",
        f"/{quote(project_name)}/_apis/wiki/wikis/{quote(wiki_id)}/pages?path={encoded_path}&api-version=7.1",
        {"content": content},
        ok_statuses={200, 201},
    )
    print(f"Seeded wiki page: {path}")


def write_manifest(path: Path, manifest: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Wrote manifest: {path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--org-service-url", default=os.environ.get("AZDO_ORG_SERVICE_URL", "https://dev.azure.com/alexharv074"))
    parser.add_argument("--project-name", default=os.environ.get("AZDO_IMPORT_PROJECT", "azdo-import-poc"))
    parser.add_argument("--manifest", default=".terraform/import-seed.json")
    args = parser.parse_args()

    client = AzureDevOpsClient(args.org_service_url, get_token())
    project = ensure_project(client, args.project_name)
    project_id = project["id"]
    project_name = project["name"]

    teams = {
        "platform": ensure_team(client, project, "Platform"),
        "application": ensure_team(client, project, "Application"),
    }

    repositories = {
        "platform": ensure_repository(client, project_name, project_id, "platform"),
        "application": ensure_repository(client, project_name, project_id, "application"),
    }
    for key, repo in repositories.items():
        seed_repository_files(client, project_name, repo, key)

    variable_groups = {
        "shared": ensure_variable_group(
            client,
            project_name,
            project_id,
            "shared-non-secret",
            {"ENVIRONMENT": "import-test", "OWNER": "seed-script"},
        ),
        "shared_runtime": ensure_variable_group(
            client,
            project_name,
            project_id,
            "shared-runtime-settings",
            {"LOG_LEVEL": "info", "SERVICE_NAMESPACE": "example", "DEPLOYMENT_RING": "placeholder"},
        ),
    }

    build_folders = {
        "platform": ensure_build_folder(client, project_name, "\\platform", "Build definitions for platform examples."),
        "application": ensure_build_folder(client, project_name, "\\application", "Build definitions for application examples."),
    }

    environments = {
        "development": ensure_environment(client, project_name, "development", "Placeholder deployment environment for early validation."),
        "test": ensure_environment(client, project_name, "test", "Placeholder deployment environment for pre-production validation."),
        "production": ensure_environment(client, project_name, "production", "Placeholder deployment environment for production release gates."),
    }

    feeds = {
        "internal_packages": ensure_feed(client, project_name, "internal-packages"),
    }

    wiki = ensure_project_wiki(client, project_name, f"{project_name}.wiki")
    put_wiki_page(client, project_name, wiki["id"], "/Home", "# Project Space\n\nSeeded for Terraform import rehearsal.\n")
    put_wiki_page(
        client,
        project_name,
        wiki["id"],
        "/Conventions",
        "# Conventions\n\n- Use repository-specific pipelines for CI.\n- Store secrets outside Terraform state.\n",
    )

    manifest = {
        "org_service_url": args.org_service_url.rstrip("/"),
        "project": {"name": project_name, "id": project_id},
        "teams": {key: {"name": value["name"], "id": value["id"]} for key, value in teams.items()},
        "repositories": {key: {"name": value["name"], "id": value["id"]} for key, value in repositories.items()},
        "build_folders": {key: {"path": value["path"]} for key, value in build_folders.items()},
        "variable_groups": {key: {"name": value["name"], "id": value["id"]} for key, value in variable_groups.items()},
        "environments": {key: {"name": value["name"], "id": value["id"]} for key, value in environments.items()},
        "artifact_feeds": {key: {"name": value["name"], "id": value["id"]} for key, value in feeds.items()},
        "wiki": {"name": wiki["name"], "id": wiki["id"]},
        "wiki_pages": {"home": {"path": "/Home"}, "conventions": {"path": "/Conventions"}},
    }
    write_manifest(Path(args.manifest), manifest)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AzureDevOpsError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
