import importlib.util
import sys
import unittest
from pathlib import Path


TOOL_DIRECTORY = Path(__file__).parent
sys.path.insert(0, str(TOOL_DIRECTORY))
SPEC = importlib.util.spec_from_file_location("seed_example_board", TOOL_DIRECTORY / "seed_example_board.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class ExampleBoardTests(unittest.TestCase):
    def test_fixture_has_requested_hierarchy_with_tasks_to_do(self):
        items = MODULE.example_work_items("New", "New", "New", "To Do")

        self.assertEqual(sum(1 for item, _ in items if item.work_item_type == "Epic"), 2)
        self.assertEqual(sum(1 for item, _ in items if item.work_item_type == "Feature"), 3)
        self.assertEqual(sum(1 for item, _ in items if item.work_item_type == "Product Backlog Item"), 4)
        self.assertEqual(sum(1 for item, _ in items if item.work_item_type == "Task"), 5)
        self.assertEqual(sum(1 for _, state in items if state == "To Do"), 5)

    def test_patch_for_new_child_links_to_parent(self):
        child = MODULE.ExampleWorkItem("TASK", "Task", "Example: Child", "Description", "FEATURE")

        patch = MODULE.patch_for(child, "New", 42, None)

        self.assertIn(
            {"op": "add", "path": "/relations/-", "value": {"rel": "System.LinkTypes.Hierarchy-Reverse", "url": "vstfs:///WorkItemTracking/WorkItem/42"}},
            patch,
        )



if __name__ == "__main__":
    unittest.main()
