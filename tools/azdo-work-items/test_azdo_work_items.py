import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("azdo_work_items.py")
SPEC = importlib.util.spec_from_file_location("azdo_work_items", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def row(external_id, title=None, parent_external_id=None, parent_work_item_type=None, parent_title=None):
    return MODULE.WorkItemRow(
        external_id,
        "Feature",
        title or external_id,
        "Description",
        parent_external_id,
        parent_work_item_type,
        parent_title,
    )


def item(work_item_id, title, description="Description", parent_id=None):
    relations = [] if parent_id is None else [{"rel": "System.LinkTypes.Hierarchy-Reverse", "url": MODULE.parent_relation_url(parent_id)}]
    return {"id": work_item_id, "fields": {"System.WorkItemType": "Feature", "System.Title": title, "System.Description": description}, "relations": relations}


class Client:
    org_service_url = "https://dev.azure.com/example"

    def __init__(self, discovered=None, stored=None, exact_matches=None):
        self.discovered = discovered or {}
        self.stored = stored or {}
        self.exact_matches = exact_matches or {}
        self.creates = []
        self.updates = []

    def get_work_item(self, project, work_item_id):
        return self.stored.get(work_item_id)

    def find_work_item(self, project, work_item):
        return self.discovered.get(work_item.external_id)

    def find_exact_work_item(self, project, work_item_type, title, description):
        return self.exact_matches.get((work_item_type, title))

    def create_work_item(self, project, work_item, parent_id):
        self.creates.append((work_item.external_id, parent_id))
        work_item_id = 100 + len(self.creates)
        created = item(work_item_id, work_item.title, work_item.description, parent_id)
        created["fields"]["System.WorkItemType"] = work_item.work_item_type
        self.stored[work_item_id] = created
        return created

    def update_work_item(self, project, work_item_id, work_item, parent_id, existing):
        self.updates.append((work_item_id, parent_id))
        return {"id": work_item_id}


class WorkItemImportTests(unittest.TestCase):
    def test_topological_rows_orders_parent_before_child(self):
        self.assertEqual([item.external_id for item in MODULE.topological_rows([row("child", parent_external_id="parent"), row("parent")])], ["parent", "child"])

    def test_validate_rows_requires_complete_remote_parent_lookup(self):
        with self.assertRaisesRegex(MODULE.ImportError, "provided together"):
            MODULE.validate_rows([row("child", parent_work_item_type="Epic")])

    def test_work_item_patch_only_changes_drifted_values(self):
        existing = item(101, "Old title")
        self.assertEqual(MODULE.work_item_patch(row("feature", "New title"), None, existing), [{"op": "add", "path": "/fields/System.Title", "value": "New title"}])

    def test_work_item_patch_replaces_parent(self):
        self.assertEqual(
            MODULE.work_item_patch(row("child"), 34, item(101, "child", parent_id=12)),
            [
                {"op": "remove", "path": "/relations/0"},
                {"op": "add", "path": "/relations/-", "value": {"rel": "System.LinkTypes.Hierarchy-Reverse", "url": "vstfs:///WorkItemTracking/WorkItem/34"}},
            ],
        )

    def test_state_round_trip_is_scoped_to_organisation_and_project(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            MODULE.write_state(path, "https://dev.azure.com/example", "project", {"FEATURE-001": 101})
            self.assertEqual(MODULE.read_state(path, "https://dev.azure.com/example", "project"), {"FEATURE-001": 101})
            with self.assertRaisesRegex(MODULE.ImportError, "belongs to"):
                MODULE.read_state(path, "https://dev.azure.com/example", "other-project")

    def test_discovery_adopts_existing_work_item_into_state(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            client = Client(discovered={"feature": item(101, "feature")})
            self.assertEqual(MODULE.import_rows(client, "project", [row("feature")], path, dry_run=False), 0)
            self.assertEqual(MODULE.read_state(path, client.org_service_url, "project"), {"feature": 101})
            self.assertEqual(client.creates, [])

    def test_create_records_state_and_resolves_child_parent(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            client = Client()
            rows = MODULE.topological_rows([row("child", parent_external_id="parent"), row("parent")])
            self.assertEqual(MODULE.import_rows(client, "project", rows, path, dry_run=False), 2)
            self.assertEqual(client.creates, [("parent", None), ("child", 101)])
            self.assertEqual(MODULE.read_state(path, client.org_service_url, "project"), {"child": 102, "parent": 101})

    def test_create_resolves_existing_remote_parent_from_csv_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            client = Client(exact_matches={("Epic", "Existing roadmap"): item(44, "Existing roadmap")})
            child = row(
                "FEATURE-DELIVERY-REPORTING",
                "Delivery reporting",
                parent_work_item_type="Epic",
                parent_title="Existing roadmap",
            )
            self.assertEqual(MODULE.import_rows(client, "project", [child], path, dry_run=False), 1)
            self.assertEqual(client.creates, [("FEATURE-DELIVERY-REPORTING", 44)])
            self.assertEqual(
                MODULE.read_state(path, client.org_service_url, "project"),
                {"FEATURE-DELIVERY-REPORTING": 101},
            )

    def test_dry_run_does_not_write_state(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            self.assertEqual(MODULE.import_rows(Client(), "project", [row("feature")], path, dry_run=True), 1)
            self.assertFalse(path.exists())

    def test_dry_run_plans_children_of_new_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            rows = MODULE.topological_rows([row("child", parent_external_id="parent"), row("parent")])
            self.assertEqual(MODULE.import_rows(Client(), "project", rows, path, dry_run=True), 2)
            self.assertFalse(path.exists())


if __name__ == "__main__":
    unittest.main()
