# Security

## Reporting a problem

Please do not open a public issue for a security problem. Report it privately through GitHub:

https://github.com/KranzL/Jevflake/security/advisories/new

You can also get there from the Security tab of the repo, under "Report a vulnerability". Only the maintainer can see the report.

Only the latest release and the `main` branch are supported.

## What counts

Jevflake runs inside your Snowflake account, holds an API key, and sends row content to an outside API. These are the kinds of problems worth a private report:

- the TypeSafe API key ending up somewhere it should not, such as dbt logs, query text, or Terraform state when `existing_secret` is used
- the network rule or integration allowing traffic to anywhere other than `api.typesafe.ai`
- grants that are wider than the README says
- row content making the function do anything other than return an answer

Wrong or low quality answers from Jev are not security problems. Open a normal issue for those.

## Your API key

- Keep the key in a Snowflake secret. Never put it in `dbt_project.yml`, a profile, or a `.tfvars` file that gets committed.
- With the Terraform module, prefer `existing_secret`. The `api_key` input writes the key to Terraform state.
- If a key is exposed, revoke it in the TypeSafe console, create a new key, and put it in the same secret with `alter secret <name> set secret_string = '...'`. The function reads the secret on every call, so it does not need to be recreated. Do not use `create or replace secret`, which makes a new object that the integration and the function no longer point at.
