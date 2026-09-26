# Changelog

## 0.2.0

New caching: judgments models now track one hash per question instead of a
single hash for the whole question set. Changing one question only re-asks
that question; new or changed rows are still asked everything at once. The
result gains a `question_hash` column, and tables built by 0.1.0 are picked
up without a re-ask when their stored `questions_hash` still matches.

New macros:

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

New generic tests: `score_between`, `choice_allowed`, and `judgment_drift`,
which compares current answers against a baseline snapshot table.

Hardening and behavior changes:

- Database, schema, secret, network rule, integration, role, key column, and
  state column names are validated at compile time and must be plain
  identifiers. The string and mapping forms of `state` stay raw SQL.
- `setup` and `setup_functions` re-apply grants to roles that already had
  access instead of dropping them. Pass `preserve_grants: false` for exactly
  `grant_to`.
- Rows where the whole state is null are now always skipped, including the
  list and mapping forms of `state`, which used to send all-null rows to Jev.
- Numeric test and review queue thresholds are validated at compile time.
- `judgments` logs the question list to the dbt log on every run.

Model notes:

- The default model is still `jev-1.13.0`. The model name is part of both the
  per-question and the whole-set cache keys, so changing `jevflake_model`
  re-asks every row on the next run, exactly as before. The `model` column
  always shows the versioned model the API reported for that answer.
- With the Terraform module, the model the functions really send is the
  Terraform `model` input; keep the dbt var `jevflake_model` set to the same
  value or the cache keys stop describing the answers.

Verification:

- Offline macro tests render every macro and generic test with stubbed dbt
  globals and compare against snapshots in `tests/snapshots`. They need
  `jinja2`, which CI installs; without it they skip and the remaining checks
  still run with no packages.
- CI runs the unit tests on Python 3.10 through 3.12, `dbt parse` and
  `dbt compile` on dbt 1.10 and 1.12, and Terraform validate on every
  example.

## 0.1.0

First release. Snowflake UDFs calling the Jev API (`jev_noul`, `jev_choice`,
`jev_score`, `jev_ask`), dbt macros for judgments models, column answers, and
a review queue, generic tests (`no_errors`, `noul_between`,
`confidence_at_least`), dbt and Terraform setup paths, and an example project
with ten sample tickets.
