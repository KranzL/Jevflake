output "database" {
  description = "Database that holds the functions. Use it for the dbt var jevflake_database."
  value       = local.database
}

output "schema" {
  description = "Schema that holds the functions. Use it for the dbt var jevflake_schema."
  value       = local.schema
}

output "integration_name" {
  description = "Name of the external access integration."
  value       = snowflake_external_access_integration.jev.name
}

output "network_rule" {
  description = "Full name of the egress network rule."
  value       = snowflake_network_rule.egress.fully_qualified_name
}

output "secret" {
  description = "Full name of the secret the functions read the API key from."
  value       = local.secret_id
}

output "functions" {
  description = "Full names of the SQL functions you call."
  value = sort(distinct(concat(
    [for function in snowflake_function_sql.ask : "${local.namespace}.${function.name}"],
    [for function in snowflake_function_sql.question : "${local.namespace}.${function.name}"],
  )))
}
