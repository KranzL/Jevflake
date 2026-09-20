locals {
  database  = upper(var.database)
  schema    = var.create_schema ? snowflake_schema.this[0].name : upper(var.schema)
  schema_id = "\"${local.database}\".\"${local.schema}\""
  namespace = "${local.database}.${local.schema}"

  existing_secret_id = var.existing_secret == null ? null : join(".", [for part in split(".", upper(var.existing_secret)) : "\"${part}\""])
  secret_id          = coalesce(local.existing_secret_id, one(snowflake_secret_with_generic_string.api_key[*].fully_qualified_name), "missing")

  state_forms = {
    variant = { type = "VARIANT", expression = "STATE" }
    varchar = { type = "VARCHAR", expression = "TO_VARIANT(STATE)" }
  }

  ask_functions = {
    for key, form in local.state_forms : key => {
      state_type = form.type
      definition = "PARSE_JSON(${local.namespace}.JEV_ASK_JSON(TO_JSON(${form.expression}), TO_JSON(QUESTIONS)))"
    }
  }

  question_functions = merge([
    for key, form in local.state_forms : {
      "noul_${key}" = {
        name          = "JEV_NOUL"
        return_type   = "FLOAT"
        state_type    = form.type
        with_criteria = false
        definition    = "${local.namespace}.JEV_ASK(${form.expression}, TO_VARIANT(OBJECT_CONSTRUCT('answer', OBJECT_CONSTRUCT('type', 'noul', 'instructions', INSTRUCTIONS)))):answers:answer:noul::FLOAT"
      }
      "noul_criteria_${key}" = {
        name          = "JEV_NOUL"
        return_type   = "FLOAT"
        state_type    = form.type
        with_criteria = true
        definition    = "${local.namespace}.JEV_ASK(${form.expression}, TO_VARIANT(OBJECT_CONSTRUCT('answer', OBJECT_CONSTRUCT('type', 'noul', 'instructions', INSTRUCTIONS, 'criteria', CRITERIA)))):answers:answer:noul::FLOAT"
      }
      "choice_${key}" = {
        name          = "JEV_CHOICE"
        return_type   = "VARIANT"
        state_type    = form.type
        with_criteria = true
        definition    = "${local.namespace}.JEV_ASK(${form.expression}, TO_VARIANT(OBJECT_CONSTRUCT('answer', OBJECT_CONSTRUCT('type', 'choice', 'instructions', INSTRUCTIONS, 'criteria', CRITERIA)))):answers:answer"
      }
      "score_${key}" = {
        name          = "JEV_SCORE"
        return_type   = "VARIANT"
        state_type    = form.type
        with_criteria = true
        definition    = "${local.namespace}.JEV_ASK(${form.expression}, TO_VARIANT(OBJECT_CONSTRUCT('answer', OBJECT_CONSTRUCT('type', 'score', 'instructions', INSTRUCTIONS, 'criteria', CRITERIA)))):answers:answer"
      }
    }
  ]...)
}

resource "snowflake_schema" "this" {
  count    = var.create_schema ? 1 : 0
  database = local.database
  name     = upper(var.schema)
  comment  = "Jevflake: functions that call the TypeSafe Jev API"
}

resource "snowflake_network_rule" "egress" {
  database   = local.database
  schema     = local.schema
  name       = upper(var.network_rule_name)
  type       = "HOST_PORT"
  mode       = "EGRESS"
  value_list = ["api.typesafe.ai:443"]
  comment    = "Jevflake: outbound access to the TypeSafe Jev API"
}

resource "snowflake_secret_with_generic_string" "api_key" {
  count         = nonsensitive(var.api_key != null) ? 1 : 0
  database      = local.database
  schema        = local.schema
  name          = upper(var.secret_name)
  secret_string = var.api_key
  comment       = "Jevflake: TypeSafe API key"
}

resource "snowflake_external_access_integration" "jev" {
  name                  = upper(var.integration_name)
  enabled               = true
  allowed_network_rules = [snowflake_network_rule.egress.fully_qualified_name]
  comment               = "Jevflake: lets the Jev functions reach api.typesafe.ai"

  allowed_authentication_secrets {
    secrets = [local.secret_id]
  }

  lifecycle {
    precondition {
      condition     = (var.existing_secret == null) != nonsensitive(var.api_key == null)
      error_message = "Set exactly one of api_key or existing_secret."
    }
  }
}

resource "snowflake_execute" "ask_json" {
  execute = join("\n", [
    "CREATE OR REPLACE FUNCTION ${local.namespace}.JEV_ASK_JSON(STATE VARCHAR, QUESTIONS VARCHAR)",
    "RETURNS VARCHAR",
    "LANGUAGE PYTHON",
    "RUNTIME_VERSION = '${var.python_version}'",
    "PACKAGES = ('pandas', 'requests')",
    "EXTERNAL_ACCESS_INTEGRATIONS = (${snowflake_external_access_integration.jev.name})",
    "SECRETS = ('api_key' = ${local.secret_id})",
    "HANDLER = 'ask'",
    "COMMENT = 'Jevflake: sends rows and questions to the Jev API'",
    "AS $$",
    templatefile("${path.module}/handler.py.tftpl", {
      model            = var.model
      rows_per_request = var.rows_per_request
      concurrency      = var.concurrency
      max_batch_size   = var.max_batch_size
      max_retries      = var.max_retries
      timeout_seconds  = var.timeout_seconds
    }),
    "$$",
  ])

  revert = "DROP FUNCTION IF EXISTS ${local.namespace}.JEV_ASK_JSON(VARCHAR, VARCHAR)"
}

resource "snowflake_function_sql" "ask" {
  for_each            = local.ask_functions
  database            = local.database
  schema              = local.schema
  name                = "JEV_ASK"
  return_type         = "VARIANT"
  function_definition = each.value.definition
  comment             = "Jevflake: asks Jev one or more named questions about a row"

  arguments {
    arg_name      = "STATE"
    arg_data_type = each.value.state_type
  }

  arguments {
    arg_name      = "QUESTIONS"
    arg_data_type = "VARIANT"
  }

  depends_on = [snowflake_execute.ask_json]
}

resource "snowflake_function_sql" "question" {
  for_each            = local.question_functions
  database            = local.database
  schema              = local.schema
  name                = each.value.name
  return_type         = each.value.return_type
  function_definition = each.value.definition
  comment             = "Jevflake: asks Jev a single question about a row"

  arguments {
    arg_name      = "STATE"
    arg_data_type = each.value.state_type
  }

  arguments {
    arg_name      = "INSTRUCTIONS"
    arg_data_type = "VARCHAR"
  }

  dynamic "arguments" {
    for_each = each.value.with_criteria ? ["CRITERIA"] : []
    content {
      arg_name      = arguments.value
      arg_data_type = "VARIANT"
    }
  }

  depends_on = [snowflake_function_sql.ask]
}

resource "snowflake_grant_privileges_to_account_role" "schema_usage" {
  for_each          = toset(var.caller_roles)
  account_role_name = each.value
  privileges        = ["USAGE"]

  on_schema {
    schema_name = local.schema_id
  }
}

resource "snowflake_grant_privileges_to_account_role" "existing_functions" {
  for_each          = toset(var.caller_roles)
  account_role_name = each.value
  privileges        = ["USAGE"]

  on_schema_object {
    all {
      object_type_plural = "FUNCTIONS"
      in_schema          = local.schema_id
    }
  }

  depends_on = [snowflake_function_sql.question]
}

resource "snowflake_grant_privileges_to_account_role" "future_functions" {
  for_each          = toset(var.caller_roles)
  account_role_name = each.value
  privileges        = ["USAGE"]

  on_schema_object {
    future {
      object_type_plural = "FUNCTIONS"
      in_schema          = local.schema_id
    }
  }
}
