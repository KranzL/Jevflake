import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TERRAFORM = ROOT / "terraform"

REQUIRED_VERSION = '>= 1.5'
PROVIDER_SOURCE = 'snowflakedb/snowflake'
PROVIDER_VERSION = '>= 2.21, < 3.0'
PREVIEW_FEATURES = [
    "snowflake_network_rule_resource",
    "snowflake_external_access_integration_resource",
    "snowflake_function_sql_resource",
]


def terraform_blocks():
    return [TERRAFORM / "versions.tf"] + sorted(TERRAFORM.glob("examples/*/main.tf"))


def required_version_of(text):
    match = re.search(r'required_version\s*=\s*"([^"]+)"', text)
    return match.group(1) if match else None


def provider_version_of(text):
    match = re.search(
        r'source\s*=\s*"snowflakedb/snowflake"\s*\n\s*version\s*=\s*"([^"]+)"', text
    )
    return match.group(1) if match else None


class TerraformVersionsTest(unittest.TestCase):
    def test_every_root_pins_the_same_terraform_version(self):
        for path in terraform_blocks():
            self.assertEqual(
                required_version_of(path.read_text()),
                REQUIRED_VERSION,
                path.relative_to(ROOT),
            )

    def test_every_root_pins_the_same_provider(self):
        for path in terraform_blocks():
            text = path.read_text()
            self.assertIn(PROVIDER_SOURCE, text, path.relative_to(ROOT))
            self.assertEqual(
                provider_version_of(text),
                PROVIDER_VERSION,
                path.relative_to(ROOT),
            )

    def test_examples_enable_the_preview_features(self):
        for path in sorted(TERRAFORM.glob("examples/*/main.tf")):
            text = path.read_text()
            for feature in PREVIEW_FEATURES:
                self.assertIn(feature, text, "%s is missing %s" % (path.relative_to(ROOT), feature))

    def test_outputs_cover_grant_checks_and_dbt_vars(self):
        text = (TERRAFORM / "outputs.tf").read_text()
        for name in ["function_signatures", "model", "functions", "database", "schema"]:
            self.assertIn('output "%s"' % name, text)


if __name__ == "__main__":
    unittest.main()
