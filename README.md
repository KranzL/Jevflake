# Jevflake

Jevflake lets Snowflake ask questions about your data using [Jev](https://docs.typesafe.ai), the decision model from TypeSafe AI. It is a dbt package, with a Terraform module for teams that manage Snowflake that way.

Jev does not write text. You give it a row and a typed question. It gives back a typed answer with a probability. That makes it a good fit for SQL: the answer is a number or a label you can filter, join, and test.

This package does three things:

1. Sets up Snowflake so it is allowed to call the Jev API.
2. Creates SQL functions that call Jev: `jev_noul`, `jev_choice`, `jev_score`, and `jev_ask`.
3. Gives you dbt macros and tests so answers are stored once, reused, and checked like any other model.

If you manage Snowflake with Terraform, there is a [Terraform module](terraform/README.md) that does steps 1 and 2 instead of dbt.

This project is not affiliated with TypeSafe AI, Snowflake, or dbt Labs.

## The three question types

- **Noul** is a yes or no question. The answer is a probability from 0 to 1 that the answer is yes.
- **Choice** picks one option from a fixed list. The answer has the pick, a probability for each option, and a confidence number.
- **Score** rates the row against ordered levels. The answer has a score, probabilities, and a confidence number. The score is the probability weighted average of the level numbers, so three levels give a score from 0 to 2.

## Before you start

- A Snowflake account with external access turned on. Trial accounts have it off by default, and your Snowflake account representative has to turn it on.
- A role that can create an integration. By default that is `ACCOUNTADMIN`.
- A TypeSafe API key from https://console.typesafe.ai.
- dbt 1.8 or newer with `dbt-snowflake`. It has been tested on dbt 1.12.

The Python function needs the `pandas` and `requests` packages. Snowflake installs them for you. Depending on the account, they come from Snowflake's PyPI repository or from its Anaconda channel. If creating the function fails with a message about Anaconda terms, an `ORGADMIN` has to accept those terms once in Snowsight.

## Setup

### 1. Store your API key as a Snowflake secret

Run this once in Snowflake. The package never sees the key itself, so it never lands in dbt logs.

```sql
create schema if not exists analytics.jevflake;

create secret analytics.jevflake.jev_api_key
  type = generic_string
  secret_string = 'your-typesafe-api-key';
```

Use your own database in place of `analytics`. By default the package looks in your dbt target database, in a schema called `jevflake`.

### 2. Add the package

```yaml
packages:
  - git: "https://github.com/KranzL/Jevflake.git"
    revision: v0.1
```

Then run `dbt deps`. Pin a tag rather than `main` so updates never change your SQL under you. Changes between versions are listed in [CHANGELOG.md](CHANGELOG.md).

### 3. Create the network access and the functions

```bash
dbt run-operation jevflake.setup --args '{grant_to: [transformer]}'
```

This creates:

- the schema if it does not exist yet
- a network rule that allows traffic to `api.typesafe.ai` only
- an external access integration called `jev_access`
- the SQL functions
- for each role in `grant_to`: usage on the schema and on the functions

A role in `grant_to` can call the functions with only those grants, plus usage on the database and a warehouse. It does not need access to the integration or the secret. If a role lacks usage on the database, an admin can grant it:

```sql
grant usage on database analytics to role reporter;
```

You can run setup again at any time, and you should after you change any setting below. Setup recreates the functions, and Snowflake drops the old grants when it does, so setup reads back the roles that already had access and grants them again along with `grant_to`. Pass `preserve_grants: false` to grant exactly `grant_to` and nothing else. To verify who can use the functions afterwards:

```bash
dbt run-operation jevflake.check_grants --args '{grant_to: [transformer, reporter]}'
```

This fails if any listed role is missing access, and logs any other roles that have it.

To see the SQL without running it:

```bash
dbt run-operation jevflake.setup --args '{dry_run: true}'
```

Database, schema, role, and column names are used unquoted. They must be plain identifiers made of letters, digits, and underscores, starting with a letter or underscore, and the package fails at compile time otherwise. The string and mapping forms of `state` are raw SQL expressions by design and are not checked.

#### If your dbt role cannot create integrations

Split the work. An admin runs the first command. The dbt role runs the second.

```bash
dbt run-operation jevflake.setup_network --args '{grant_to: [transformer], callers: [reporter]}'
dbt run-operation jevflake.setup_functions --args '{grant_to: [reporter]}'
```

- In `setup_network`, `grant_to` lists the roles that will create the functions. They get usage on the integration, read on the secret, and usage and create function on the schema. `callers` lists the roles that will call the functions. They get usage on the schema, which only the schema owner can grant.
- In `setup_functions`, `grant_to` lists the roles that will call the functions. They get usage on each function.

If the secret lives in a different schema than the functions, the role that creates the functions also needs usage on that schema.

#### Removing it

To remove the functions, the integration, and the network rule:

```bash
dbt run-operation jevflake.teardown
```

The secret and the schema are left in place.

## Use it in plain SQL

```sql
select
    ticket_id,
    analytics.jevflake.jev_noul(body, 'The customer is asking for a refund') as wants_refund
from support_tickets;
```

```sql
select
    ticket_id,
    analytics.jevflake.jev_choice(
        body,
        'Which team should handle this ticket',
        parse_json('{"billing": "Charges and refunds", "technical": "Bugs and errors"}')
    ) as answer
from support_tickets;
```

The arguments are what Jev reads, the instructions, and the criteria:

- `jev_noul(state, instructions)` returns a float. An optional third argument describes what counts as yes and no: `parse_json('{"true": "...", "false": "..."}')`.
- `jev_choice(state, instructions, criteria)` returns a variant. The criteria is an object that maps each option to a short description.
- `jev_score(state, instructions, criteria)` returns a variant. The criteria is an array of level descriptions, lowest first.

`jev_choice` and `jev_score` return the whole answer. Read parts of it with `answer:choice`, `answer:score`, `answer:confidence`, `answer:probabilities`, and for a score `answer:legend`.

What Jev reads must be text, an object, or an array. Pass a text column as it is. To send more than one column, pass `object_construct('subject', subject, 'body', body)`. Jev rejects a bare number, date, or boolean, and the answer comes back null. Cast those to text first, for example `amount::varchar`, or put them inside an object.

`jev_ask` takes many named questions at once and makes one API call per row. Use it when you have more than one question about the same row. It is cheaper and faster than separate calls, because the row is only sent once.

```sql
select
    ticket_id,
    analytics.jevflake.jev_ask(
        object_construct('subject', subject, 'body', body),
        parse_json('{
          "ticket_type": {
            "type": "choice",
            "instructions": "Which team should handle this ticket",
            "criteria": {"billing": "Charges and refunds", "technical": "Bugs and errors"}
          },
          "blocked": {
            "type": "noul",
            "instructions": "The customer is blocked from running their business"
          }
        }')
    ):answers as answers
from support_tickets;
```

The result has one entry per question name, for example `answers:ticket_type:choice` and `answers:blocked:noul`.

You will also see a function called `jev_ask_json` in the schema. It is the Python function the others are built on. You do not need to call it.

## Use it in dbt models

### Store answers in a judgments model

This is the recommended way. Answers are stored in a table, one row per key and question. A row is only sent to Jev again if its content changes, one of its questions changes, or you change `jevflake_model`. New or changed rows are asked every question at once; rows that are otherwise up to date are only re-asked the questions that changed.

```sql
{{ config(
    materialized='incremental',
    unique_key=['ticket_id', 'question']
) }}

{{ jevflake.judgments(
    relation=ref('stg_support_tickets'),
    key='ticket_id',
    state=['subject', 'body'],
    questions={
        'ticket_type': jevflake.choice_question(
            'Which team should handle this ticket',
            {
                'billing': 'Charges, refunds, invoices, plans',
                'technical': 'Bugs, crashes, errors, slow pages',
                'account': 'Login, access, profile changes'
            }
        ),
        'urgency': jevflake.score_question(
            'How urgent is this ticket',
            ['No time pressure', 'Normal queue', 'Customer is blocked right now']
        ),
        'has_contact_info': jevflake.noul_question(
            'The text contains a phone number or an email address'
        )
    }
) }}
```

Arguments:

- `relation` is the model or source to read.
- `key` is the column, or list of columns, that identifies a row.
- `state` is what Jev gets to read. It can be one SQL expression, a list of columns, or a mapping of labels to SQL expressions. Send only the columns the questions need. TypeSafe's docs say unrelated content lowers accuracy, and in testing the same question gave noticeably different probabilities with and without an extra column.
- `questions` is a mapping of names to questions. All of them go out in one API call per row.

Columns in the result: your key columns, `question`, `answer_type`, `noul`, `choice`, `score`, `confidence`, `probabilities`, `error`, `answer`, `model`, `state_hash`, `question_hash`, `questions_hash`, `judged_at`. `question_hash` covers one question plus the model name and is what decides whether that question is asked again. `questions_hash` covers the whole question set and is kept for backwards compatibility.

Things to know about what gets stored:

- If you change one question, every row is asked that question again on the next run, and only that question. Unchanged questions keep their stored answers.
- If you remove or rename a question, its old rows stay until you prune them (see below) or run the model with `--full-refresh`. The same goes for rows that are deleted from the source.
- Tables built before `question_hash` existed are picked up without a re-ask: rows whose stored `questions_hash` still matches are treated as up to date.
- Rows with a null key are skipped, and so are rows where the whole state is null: a null expression, or a list or mapping where every column or expression is null. Skipped rows are never sent to Jev and leave no row in the result.
- The `model` column holds the versioned model ID the API reports, falling back to your configured `jevflake_model`.

### Put an answer straight into a column

```sql
select
    ticket_id,
    {{ jevflake.noul('body', 'The customer is asking for a refund') }} as wants_refund,
    {{ jevflake.choice('body', 'What is the tone', ['calm', 'frustrated', 'happy']) }} as tone,
    {{ jevflake.score('body', 'How urgent is this', ['low', 'medium', 'high']) }} as urgency
from {{ ref('stg_support_tickets') }}
```

The first argument is a SQL expression written as a string, a list of columns, or a mapping, the same as `state` above. `noul` gives the probability as a float, `choice` gives the chosen label as text, and `score` gives the score as a float. For `choice` you can pass a list of options, or a mapping of options to descriptions.

Each macro is one API call per row, every time the model runs. Make the model incremental, or use a judgments model, so you do not pay for the same rows twice.

### Review queue

Some answers should go to a person. This macro selects errors, yes or no answers in the uncertain middle, and choices or scores with low confidence.

```sql
{{ jevflake.review_queue(ref('ticket_judgments'), noul_low=0.2, noul_high=0.8, min_confidence=0.5) }}
```

### Prune removed questions and deleted rows

When you remove or rename a question, or rows disappear from the source, the old judgment rows stay until you delete them. This removes both in one step:

```bash
dbt run-operation jevflake.prune_orphans --args '{judgments: ANALYTICS.PUBLIC.ticket_judgments, relation: ANALYTICS.PUBLIC.stg_support_tickets, key: ticket_id, questions: [ticket_type, urgency, has_contact_info]}'
```

`judgments` is the judgments table, `relation` is the source it was built from, `key` is the key column or columns, and `questions` is the current question names, or the full questions mapping. Pass `dry_run: true` to print the deletes without running them. Nothing is sent to Jev, so pruning costs nothing but warehouse time.

### Tests

These run on a judgments model. They read stored answers, so running tests costs nothing.

```yaml
models:
  - name: ticket_judgments
    data_tests:
      - jevflake.no_errors
      - jevflake.noul_between:
          arguments:
            question: has_contact_info
            max_value: 0.2
      - jevflake.confidence_at_least:
          arguments:
            question: ticket_type
            threshold: 0.5
          config:
            severity: warn
```

- `no_errors` fails on rows Jev rejected, for example text that is too long.
- `noul_between` fails when a yes or no probability is outside `min_value` and `max_value`. They default to 0 and 1.
- `score_between` fails when a score is outside `min_value` and `max_value`. `min_value` defaults to 0; `max_value` is required and is the number of levels minus one.
- `choice_allowed` fails when a choice is not in `allowed`. Leave out `question` to check every choice in the model.
- `confidence_at_least` fails when a choice or score has confidence below `threshold`. Leave out `question` to check every choice and score in the model.
- `judgment_drift` fails when answers moved since a baseline run: give it the baseline table name, the key columns, the question, and a `tolerance` for noul and score probabilities (default 0.05). Choice answers fail on any change, and any answer type change fails. Snapshot the judgments table before a question or model change, then point `baseline` at the snapshot.

The `arguments` key needs dbt 1.10.5 or newer. On older versions, put the test arguments directly under the test name.

## Settings

Set these as `vars` in your `dbt_project.yml`. Run `jevflake.setup` again after changing any of them.

- `jevflake_database`: where the functions live. Default: your target database.
- `jevflake_schema`: default `jevflake`.
- `jevflake_secret`: full name of the secret. Default `<database>.<schema>.jev_api_key`.
- `jevflake_integration`: default `jev_access`. Integrations are account level, so the name must be unique in the account.
- `jevflake_network_rule`: default `jev_egress`.
- `jevflake_model`: default `jev-1.13.0`. It is pinned so answers do not shift under you. The model name is part of every cache key, so changing it asks every row every question again on the next run. Snapshot the judgments table first if you want to compare: `judgment_drift` will tell you what moved.
- `jevflake_concurrency`: API calls in flight per batch. Default `8`. Snowflake can run several batches at once, so the total can be higher.
- `jevflake_max_batch_size`: the most rows Snowflake hands the function at once. Default `64`.
- `jevflake_max_retries`: default `6`.
- `jevflake_timeout_seconds`: default `30`.
- `jevflake_rows_per_request`: default `1`. See below.
- `jevflake_python_version`: default `3.11`.

### Rows per request

By default each row is its own API call. At the time of writing TypeSafe allows 1,200 calls per minute, so that is the speed limit: about 72,000 rows per hour. TypeSafe says its limits can change, so check [their models page](https://docs.typesafe.ai/models).

Setting `jevflake_rows_per_request` higher packs several rows into one call. It is faster. It is also experimental: rows in the same call can influence each other, and Jev's own docs say unrelated content lowers accuracy. In a direct API test with three rows, the packed answers were within 0.01 of the single row answers and used about half the tokens. That is a tiny sample, and the packed path has not been run inside Snowflake. Compare answers on a sample of your own data before you trust it.

To compare, build the same judgments model twice on a sample, once with each setting, then run:

```sql
{{ jevflake.packing_drift(ref('ticket_judgments_single'), ref('ticket_judgments_packed'), 'ticket_id') }}
```

This reports per question the mean and max absolute drift for noul and score answers, plus choice and answer type mismatches. Small drift on your own sample is the signal that packing is safe for that question set.

## Costs and limits

- Jev costs $0.042 per million input tokens. Output is free. Every call carries fixed overhead: in testing, one sentence of text with one short question used about 290 input tokens. A short support ticket with three questions came to about 470 input tokens, which works out to roughly $20 per million rows.
- The Snowflake warehouse keeps running while it waits on the API. A small warehouse is enough. A bigger one does not help, because the API rate limit is the cap.
- Jev reads up to 32k tokens of state plus the longest question per call, within 64k tokens for state plus all questions combined.
- Snowflake gives the function 180 seconds per batch of rows. If heavy rate limiting pushes a batch past that, the query fails. Lower `jevflake_max_batch_size` if you see it.
- Busy or rate limited calls are retried with backoff. If retries run out, the query fails. A bad API key fails the query right away.
- Rows that Jev rejects do not fail the query. In a judgments model they come back with `answer_type = 'error'` and the reason in `error`. In plain SQL, `jev_noul` returns null for them, and `jev_choice`, `jev_score`, and `jev_ask` return an answer with `type` set to `error`.

### Estimate before you judge

This reads your source table and estimates tokens and dollars for one full pass, using your real state sizes. It sends nothing to Jev.

```sql
{{ jevflake.estimate_cost(ref('stg_support_tickets'), ['subject', 'body'], {'ticket_type': jevflake.choice_question('Which team', ['billing', 'technical'])}, key='ticket_id') }}
```

The estimate assumes four characters per token plus a fixed overhead per call. Both are parameters, along with the price, so recalibrate them against your first bill.

### Tune the throughput

Two settings control speed: `jevflake_concurrency` is API calls in flight per batch, and `jevflake_max_batch_size` is rows per batch. With the defaults of 8 and 64, one batch makes up to 64 calls, 8 at a time. Snowflake runs several batches in parallel, so the real call rate is higher than one batch suggests.

- The binding constraint is usually TypeSafe's rate limit, currently 1,200 calls per minute, or about 72,000 rows per hour at one row per call. Raising concurrency past what the limit allows only buys retries.
- If batches time out after 180 seconds under rate limiting, lower `jevflake_max_batch_size` so each batch has less work to finish, and consider lowering `jevflake_concurrency` to smooth the call rate.
- If you are well under the rate limit and the warehouse is idle between calls, raise `jevflake_concurrency` first. Run `jevflake.setup` again after changing either setting.

### Check a run afterwards

This summarizes a judgments table by question and answer type, with mean confidence and the judged range:

```sql
{{ jevflake.judgment_run_stats(ref('ticket_judgments')) }}
```

Errors show up as `answer_type = 'error'` rows. For the uncertain middle and low confidence picks, see `review_queue` above.

## What Jev is bad at

From TypeSafe's own notes on Jev 1.13:

- Counting, comparing numbers, and ordering dates. Do those in SQL.
- Questions with double negatives or several steps of reasoning.
- It answers the question you wrote, not the one you meant. Be literal and specific.
- Asking a question and its opposite will not give answers that add up. Pick one phrasing.
- Text inside a row can steer the answer. Do not let an answer trigger anything destructive without a check.

Two more things seen in testing. The same question can give slightly different probabilities depending on which other questions are in the same call, by a point or two. Running the identical call twice gave identical answers, but TypeSafe's docs do not promise that.

## Your data

Row content is sent to TypeSafe's API. It leaves Snowflake. Read TypeSafe's terms and privacy policy, and check with your security team before pointing this at sensitive data.

## Set it up with Terraform instead

The [`terraform`](terraform/README.md) folder has a module that creates the network rule, the integration, the functions, and the grants, and optionally the schema and the secret. If you use it, skip step 3 above and point the dbt vars `jevflake_database` and `jevflake_schema` at the schema Terraform made. The dbt macros and tests work the same either way.

## Run the example project

`integration_tests/` is a small dbt project with ten sample support tickets. It needs the setup above, and these environment variables for a Snowflake user with key pair authentication: `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PRIVATE_KEY_PATH`, `SNOWFLAKE_ROLE`, `SNOWFLAKE_WAREHOUSE`, `SNOWFLAKE_DATABASE`, and optionally `SNOWFLAKE_SCHEMA`.

```bash
cd integration_tests
dbt deps --profiles-dir .
dbt build --profiles-dir .
```

This sends the ten tickets to Jev, which costs a fraction of a cent. Two of the tests are set to warn, and you should expect them to: one sample ticket really does contain contact details, and one is a close call between two teams.

## Development

The offline checks need no Snowflake account:

```bash
python3 -m venv .venv
.venv/bin/pip install jinja2
.venv/bin/python -m unittest discover -s tests
```

They cover the Python handler, render every macro and generic test against snapshots in `tests/snapshots`, and check that the Terraform copy of the handler matches the dbt macro. Without `jinja2` the render tests skip and the rest still runs with no packages. After changing a macro, regenerate snapshots with `UPDATE_SNAPSHOTS=1` and review the diff before committing. After changing `macros/setup/handler.sql`, run `python3 scripts/sync_terraform_handler.py`.

CI runs the same checks on Python 3.10 through 3.12, plus `dbt parse` of the example project on dbt 1.10 and 1.12, an offline `dbt compile` through real dbt 1.10 using a duckdb profile, and Terraform validate on every example. The Snowflake adapter always opens a connection during compile, so compile runs against duckdb: it verifies the Jinja rendering, not the SQL dialect.

## Status

Version 0.1. It has been run against one live Snowflake account with a real Jev key, on dbt 1.12.5 with dbt-snowflake 1.12.1.

What was run: setup, the split setup with a separate admin role, function builder role, and caller role, teardown, every SQL function, the example project with its tests, a second run that sent no rows back to Jev, a run after editing one ticket that sent only that ticket, and the Terraform module.

What has not been run: large tables, so rate limit behaviour at volume is untested. Packing several rows into one call has not been run inside Snowflake. dbt versions older than 1.12 have not been tried.

## License

MIT
