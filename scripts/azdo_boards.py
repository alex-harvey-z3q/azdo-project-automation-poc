#!/usr/bin/env python3

"""Reconcile Azure DevOps board settings from the project tfvars file."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any


class TfvarsError(ValueError):
    pass


@dataclass(frozen=True)
class Token:
    kind: str
    value: Any
    line: int


class TfvarsParser:
    def __init__(self, source: str) -> None:
        self.tokens = list(self._tokenize(source))
        self.pos = 0

    def parse(self) -> dict[str, Any]:
        result: dict[str, Any] = {}
        while not self._at("eof"):
            name = self._expect("ident").value
            self._expect("=")
            result[name] = self._value()
            self._optional(",")
        return result

    def _value(self) -> Any:
        if self._at("{"):
            return self._object()
        if self._at("["):
            return self._list()
        if self._at("string"):
            return self._advance().value
        if self._at("number"):
            return self._advance().value
        if self._at("bool"):
            return self._advance().value
        token = self._peek()
        raise TfvarsError(f"Expected value at line {token.line}, got {token.kind!r}.")

    def _object(self) -> dict[str, Any]:
        result: dict[str, Any] = {}
        self._expect("{")
        while not self._at("}"):
            key = self._advance()
            if key.kind not in {"ident", "string"}:
                raise TfvarsError(f"Expected object key at line {key.line}, got {key.kind!r}.")
            self._expect("=")
            result[str(key.value)] = self._value()
            self._optional(",")
        self._expect("}")
        return result

    def _list(self) -> list[Any]:
        result: list[Any] = []
        self._expect("[")
        while not self._at("]"):
            result.append(self._value())
            self._optional(",")
        self._expect("]")
        return result

    def _tokenize(self, source: str) -> list[Token]:
        tokens: list[Token] = []
        index = 0
        line = 1
        length = len(source)
        while index < length:
            char = source[index]

            if char.isspace():
                line += char == "\n"
                index += 1
                continue

            if source.startswith("//", index) or char == "#":
                newline = source.find("\n", index)
                if newline == -1:
                    break
                index = newline + 1
                line += 1
                continue

            if char in "{}[]=,":
                tokens.append(Token(char, char, line))
                index += 1
                continue

            if source.startswith("<<", index):
                match = re.match(r"<<-?([A-Za-z_][A-Za-z0-9_]*)", source[index:])
                if not match:
                    raise TfvarsError(f"Invalid heredoc marker at line {line}.")
                marker = match.group(1)
                start = index + match.end()
                if start < length and source[start] == "\r":
                    start += 1
                if start < length and source[start] == "\n":
                    start += 1
                end_match = re.search(rf"(?m)^{re.escape(marker)}\s*$", source[start:])
                if not end_match:
                    raise TfvarsError(f"Unterminated heredoc {marker!r} at line {line}.")
                value = source[start : start + end_match.start()]
                tokens.append(Token("string", value.rstrip("\n"), line))
                consumed = source[index : start + end_match.end()]
                line += consumed.count("\n")
                index = start + end_match.end()
                continue

            if char == '"':
                value, index, line = self._read_string(source, index, line)
                tokens.append(Token("string", value, line))
                continue

            number_match = re.match(r"-?[0-9]+(?:[.][0-9]+)?", source[index:])
            if number_match:
                raw = number_match.group(0)
                value: int | float = float(raw) if "." in raw else int(raw)
                tokens.append(Token("number", value, line))
                index += len(raw)
                continue

            ident_match = re.match(r"[A-Za-z_][A-Za-z0-9_-]*", source[index:])
            if ident_match:
                raw = ident_match.group(0)
                if raw in {"true", "false"}:
                    tokens.append(Token("bool", raw == "true", line))
                else:
                    tokens.append(Token("ident", raw, line))
                index += len(raw)
                continue

            raise TfvarsError(f"Unexpected character {char!r} at line {line}.")

        tokens.append(Token("eof", None, line))
        return tokens

    def _read_string(self, source: str, index: int, line: int) -> tuple[str, int, int]:
        index += 1
        value = []
        while index < len(source):
            char = source[index]
            if char == '"':
                return "".join(value), index + 1, line
            if char == "\\":
                index += 1
                if index >= len(source):
                    break
                escapes = {"n": "\n", "r": "\r", "t": "\t", '"': '"', "\\": "\\"}
                value.append(escapes.get(source[index], source[index]))
            else:
                value.append(char)
                line += char == "\n"
            index += 1
        raise TfvarsError(f"Unterminated string at line {line}.")

    def _peek(self) -> Token:
        return self.tokens[self.pos]

    def _advance(self) -> Token:
        token = self._peek()
        self.pos += 1
        return token

    def _at(self, kind: str) -> bool:
        return self._peek().kind == kind

    def _expect(self, kind: str) -> Token:
        token = self._advance()
        if token.kind != kind:
            raise TfvarsError(f"Expected {kind!r} at line {token.line}, got {token.kind!r}.")
        return token

    def _optional(self, kind: str) -> bool:
        if self._at(kind):
            self._advance()
            return True
        return False


class AzureDevOpsClient:
    def __init__(self, org_service_url: str, personal_access_token: str) -> None:
        self.base_url = org_service_url.rstrip("/")
        self.token = personal_access_token

    def request(self, method: str, path: str, payload: Any | None = None) -> Any:
        data = None
        headers = {
            "Accept": "application/json",
            "Authorization": "Basic "
            + base64.b64encode(f":{self.token}".encode("utf-8")).decode("ascii"),
        }
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"

        request = urllib.request.Request(
            self.base_url + path,
            data=data,
            headers=headers,
            method=method,
        )

        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                body = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace").strip()
            raise RuntimeError(f"{method} {path} failed with {error.code}: {detail}") from error

        if not body:
            return None
        return json.loads(body)


def parse_tfvars(path: str) -> dict[str, Any]:
    with open(path, encoding="utf-8") as handle:
        return TfvarsParser(handle.read()).parse()


def quoted_path(*segments: str) -> str:
    return "/".join(urllib.parse.quote(segment, safe="") for segment in segments)


def board_columns_path(project: str, team: str, board: str) -> str:
    return f"/{quoted_path(project, team)}/_apis/work/boards/{urllib.parse.quote(board, safe='')}/columns?api-version=7.1-preview.1"


def team_settings_path(project: str, team: str) -> str:
    return f"/{quoted_path(project, team)}/_apis/work/teamsettings?api-version=7.1-preview.1"


def team_field_values_path(project: str, team: str) -> str:
    return f"/{quoted_path(project, team)}/_apis/work/teamsettings/teamfieldvalues?api-version=7.1-preview.1"


def iteration_path(project: str, iteration_path_value: str) -> str:
    relative = iteration_path_value.strip()
    prefix = project + "\\"
    if relative == project:
        relative = ""
    elif relative.startswith(prefix):
        relative = relative[len(prefix) :]

    if not relative:
        return f"/{urllib.parse.quote(project, safe='')}/_apis/wit/classificationnodes/iterations?api-version=7.1"

    return (
        f"/{urllib.parse.quote(project, safe='')}/_apis/wit/classificationnodes/iterations/"
        + quoted_path(*relative.split("\\"))
        + "?api-version=7.1"
    )


def normalize_column(column: dict[str, Any]) -> dict[str, Any]:
    normalized = {
        "name": column["name"],
        "stateMappings": column.get("state_mappings", column.get("stateMappings", {})),
        "columnType": column.get("column_type", column.get("columnType", "inProgress")),
        "itemLimit": int(column.get("item_limit", column.get("itemLimit", 0)) or 0),
        "isSplit": bool(column.get("is_split", column.get("isSplit", False))),
        "description": column.get("description", ""),
    }
    if column.get("id"):
        normalized["id"] = column["id"]
    return normalized


def column_summary(columns: list[dict[str, Any]]) -> list[str]:
    return [
        f"{column['name']}[{column.get('columnType', '')}; limit={column.get('itemLimit', 0)}; split={column.get('isSplit', False)}]"
        for column in columns
    ]


def normalize_team_field_values(values: dict[str, Any]) -> dict[str, Any]:
    return {
        "defaultValue": values.get("defaultValue", ""),
        "values": sorted(
            [
                {
                    "value": value.get("value", ""),
                    "includeChildren": bool(value.get("includeChildren", False)),
                }
                for value in values.get("values", [])
            ],
            key=lambda value: value["value"],
        ),
    }


def normalize_team_settings(settings: dict[str, Any]) -> dict[str, Any]:
    backlog = settings.get("backlogIteration", {})
    if isinstance(backlog, dict):
        backlog_value = str(backlog.get("identifier") or backlog.get("id") or "")
    else:
        backlog_value = str(backlog or "")
    return {
        "backlogIteration": backlog_value,
        "defaultIterationMacro": settings.get("defaultIterationMacro", ""),
    }


def resolve_iteration_id(client: AzureDevOpsClient, project: str, iteration_name: str) -> str:
    node = client.request("GET", iteration_path(project, iteration_name))
    identifier = node.get("identifier")
    if identifier:
        return str(identifier)
    node_id = node.get("id")
    if node_id is None:
        raise RuntimeError(f"Iteration path {iteration_name!r} did not return id or identifier.")
    return str(node_id)


def desired_boards(config: dict[str, Any], selected: set[str] | None = None) -> dict[str, dict[str, Any]]:
    project = config["project"]
    teams = config.get("teams", {})
    boards = config.get("boards", {})
    result: dict[str, dict[str, Any]] = {}
    for key, board in boards.items():
        if selected and key not in selected:
            continue
        team_key = board["team_key"]
        if team_key not in teams:
            print(f"Skipping {key}: unknown team_key {team_key!r}.", file=sys.stderr)
            continue
        result[key] = {
            "project": project["name"],
            "team": teams[team_key]["name"],
            "board": board["board"],
            "default_area_path": board.get("default_area_path") or project["name"],
            "include_area_children": board.get("include_area_children", True),
            "backlog_iteration_path": board.get("backlog_iteration_path") or project["name"],
            "default_iteration_macro": board.get("default_iteration_macro", "@CurrentIteration"),
            "columns": [normalize_column(column) for column in board["columns"]],
        }
    return result


def reconcile_board(client: AzureDevOpsClient, key: str, desired: dict[str, Any], apply: bool) -> bool:
    project = desired["project"]
    team = desired["team"]
    board = desired["board"]
    changed = False

    print(f"\n{key}: {project}/{team}/{board}")

    iteration_id = resolve_iteration_id(client, project, desired["backlog_iteration_path"])
    field_patch = {
        "defaultValue": desired["default_area_path"],
        "values": [
            {
                "value": desired["default_area_path"],
                "includeChildren": desired["include_area_children"],
            }
        ],
    }
    settings_patch = {
        "backlogIteration": iteration_id,
        "defaultIterationMacro": desired["default_iteration_macro"],
    }

    current_field_values = normalize_team_field_values(
        client.request("GET", team_field_values_path(project, team))
    )
    desired_field_values = normalize_team_field_values(field_patch)
    field_changed = current_field_values != desired_field_values

    current_settings = normalize_team_settings(client.request("GET", team_settings_path(project, team)))
    desired_settings = normalize_team_settings(settings_patch)
    settings_changed = current_settings != desired_settings

    if not field_changed and not settings_changed:
        print("  team settings: already match")
    elif apply:
        client.request("PATCH", team_field_values_path(project, team), field_patch)
        client.request("PATCH", team_settings_path(project, team), settings_patch)
        print("  team settings: applied")
    else:
        print("  team settings: would change")
        if field_changed:
            print(f"    current field: {current_field_values}")
            print(f"    desired field: {desired_field_values}")
        if settings_changed:
            print(f"    current settings: {current_settings}")
            print(f"    desired settings: {desired_settings}")
    changed = field_changed or settings_changed

    current_response = client.request("GET", board_columns_path(project, team, board))
    current_columns = current_response.get("value", current_response)
    current_by_name = {column["name"]: column for column in current_columns}
    desired_columns = []
    for column in desired["columns"]:
        with_id = dict(column)
        if column["name"] in current_by_name:
            with_id["id"] = current_by_name[column["name"]].get("id", "")
        desired_columns.append(with_id)

    current_summary = column_summary([normalize_column(column) for column in current_columns])
    desired_summary = column_summary(desired_columns)
    if current_summary == desired_summary:
        print("  columns: already match")
    elif apply:
        client.request("PUT", board_columns_path(project, team, board), desired_columns)
        print("  columns: applied")
    else:
        print("  columns: would change")
        print(f"    current: {', '.join(current_summary)}")
        print(f"    desired: {', '.join(desired_summary)}")
    changed = changed or current_summary != desired_summary

    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--var-file", default="env/prod.tfvars", help="Terraform tfvars file to read.")
    parser.add_argument("--apply", action="store_true", help="Apply changes. Without this, run in dry-run mode.")
    parser.add_argument("--board", action="append", help="Board key to reconcile. Can be passed more than once.")
    args = parser.parse_args()

    token = os.environ.get("AZDO_PERSONAL_ACCESS_TOKEN") or os.environ.get("TF_VAR_personal_access_token")
    if not token:
        print(
            "Set AZDO_PERSONAL_ACCESS_TOKEN or TF_VAR_personal_access_token before running board reconciliation.",
            file=sys.stderr,
        )
        return 2

    config = parse_tfvars(args.var_file)
    boards = desired_boards(config, set(args.board) if args.board else None)
    if not boards:
        print("No matching boards declared.")
        return 0

    client = AzureDevOpsClient(config["org_service_url"], token)
    print("Mode:", "apply" if args.apply else "dry-run")
    changed = False
    for key in sorted(boards):
        changed = reconcile_board(client, key, boards[key], args.apply) or changed

    if args.apply:
        print("\nBoard reconciliation complete.")
    elif changed:
        print("\nDry-run complete. Re-run with --apply to make these changes.")
    else:
        print("\nDry-run complete. No board column changes detected.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
