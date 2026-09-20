import importlib.util
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_sync_script():
    spec = importlib.util.spec_from_file_location("sync_terraform_handler", ROOT / "scripts" / "sync_terraform_handler.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TerraformHandlerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sync = load_sync_script()
        cls.rendered = cls.sync.render(cls.sync.SOURCE.read_text())

    def test_committed_template_matches_the_dbt_macro(self):
        self.assertEqual(
            self.sync.TARGET.read_text(),
            self.rendered,
            "Run: python3 scripts/sync_terraform_handler.py",
        )

    def test_only_known_placeholders_are_used(self):
        placeholders = set(re.findall(r"\$\{([^}]+)\}", self.rendered))
        self.assertEqual(
            placeholders,
            {
                "jsonencode(model)",
                "rows_per_request",
                "concurrency",
                "max_batch_size",
                "max_retries",
                "timeout_seconds",
            },
        )

    def test_rendered_template_is_valid_python_once_filled_in(self):
        filled = self.rendered.replace("${jsonencode(model)}", '"jev-test-model"')
        filled = re.sub(r"\$\{[a-z_]+\}", "1", filled)
        compile(filled, "handler.py", "exec")


if __name__ == "__main__":
    unittest.main()
