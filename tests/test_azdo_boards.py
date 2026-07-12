import unittest
from textwrap import dedent

from scripts.azdo_boards import (
    TfvarsParser,
    board_columns_path,
    desired_boards,
    iteration_path,
    normalize_team_field_values,
    normalize_team_settings,
    normalize_column,
)


class TfvarsParserTest(unittest.TestCase):
    def test_parses_project_team_and_board_shape(self):
        parsed = TfvarsParser(
            '''
            org_service_url = "https://dev.azure.com/example"
            project = {
              name = "demo"
              work_item_template = "Basic"
            }
            teams = {
              platform = {
                name = "Platform"
              }
            }
            boards = {
              platform_issues = {
                team_key = "platform"
                board = "Issues"
                columns = [
                  {
                    name = "To Do"
                    state_mappings = {
                      Issue = "To Do"
                    }
                  }
                ]
              }
            }
            '''
        ).parse()

        self.assertEqual(parsed["project"]["name"], "demo")
        self.assertEqual(parsed["teams"]["platform"]["name"], "Platform")
        self.assertEqual(parsed["boards"]["platform_issues"]["columns"][0]["name"], "To Do")

    def test_skips_heredoc_values_used_elsewhere_in_tfvars(self):
        parsed = TfvarsParser(
            dedent(
                '''
            repository_files = {
              readme = {
                content = <<EOT
            # Demo
            Managed elsewhere.
EOT
              }
            }
            '''
            )
        ).parse()

        self.assertIn("# Demo", parsed["repository_files"]["readme"]["content"])


class BoardConfigTest(unittest.TestCase):
    def test_desired_boards_uses_tfvars_defaults_and_team_name(self):
        config = {
            "project": {"name": "demo"},
            "teams": {"platform": {"name": "Platform"}},
            "boards": {
                "platform_issues": {
                    "team_key": "platform",
                    "board": "Issues",
                    "columns": [
                        {
                            "name": "Doing",
                            "state_mappings": {"Issue": "Doing"},
                        }
                    ],
                }
            },
        }

        boards = desired_boards(config)

        self.assertEqual(boards["platform_issues"]["team"], "Platform")
        self.assertEqual(boards["platform_issues"]["default_area_path"], "demo")
        self.assertEqual(boards["platform_issues"]["backlog_iteration_path"], "demo")
        self.assertEqual(boards["platform_issues"]["default_iteration_macro"], "@CurrentIteration")
        self.assertTrue(boards["platform_issues"]["include_area_children"])

    def test_normalizes_column_defaults_to_azure_devops_payload_shape(self):
        self.assertEqual(
            normalize_column({"name": "To Do", "state_mappings": {"Issue": "To Do"}}),
            {
                "name": "To Do",
                "stateMappings": {"Issue": "To Do"},
                "columnType": "inProgress",
                "itemLimit": 0,
                "isSplit": False,
                "description": "",
            },
        )

    def test_paths_escape_project_team_board_and_iteration_segments(self):
        self.assertEqual(
            board_columns_path("demo project", "Team A", "Backlog items"),
            "/demo%20project/Team%20A/_apis/work/boards/Backlog%20items/columns?api-version=7.1-preview.1",
        )
        self.assertEqual(
            iteration_path("demo project", "demo project\\Release 1"),
            "/demo%20project/_apis/wit/classificationnodes/iterations/Release%201?api-version=7.1",
        )

    def test_normalizes_team_settings_api_shapes_for_drift_checks(self):
        self.assertEqual(
            normalize_team_settings(
                {
                    "backlogIteration": {"identifier": "iteration-guid", "id": 123},
                    "defaultIterationMacro": "@CurrentIteration",
                }
            ),
            {
                "backlogIteration": "iteration-guid",
                "defaultIterationMacro": "@CurrentIteration",
            },
        )
        self.assertEqual(
            normalize_team_field_values(
                {
                    "defaultValue": "demo",
                    "values": [
                        {"value": "demo\\child", "includeChildren": False},
                        {"value": "demo", "includeChildren": True},
                    ],
                }
            ),
            {
                "defaultValue": "demo",
                "values": [
                    {"value": "demo", "includeChildren": True},
                    {"value": "demo\\child", "includeChildren": False},
                ],
            },
        )


if __name__ == "__main__":
    unittest.main()
