# Changelog

## 0.1.0

First release. Jevflake lets Snowflake ask questions about your data using
Jev, the decision model from TypeSafe AI. It is a dbt package, with a
Terraform module for teams that manage Snowflake that way.

Snowflake UDFs calling the Jev API (`jev_noul`, `jev_choice`, `jev_score`,
`jev_ask`), dbt macros for judgments models, column answers, and a review
queue, and an example project with ten sample tickets.

Caching: judgments models track one hash per question. Changing one
question only re-asks that question; new or changed rows are asked
everything at once. The result carries a `question_hash` column per row plus
the whole-set `questions_hash`. Judgment tables built from pre-release main
are picked up without a re-ask when their stored `questions_hash` matches.

Extra macros:

- `prune_orphans` deletes judgment rows for removed or renamed questions and
  for keys that disappeared from the source, replacing `--full-refresh` for
  cleanup.
- `packing_drift` compares two judgments tables per question, for validating
  `jevflake_rows_per_request` values above 1 on your own data.
- `estimate_cost` estimates tokens and dollars for a full pass over a source
  table without calling Jev.
- `judgment_run_stats` summarizes a judgments table by question and answer
  type.
- `check_grants` fails when an expected role cannot use the functions.

Generic tests: `no_errors`, `noul_between`, `score_between`,
`choice_allowed`, `confidence_at_least`, and `judgment_drift`, which
compares current answers against a baseline snapshot table.

Hardening and behavior:

- Database, schema, secret, network rule, integration, role, key column, and
  state column names are validated at compile time and must be plain
  identifiers. The string and mapping forms of `state` stay raw SQL.
- `setup` and `setup_functions` re-apply grants to roles that already had
  access instead of dropping them. Pass `preserve_grants: false` for exactly
  `grant_to`.
- Rows where the whole state is null are always skipped and never sent
  to Jev.
- Numeric test and review queue thresholds are validated at compile time.
- `judgments` logs the question list to the dbt log on every run.

Model notes:

- The default model is `jev-1.13.0`. The model name is part of every cache
  key, so changing `jevflake_model` re-asks every row every question again
  on the next run. The `model` column always shows the versioned model the
  API reported for that answer.
- With the Terraform module, the model the functions really send is the
  Terraform `model` input; keep the dbt var `jevflake_model` set to the same
  value or the cache keys stop describing the answers.

Verification:

- Offline macro tests render every macro and generic test with stubbed dbt
  globals and compare against snapshots in `tests/snapshots`. They need
  `jinja2`, which CI installs; without it they skip and the remaining checks
  still run with no packages.
- CI runs the unit tests on Python 3.10 through 3.12, `dbt parse` on
  dbt 1.10 and 1.12, an offline `dbt compile` through dbt 1.10 with a
  duckdb profile, and Terraform validate on every example.
