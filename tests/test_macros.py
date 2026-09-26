import importlib.util
import json
import os
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SNAPSHOTS = Path(__file__).resolve().parent / "snapshots"


def load_stubs():
    spec = importlib.util.spec_from_file_location("dbt_stubs", ROOT / "tests" / "dbt_stubs.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


try:
    dbt_stubs = load_stubs()
    HAS_JINJA = True
except ImportError:
    HAS_JINJA = False


def sample_questions(ctx):
    return {
        "ticket_type": ctx.call(
            "choice_question",
            "Which team should handle this ticket",
            {"billing": "Charges and refunds", "technical": "Bugs and errors"},
        ),
        "has_contact_info": ctx.call(
            "noul_question", "The text contains a phone number or an email address"
        ),
    }


@unittest.skipUnless(HAS_JINJA, "jinja2 is not installed")
class MacroSnapshotTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.stubs = dbt_stubs

    def make_context(self):
        return self.stubs.MacroContext()

    def assert_snapshot(self, name, actual):
        path = SNAPSHOTS / (name + ".sql")
        if os.environ.get("UPDATE_SNAPSHOTS") == "1":
            SNAPSHOTS.mkdir(exist_ok=True)
            path.write_text(actual.strip() + "\n")
            return
        self.assertTrue(
            path.exists(),
            "missing snapshot %s. Run: UPDATE_SNAPSHOTS=1 python3 -m unittest tests.test_macros" % path.name,
        )
        self.assertEqual(actual.strip() + "\n", path.read_text())

    def test_sql_string_escapes_quotes(self):
        ctx = self.make_context()
        self.assertEqual(ctx.call("sql_string", "o'clock"), "'o''clock'")

    def test_sql_string_escapes_backslashes(self):
        ctx = self.make_context()
        self.assertEqual(ctx.call("sql_string", "a\\b"), "'a\\\\b'")

    def test_json_literal(self):
        ctx = self.make_context()
        self.assert_snapshot("json_literal", ctx.call("json_literal", {"b": 1, "a": 2}))

    def test_state_expression_forms(self):
        ctx = self.make_context()
        self.assert_snapshot("state_expression_string", ctx.call("state_expression", "body"))
        self.assert_snapshot(
            "state_expression_list", ctx.call("state_expression", ["subject", "body"])
        )
        self.assert_snapshot(
            "state_expression_mapping",
            ctx.call("state_expression", {"text": "body", "amount": "amount::varchar"}),
        )

    def test_state_not_null_predicate(self):
        ctx = self.make_context()
        self.assert_snapshot(
            "state_predicate_string", ctx.call("state_not_null_predicate", "body")
        )
        self.assert_snapshot(
            "state_predicate_list", ctx.call("state_not_null_predicate", ["subject", "body"])
        )
        self.assert_snapshot(
            "state_predicate_mapping",
            ctx.call("state_not_null_predicate", {"text": "body", "n": "amount"}),
        )

    def test_judgments_skips_null_keys_and_null_state(self):
        ctx = self.make_context()
        rendered = ctx.call(
            "judgments", "rel", ["a", "b"], ["subject", "body"], sample_questions(ctx)
        )
        self.assertIn("a is not null and b is not null and", rendered)
        self.assertIn("((subject is not null) or (body is not null))", rendered)

    def test_state_expression_rejects_empty(self):
        ctx = self.make_context()
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("state_expression", [])

    def test_question_builders(self):
        ctx = self.make_context()
        built = {
            "noul": ctx.call("noul_question", "Is it urgent"),
            "choice": ctx.call("choice_question", "Which team", ["a", "b"]),
            "score": ctx.call("score_question", "How urgent", ["low", "high"]),
        }
        self.assert_snapshot("question_builders", json.dumps(built, sort_keys=True, indent=2))

    def test_choice_question_needs_two_options(self):
        ctx = self.make_context()
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("choice_question", "Which", ["only"])

    def test_score_question_needs_ordered_levels(self):
        ctx = self.make_context()
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("score_question", "How", ["only"])
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("score_question", "How", {"low": "x", "high": "y"})

    def test_column_expressions(self):
        ctx = self.make_context()
        self.assert_snapshot("expr_noul", ctx.call("noul", "body", "Is it urgent"))
        self.assert_snapshot(
            "expr_choice", ctx.call("choice", ["subject", "body"], "Which team", ["a", "b"])
        )
        self.assert_snapshot(
            "expr_score", ctx.call("score", "body", "How urgent", ["low", "high"])
        )

    def test_judgments_full_refresh(self):
        ctx = self.make_context()
        rendered = ctx.call(
            "judgments", "ref_stg_tickets", "ticket_id", ["subject", "body"], sample_questions(ctx)
        )
        self.assert_snapshot("judgments_full_refresh", rendered)
        self.assertNotIn("not exists", rendered)
        self.assertIn("questions_hash", rendered)

    def test_judgments_incremental(self):
        ctx = self.make_context()
        ctx.incremental = True
        rendered = ctx.call(
            "judgments", "ref_stg_tickets", "ticket_id", ["subject", "body"], sample_questions(ctx)
        )
        self.assert_snapshot("judgments_incremental", rendered)
        self.assertIn("not exists", rendered)
        self.assertIn(str(ctx.this), rendered)

    def test_judgments_needs_key_and_question(self):
        ctx = self.make_context()
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("judgments", "rel", [], ["body"], sample_questions(ctx))
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("judgments", "rel", "ticket_id", ["body"], {})

    def test_questions_hash_is_stable(self):
        first = self.make_context().call("questions_hash", sample_questions(self.make_context()))
        second = self.make_context().call("questions_hash", sample_questions(self.make_context()))
        self.assertEqual(first, second)

    def test_question_hashes_change_one_at_a_time(self):
        ctx = self.make_context()
        before = ctx.call("question_hashes", sample_questions(ctx))
        changed = sample_questions(ctx)
        changed["ticket_type"] = ctx.call(
            "choice_question",
            "Which team should handle this ticket",
            {"billing": "Charges", "other": "Everything else"},
        )
        after = ctx.call("question_hashes", changed)
        self.assertNotEqual(before["ticket_type"], after["ticket_type"])
        self.assertEqual(before["has_contact_info"], after["has_contact_info"])

    def test_question_hashes_change_with_model(self):
        ctx = self.make_context()
        plain = ctx.call("question_hashes", sample_questions(ctx))
        ctx.vars["jevflake_model"] = "jev-9.9.9"
        changed = ctx.call("question_hashes", sample_questions(ctx))
        self.assertNotEqual(plain, changed)

    def test_judgments_incremental_has_fresh_and_stale_branches(self):
        ctx = self.make_context()
        ctx.incremental = True
        rendered = ctx.call(
            "judgments", "rel", "ticket_id", ["subject"], sample_questions(ctx)
        )
        self.assertIn("jevflake_fresh", rendered)
        self.assertIn("jevflake_stale_0", rendered)
        self.assertIn("jevflake_stale_1", rendered)
        self.assertNotIn("jevflake_stale_2", rendered)
        self.assertEqual(rendered.count("union all"), 2)
        self.assertIn("end as question_hash", rendered)
        self.assertIn("judged.question_hash is null and judged.questions_hash =", rendered)

    def test_judgments_full_refresh_has_no_stale_branches(self):
        ctx = self.make_context()
        rendered = ctx.call(
            "judgments", "rel", "ticket_id", ["subject"], sample_questions(ctx)
        )
        self.assertNotIn("jevflake_stale_0", rendered)
        self.assertNotIn("union all", rendered)
        self.assertIn("end as question_hash", rendered)

    def test_questions_hash_changes_with_model(self):
        ctx = self.make_context()
        plain = ctx.call("questions_hash", sample_questions(ctx))
        ctx.vars["jevflake_model"] = "jev-9.9.9"
        changed = ctx.call("questions_hash", sample_questions(ctx))
        self.assertNotEqual(plain, changed)

    def test_review_queue(self):
        ctx = self.make_context()
        self.assert_snapshot("review_queue", ctx.call("review_queue", "ref_ticket_judgments"))

    def test_generic_tests(self):
        ctx = self.make_context()
        self.assert_snapshot(
            "test_noul_between",
            ctx.call("noul_between", "ref_judgments", "has_contact_info", min_value=0, max_value=0.2),
        )
        self.assert_snapshot(
            "test_confidence_scoped",
            ctx.call("confidence_at_least", "ref_judgments", threshold=0.5, question="ticket_type"),
        )
        self.assert_snapshot(
            "test_confidence_unscoped",
            ctx.call("confidence_at_least", "ref_judgments", threshold=0.5),
        )
        self.assert_snapshot("test_no_errors", ctx.call("no_errors", "ref_judgments"))
        self.assert_snapshot(
            "test_score_between",
            ctx.call("score_between", "ref_judgments", "urgency", min_value=0, max_value=2),
        )
        self.assert_snapshot(
            "test_choice_allowed_scoped",
            ctx.call(
                "choice_allowed",
                "ref_judgments",
                ["billing", "technical"],
                question="ticket_type",
            ),
        )
        self.assert_snapshot(
            "test_choice_allowed_unscoped",
            ctx.call("choice_allowed", "ref_judgments", ["billing", "technical"]),
        )
        self.assert_snapshot(
            "test_judgment_drift",
            ctx.call(
                "judgment_drift",
                "ref_judgments",
                "ANALYTICS.PUBLIC.baseline",
                "ticket_id",
                "urgency",
                tolerance=0.05,
            ),
        )

    def test_extended_tests_reject_bad_input(self):
        ctx = self.make_context()
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("score_between", "rel", "q")
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("score_between", "rel", "q", max_value="high")
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("choice_allowed", "rel", [])
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("judgment_drift", "rel", "base line", "k", "q")
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("judgment_drift", "rel", "baseline", "k;k", "q", tolerance=0.1)
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("judgment_drift", "rel", "baseline", [], "q")

    def test_network_statements(self):
        ctx = self.make_context()
        statements = ctx.call("network_statements", ["builder"], ["caller"])
        self.assert_snapshot("network_statements", ";\n".join(statements))
        joined = " ".join(statements)
        self.assertIn("api.typesafe.ai:443", joined)
        self.assertIn("grant usage on schema", joined)

    def test_teardown_statements(self):
        ctx = self.make_context()
        ctx.call("teardown", dry_run=True)
        self.assert_snapshot("teardown_statements", "\n".join(ctx.printed))
        self.assertEqual(len(ctx.printed), 13)

    def test_function_signatures(self):
        ctx = self.make_context()
        signatures = ctx.call("function_signatures")
        self.assertEqual(len(signatures), 11)
        self.assert_snapshot("function_signatures", "\n".join(signatures))

    def test_assert_identifier_accepts_plain_names(self):
        ctx = self.make_context()
        for name in ["reporter", "TRANSFORMER", "_private", "role_2"]:
            self.assertEqual(ctx.call("assert_identifier", name, "role"), name)

    def test_assert_identifier_rejects_bad_names(self):
        ctx = self.make_context()
        for name in ["", "has space", "has-hyphen", "9lives", "a'b", "a;b", "a.b", 42, None]:
            with self.assertRaises(self.stubs.CompilerError, msg=repr(name)):
                ctx.call("assert_identifier", name, "role")

    def test_assert_dotted_name(self):
        ctx = self.make_context()
        self.assertEqual(ctx.call("assert_dotted_name", "A.B.C", "secret"), "A.B.C")
        for name in ["", "A.B-C", "A..B", ".A", 42]:
            with self.assertRaises(self.stubs.CompilerError, msg=repr(name)):
                ctx.call("assert_dotted_name", name, "secret")

    def test_assert_number(self):
        ctx = self.make_context()
        self.assertEqual(ctx.call("assert_number", 0.5, "threshold"), 0.5)
        self.assertEqual(ctx.call("assert_number", 1, "threshold"), 1)
        for value in ["0.5", "1; drop table x", None]:
            with self.assertRaises(self.stubs.CompilerError, msg=repr(value)):
                ctx.call("assert_number", value, "threshold")

    def test_judgments_rejects_bad_key(self):
        ctx = self.make_context()
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("judgments", "rel", "ticket_id; delete", ["body"], sample_questions(ctx))

    def test_state_list_rejects_bad_column_but_string_stays_raw(self):
        ctx = self.make_context()
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("state_expression", ["body; delete"])
        self.assertEqual(
            ctx.call("state_expression", "amount::varchar"), "to_variant(amount::varchar)"
        )

    def test_setup_rejects_bad_role(self):
        ctx = self.make_context()
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("network_statements", ["reporter; admin"], [])
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("function_statements", ["x y"])

    def test_config_rejects_bad_names(self):
        ctx = self.make_context()
        ctx.vars["jevflake_schema"] = "bad-schema"
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("function_name", "jev_ask")
        ctx.vars["jevflake_schema"] = "jevflake"
        ctx.vars["jevflake_secret"] = "A.B-C"
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("secret_name")

    def test_review_queue_rejects_non_numbers(self):
        ctx = self.make_context()
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("review_queue", "rel", noul_low="low")

    def test_generic_tests_reject_non_numbers(self):
        ctx = self.make_context()
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("noul_between", "rel", "q", max_value="high")
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("confidence_at_least", "rel", threshold="high")

    def test_prune_statements(self):
        ctx = self.make_context()
        statements = ctx.call(
            "prune_statements",
            "ANALYTICS.PUBLIC.ticket_judgments",
            "ANALYTICS.PUBLIC.stg_tickets",
            "ticket_id",
            sample_questions(ctx),
        )
        self.assert_snapshot("prune_statements", ";\n".join(statements))
        self.assertEqual(len(statements), 2)
        self.assertIn("question not in", statements[0])
        self.assertIn("not exists", statements[1])

    def test_prune_accepts_name_list_and_composite_keys(self):
        ctx = self.make_context()
        statements = ctx.call(
            "prune_statements", "judgments", "source", ["a", "b"], ["q1", "o'clock"]
        )
        self.assertIn("question not in ('q1', 'o''clock')", statements[0])
        self.assertIn("source.a = judged.a", statements[1])
        self.assertIn("source.b = judged.b", statements[1])

    def test_prune_rejects_bad_input(self):
        ctx = self.make_context()
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("prune_statements", "judgments", "source", "a;b", ["q"])
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("prune_statements", "judg ments", "source", "a", ["q"])
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("prune_statements", "judgments", "source", "a", [])
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("prune_statements", "judgments", "source", [], ["q"])

    def test_prune_orphans_dry_run_prints(self):
        ctx = self.make_context()
        ctx.call(
            "prune_orphans",
            "judgments",
            "source",
            "ticket_id",
            sample_questions(ctx),
            dry_run=True,
        )
        self.assertEqual(len(ctx.printed), 2)

    def test_prune_orphans_runs_statements(self):
        ctx = self.make_context()
        ctx.call(
            "prune_orphans", "judgments", "source", "ticket_id", sample_questions(ctx)
        )
        self.assertEqual(len(ctx.statements), 2)

    def test_packing_drift(self):
        ctx = self.make_context()
        rendered = ctx.call(
            "packing_drift", "baseline_judgments", "candidate_judgments", "ticket_id"
        )
        self.assert_snapshot("packing_drift", rendered)
        self.assertIn("full outer join", rendered)
        self.assertIn("choice_mismatches", rendered)
        self.assertIn("group by 1", rendered)

    def test_packing_drift_rejects_bad_input(self):
        ctx = self.make_context()
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("packing_drift", "baseline", "candidate", "k;k")
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("packing_drift", "base line", "candidate", "k")
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("packing_drift", "baseline", "candidate", [])

    def test_estimate_cost(self):
        ctx = self.make_context()
        rendered = ctx.call(
            "estimate_cost",
            "stg_tickets",
            ["subject", "body"],
            sample_questions(ctx),
            key="ticket_id",
        )
        self.assert_snapshot("estimate_cost", rendered)
        self.assertIn("est_usd", rendered)
        self.assertIn("ticket_id is not null", rendered)

    def test_estimate_cost_rejects_bad_input(self):
        ctx = self.make_context()
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("estimate_cost", "rel", ["body"], {})
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call(
                "estimate_cost", "rel", ["body"], sample_questions(ctx), price_per_million="x"
            )

    def test_judgment_run_stats(self):
        ctx = self.make_context()
        rendered = ctx.call("judgment_run_stats", "ticket_judgments")
        self.assert_snapshot("judgment_run_stats", rendered)
        self.assertIn("mean_confidence", rendered)
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("judgment_run_stats", "bad name")

    def test_judgments_logs_question_summary(self):
        ctx = self.make_context()
        ctx.call("judgments", "rel", "ticket_id", ["body"], sample_questions(ctx))
        self.assertEqual(len(ctx.logs), 1)
        self.assertIn("2 questions", ctx.logs[0])
        self.assertIn("ticket_type", ctx.logs[0])

    def queue_grants(self, ctx, count, roles):
        stubs = self.stubs
        ctx.query_results = [
            stubs.QueryResult(rows=[[None]]),
            stubs.QueryResult(rows=[[count]]),
            stubs.QueryResult(rows=[[None]]),
            stubs.QueryResult(rows=[[role] for role in roles]),
        ]

    def test_functions_exist_probes_schema(self):
        ctx = self.make_context()
        self.queue_grants(ctx, 1, ["REPORTER"])
        self.assertTrue(ctx.call("functions_exist"))
        self.assertIn("show functions like", ctx.statements[0])
        self.assertIn("result_scan(last_query_id())", ctx.statements[1])

    def test_setup_functions_preserves_previous_roles(self):
        ctx = self.make_context()
        self.queue_grants(ctx, 1, ["REPORTER"])
        ctx.call("setup_functions", grant_to=["transformer"])
        joined = "\n".join(ctx.statements)
        self.assertIn("to role REPORTER", joined)
        self.assertIn("to role transformer", joined)
        self.assertTrue(any("keeping grants" in line for line in ctx.logs))

    def test_setup_functions_dedupes_roles_case_insensitively(self):
        ctx = self.make_context()
        self.queue_grants(ctx, 1, ["TRANSFORMER"])
        ctx.call("setup_functions", grant_to=["transformer"])
        grants = [part for part in ctx.statements if "to role" in part and "function" in part]
        self.assertEqual(len(grants), 11)

    def test_setup_functions_fresh_install_grants_only_passed_roles(self):
        ctx = self.make_context()
        self.queue_grants(ctx, 0, [])
        ctx.call("setup_functions", grant_to=["transformer"])
        joined = "\n".join(ctx.statements)
        self.assertIn("to role transformer", joined)
        self.assertNotIn("keeping grants", "\n".join(ctx.logs))

    def test_setup_functions_dry_run_runs_no_queries(self):
        ctx = self.make_context()
        ctx.call("setup_functions", grant_to=["transformer"], dry_run=True)
        self.assertEqual(ctx.statements, [])
        self.assertEqual(len(ctx.printed), 11 + 11)

    def test_setup_functions_can_skip_preservation(self):
        ctx = self.make_context()
        ctx.call("setup_functions", grant_to=["transformer"], preserve_grants=False)
        introspection = [
            part
            for part in ctx.statements
            if part.startswith("show ") or part.startswith("select ")
        ]
        self.assertEqual(introspection, [])

    def test_setup_applies_network_before_probing_functions(self):
        ctx = self.make_context()
        self.queue_grants(ctx, 0, [])
        ctx.call("setup", grant_to=["transformer"])
        kinds = [
            "network" if "create schema" in part or "integration" in part
            else "probe" if "show functions" in part or "result_scan" in part
            else "function" if "create or replace function" in part
            else "other"
            for part in ctx.statements
        ]
        self.assertLess(kinds.index("network"), kinds.index("probe"))
        self.assertLess(kinds.index("probe"), kinds.index("function"))

    def test_check_grants_passes_and_reports_extra_roles(self):
        ctx = self.make_context()
        self.queue_grants(ctx, 1, ["REPORTER", "ANALYST"])
        ctx.call("check_grants", grant_to=["reporter"])
        self.assertTrue(any("all 1 expected roles" in line for line in ctx.logs))
        self.assertTrue(any("ANALYST" in line for line in ctx.logs))

    def test_check_grants_fails_on_missing_roles(self):
        ctx = self.make_context()
        self.queue_grants(ctx, 1, ["REPORTER"])
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("check_grants", grant_to=["reporter", "analyst"])

    def test_check_grants_fails_when_nothing_installed(self):
        ctx = self.make_context()
        self.queue_grants(ctx, 0, [])
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("check_grants", grant_to=["reporter"])

    def test_check_grants_rejects_bad_roles(self):
        ctx = self.make_context()
        with self.assertRaises(self.stubs.CompilerError):
            ctx.call("check_grants", grant_to=["bad role"])

    def test_check_grants_dry_run_prints(self):
        ctx = self.make_context()
        ctx.call("check_grants", grant_to=["reporter"], dry_run=True)
        self.assertEqual(ctx.statements, [])
        self.assertEqual(len(ctx.printed), 2)

    def test_function_statements_shape(self):
        ctx = self.make_context()
        statements = ctx.call("function_statements", ["reporter"])
        self.assertEqual(len(statements), 11 + 11)
        self.assertIn("language python", statements[0])
        grants = [part for part in statements if part.startswith("grant usage on function")]
        self.assertEqual(len(grants), 11)
        self.assertTrue(all("to role reporter" in part for part in grants))


if __name__ == "__main__":
    unittest.main()
