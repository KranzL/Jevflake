# Jevflake Terraform module

This module creates the same Snowflake objects as `dbt run-operation jevflake.setup`, for teams that manage Snowflake with Terraform. Use one or the other, not both, for the same schema.

After it runs you can call the functions from plain SQL, and the dbt macros in this package work against them without any dbt setup step.

## What it creates

- the schema (optional)
- a network rule that allows outbound traffic to `api.typesafe.ai:443` only
- a secret that holds your TypeSafe API key (optional, see below)
- an external access integration that ties the rule and the secret together
- the Python function `JEV_ASK_JSON`, which calls the Jev API
- ten SQL functions on top of it: `JEV_ASK`, `JEV_NOUL` (with and without criteria), `JEV_CHOICE`, and `JEV_SCORE`, each in a version that takes text and a version that takes a variant
- for each role in `caller_roles`: usage on the schema, and usage on all current and future functions in it

It needs the [snowflakedb/snowflake](https://registry.terraform.io/providers/snowflakedb/snowflake/latest) provider, version 2.21 or newer, and Terraform 1.5 or newer.

## Provider setup

Three of the resources are still preview features in the provider. You have to turn them on in your own provider block. A module cannot do it for you.

```hcl
provider "snowflake" {
  preview_features_enabled = [
    "snowflake_network_rule_resource",
    "snowflake_external_access_integration_resource",
    "snowflake_function_sql_resource",
  ]
}
```

The role Terraform connects with must be able to create integrations. By default that is `ACCOUNTADMIN`. The account must also have external access turned on, which trial accounts do not by default.

## Usage

```hcl
module "jevflake" {
  source = "github.com/KranzL/Jevflake//terraform?ref=v0.2.0"

  database        = "ANALYTICS"
  existing_secret = "ANALYTICS.SECRETS.JEV_API_KEY"
  caller_roles    = ["TRANSFORMER", "REPORTER"]
}
```

There are complete root configurations in [`examples/basic`](examples/basic/main.tf) and [`examples/existing_secret`](examples/existing_secret/main.tf). The second one is the recommended shape: the secret already exists and the key never enters Terraform.

## The API key

You have two choices. Set exactly one.

- `existing_secret`: the full name of a secret you created yourself. The key never enters Terraform. This is the safer choice.

  ```sql
  create secret analytics.secrets.jev_api_key
    type = generic_string
    secret_string = 'your-typesafe-api-key';
  ```

- `api_key`: Terraform creates the secret for you. The variable is marked sensitive, but the key is still written to your Terraform state in plain text. Only use this if your state is encrypted and access to it is locked down.

## Inputs

- `database` (required): the database that holds the schema. It must already exist.
- `schema`: default `JEVFLAKE`.
- `create_schema`: default `true`. Set to `false` if the schema already exists.
- `existing_secret`: full name of an existing secret. Default `null`.
- `api_key`: TypeSafe API key, if Terraform should create the secret. Default `null`.
- `secret_name`: name of the secret Terraform creates. Default `JEV_API_KEY`.
- `network_rule_name`: default `JEV_EGRESS`.
- `integration_name`: default `JEV_ACCESS`. Integrations are account level, so the name must be unique in the account.
- `caller_roles`: roles that may call the functions. Default `[]`. The roles must already exist, and each also needs usage on the database and on a warehouse, which this module does not grant.
- `model`: default `jev-1.13.0`.
- `rows_per_request`: default `1`. Values above 1 are experimental. See the main README.
- `concurrency`: default `8`.
- `max_batch_size`: default `64`.
- `max_retries`: default `6`.
- `timeout_seconds`: default `30`.
- `python_version`: default `3.11`.

All names are turned into upper case. The dbt macros use unquoted names, which Snowflake reads as upper case, so this keeps the two in step.

## Outputs

- `database` and `schema`: where the functions live
- `functions`: full names of the functions you call
- `function_signatures`: full signatures of every overload
- `model`: the model the functions send, for the dbt var of the same name
- `integration_name`, `network_rule`, `secret`

## Using it with the dbt package

Skip `dbt run-operation jevflake.setup`. Point the dbt package at the schema Terraform made, and keep the model name the same on both sides:

```yaml
vars:
  jevflake_database: ANALYTICS
  jevflake_schema: JEVFLAKE
  jevflake_model: jev-1.13.0
```

The dbt var `jevflake_model` is part of the cache key in judgments models, but the model the functions really send is the Terraform `model` input. If the two differ, the cache key no longer tells you which model gave the answers. The `model` column in the judgments table always shows the model the API reported.

## Things to know

- The Python function is created with the provider's `snowflake_execute` resource, not `snowflake_function_python`. On accounts where Snowflake installs packages from its PyPI repository, Snowflake reports the packages under a different property than the provider reads. The provider then sees an empty package list and wants to recreate the function on every plan. `snowflake_execute` avoids that. The trade-off is that Terraform does not detect changes made to that one function outside Terraform.
- Changing `model`, `rows_per_request`, `concurrency`, `max_batch_size`, `max_retries`, `timeout_seconds`, or `python_version` recreates the Python function. The SQL functions and the grants stay. Callers keep access because of the grant on future functions.
- `caller_roles` get usage on all current and future functions in the schema, so keep this schema for Jevflake only.
- The Python source in `handler.py.tftpl` is generated from the dbt macro in `macros/setup/handler.sql`. Do not edit it by hand. After changing the macro, run `python3 scripts/sync_terraform_handler.py`. A unit test fails if the two are out of step.

## Tested

Applied once to a live Snowflake account with provider 2.21.0 and Terraform 1.5.7, using `existing_secret`: a fresh apply of 17 resources, real Jev calls from a role that only had the `caller_roles` grants, the dbt macros pointed at the Terraform schema, a second plan with no changes, a settings change, and a destroy. The `api_key` path, where Terraform creates the secret, passes `terraform validate` but has not been applied live.
