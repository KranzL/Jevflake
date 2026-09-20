import re
import sys
import types
import unittest
from pathlib import Path


def load_handler():
    path = Path(__file__).resolve().parent.parent / "macros" / "setup" / "handler.sql"
    lines = [line for line in path.read_text().splitlines() if not line.strip().startswith("{%")]
    text = "\n".join(lines)
    text = text.replace("{{ tojson(jevflake.model_name()) }}", '"jev-test-model"')
    text = re.sub(r"\{\{ var\('[^']+', (\d+)\) \| int \}\}", r"\1", text)
    if "{{" in text or "{%" in text:
        raise ValueError("unrendered Jinja left in handler.sql")
    pandas = types.ModuleType("pandas")
    pandas.DataFrame = object
    pandas.Series = object
    pandas.isna = lambda value: value is None
    sys.modules["pandas"] = pandas
    requests = types.ModuleType("requests")
    requests.RequestException = type("RequestException", (Exception,), {})
    requests.Session = lambda: types.SimpleNamespace(mount=lambda *args: None)
    adapters = types.ModuleType("requests.adapters")
    adapters.HTTPAdapter = lambda *args, **kwargs: None
    requests.adapters = adapters
    sys.modules["requests"] = requests
    sys.modules["requests.adapters"] = adapters
    snowflake = types.ModuleType("_snowflake")
    snowflake.get_generic_secret_string = lambda name: "test-key"
    snowflake.vectorized = lambda **kwargs: (lambda func: func)
    sys.modules["_snowflake"] = snowflake
    namespace = {}
    exec(compile(text, "handler.sql", "exec"), namespace)
    return namespace


class HandlerModelTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.handler = load_handler()

    def test_reported_model_wins_over_configured(self):
        answers = self.handler["finish"]({"q": {"type": "noul", "noul": 0.7}}, "jev-1.13.0")
        self.assertEqual(answers["q"]["model"], "jev-1.13.0")

    def test_missing_reported_model_falls_back_to_configured(self):
        answers = self.handler["finish"]({"q": {"type": "noul", "noul": 0.7}}, None)
        self.assertEqual(answers["q"]["model"], "jev-test-model")

    def test_existing_answer_model_is_preserved(self):
        answers = self.handler["finish"]({"q": {"type": "choice", "model": "pinned"}}, "jev-1.13.0")
        self.assertEqual(answers["q"]["model"], "pinned")

    def test_failed_answers_carry_configured_model(self):
        answers = self.handler["failed"]({"q": {"type": "noul"}}, "boom")
        self.assertEqual(answers["q"]["model"], "jev-test-model")
        self.assertEqual(answers["q"]["type"], "error")

    def test_ask_row_threads_response_model(self):
        body = {"model": "jev-1.13.0", "answers": {"q": {"type": "noul", "noul": 0.2}}}
        self.handler["post"] = lambda payload, key: (body, None)
        answers = self.handler["ask_row"]({"text": "hi"}, {"q": {"type": "noul"}}, "key")
        self.assertEqual(answers["q"]["model"], "jev-1.13.0")
        self.assertEqual(answers["q"]["noul"], 0.2)

    def test_ask_row_without_response_model_falls_back(self):
        body = {"answers": {"q": {"type": "noul", "noul": 0.2}}}
        self.handler["post"] = lambda payload, key: (body, None)
        answers = self.handler["ask_row"]({"text": "hi"}, {"q": {"type": "noul"}}, "key")
        self.assertEqual(answers["q"]["model"], "jev-test-model")

    def test_ask_rows_threads_response_model(self):
        def fake_post(payload, key):
            asked = payload["questions"]
            made = {name: {"type": "noul", "noul": 0.5} for name in asked}
            return ({"model": "jev-1.13.0", "answers": made}, None)
        self.handler["post"] = fake_post
        questions = {"q": {"type": "noul", "instructions": "x"}}
        results = self.handler["ask_rows"]([{"a": 1}, {"b": 2}], questions, "key")
        self.assertEqual([row["q"]["model"] for row in results], ["jev-1.13.0", "jev-1.13.0"])


if __name__ == "__main__":
    unittest.main()
