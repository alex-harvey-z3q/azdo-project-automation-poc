#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_NAME="${ENV_NAME:-import-test}"
VAR_FILE="${VAR_FILE:-env/${ENV_NAME}.tfvars}"
MANIFEST="${MANIFEST:-.terraform/import-seed.json}"
TF_CLI_CONFIG_FILE="${TF_CLI_CONFIG_FILE:-${ROOT_DIR}/.terraformrc}"
PROJECT_NAME="${AZDO_IMPORT_PROJECT:-azdo-import-poc}"
ORG_SERVICE_URL="${AZDO_ORG_SERVICE_URL:-https://dev.azure.com/alexharv074}"

export TF_CLI_CONFIG_FILE

if [[ -z "${AZDO_PERSONAL_ACCESS_TOKEN:-${TF_VAR_personal_access_token:-}}" ]]; then
  echo "Set AZDO_PERSONAL_ACCESS_TOKEN or TF_VAR_personal_access_token before importing." >&2
  exit 1
fi

token="${AZDO_PERSONAL_ACCESS_TOKEN:-${TF_VAR_personal_access_token:-}}"
export TF_VAR_personal_access_token="${TF_VAR_personal_access_token:-$token}"
auth_header="Authorization: Basic $(printf ':%s' "$token" | base64)"
accept_header="Accept: application/json"

api_get() {
  local url="$1"
  curl -fsS -H "$accept_header" -H "$auth_header" "$url"
}

json_get() {
  local filter="$1"
  jq -er "$filter" "$MANIFEST"
}

import_if_missing() {
  local address="$1"
  local import_id="$2"

  if terraform state show "$address" >/dev/null 2>&1; then
    echo "Already imported: $address"
    return
  fi

  echo "Importing $address <= $import_id"
  terraform import -var-file="$VAR_FILE" "$address" "$import_id"
}

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found at $MANIFEST; querying Azure DevOps by generic fixture names." >&2
  mkdir -p "$(dirname "$MANIFEST")"

  project_json="$(api_get "${ORG_SERVICE_URL}/_apis/projects/${PROJECT_NAME}?api-version=7.1")"
  project_id="$(jq -er '.id' <<<"$project_json")"

  teams_json="$(api_get "${ORG_SERVICE_URL}/_apis/projects/${project_id}/teams?api-version=7.1")"
  repos_json="$(api_get "${ORG_SERVICE_URL}/${PROJECT_NAME}/_apis/git/repositories?api-version=7.1")"
  variable_groups_json="$(api_get "${ORG_SERVICE_URL}/${PROJECT_NAME}/_apis/distributedtask/variablegroups?api-version=7.1-preview.2")"
  environments_json="$(api_get "${ORG_SERVICE_URL}/${PROJECT_NAME}/_apis/distributedtask/environments?api-version=7.1-preview.1")"
  feeds_json="$(api_get "https://feeds.dev.azure.com/${ORG_SERVICE_URL##*/}/${PROJECT_NAME}/_apis/packaging/feeds?api-version=7.1-preview.1")"
  wikis_json="$(api_get "${ORG_SERVICE_URL}/${PROJECT_NAME}/_apis/wiki/wikis?api-version=7.1")"

  jq -n \
    --arg org "$ORG_SERVICE_URL" \
    --arg project_name "$PROJECT_NAME" \
    --arg project_id "$project_id" \
    --argjson teams "$teams_json" \
    --argjson repos "$repos_json" \
    --argjson groups "$variable_groups_json" \
    --argjson environments "$environments_json" \
    --argjson feeds "$feeds_json" \
    --argjson wikis "$wikis_json" \
    '{
      org_service_url: $org,
      project: {name: $project_name, id: $project_id},
      teams: {
        platform: ($teams.value[] | select(.name == "Platform") | {name, id}),
        application: ($teams.value[] | select(.name == "Application") | {name, id})
      },
      repositories: {
        platform: ($repos.value[] | select(.name == "platform") | {name, id}),
        application: ($repos.value[] | select(.name == "application") | {name, id})
      },
      build_folders: {
        platform: {path: "\\platform"},
        application: {path: "\\application"}
      },
      variable_groups: {
        shared: ($groups.value[] | select(.name == "shared-non-secret") | {name, id}),
        shared_runtime: ($groups.value[] | select(.name == "shared-runtime-settings") | {name, id})
      },
      environments: {
        development: ($environments.value[] | select(.name == "development") | {name, id}),
        test: ($environments.value[] | select(.name == "test") | {name, id}),
        production: ($environments.value[] | select(.name == "production") | {name, id})
      },
      artifact_feeds: {
        internal_packages: ($feeds.value[] | select(.name == "internal-packages") | {name, id})
      },
      wiki: ($wikis.value[] | select(.name == ($project_name + ".wiki")) | {name, id})
    }' > "$MANIFEST"
fi

project_id="$(json_get '.project.id')"

import_if_missing 'azuredevops_project.this' "$project_id"
import_if_missing 'azuredevops_project_tags.this[0]' "$project_id"
import_if_missing 'azuredevops_project_pipeline_settings.this' "$project_id"

import_if_missing 'azuredevops_git_repository.this["platform"]' "${project_id}/$(json_get '.repositories.platform.id')"
import_if_missing 'azuredevops_git_repository.this["application"]' "${project_id}/$(json_get '.repositories.application.id')"

import_if_missing 'azuredevops_build_folder.this["platform"]' "${project_id}/$(json_get '.build_folders.platform.path')"
import_if_missing 'azuredevops_build_folder.this["application"]' "${project_id}/$(json_get '.build_folders.application.path')"

import_if_missing 'azuredevops_team.this["platform"]' "${project_id}/$(json_get '.teams.platform.id')"
import_if_missing 'azuredevops_team.this["application"]' "${project_id}/$(json_get '.teams.application.id')"

import_if_missing 'azuredevops_variable_group.this["shared"]' "${project_id}/$(json_get '.variable_groups.shared.id')"
import_if_missing 'azuredevops_variable_group.this["shared_runtime"]' "${project_id}/$(json_get '.variable_groups.shared_runtime.id')"

import_if_missing 'azuredevops_environment.this["development"]' "${project_id}/$(json_get '.environments.development.id')"
import_if_missing 'azuredevops_environment.this["test"]' "${project_id}/$(json_get '.environments.test.id')"
import_if_missing 'azuredevops_environment.this["production"]' "${project_id}/$(json_get '.environments.production.id')"

import_if_missing 'azuredevops_feed.this["internal_packages"]' "${project_id}/$(json_get '.artifact_feeds.internal_packages.id')"

import_if_missing 'azuredevops_wiki.project[0]' "${project_id}/$(json_get '.wiki.id')"

echo
echo "Core imports complete. Next run:"
echo "  terraform plan -var-file=\"$VAR_FILE\" -var=\"enable_boards=false\""
echo
echo "Expect some drift while you discover exact import IDs for files, wiki pages, feed retention,"
echo "project tags, build folders, and repository guardrails. Those are the useful sharp edges"
echo "this rehearsal is meant to expose."
