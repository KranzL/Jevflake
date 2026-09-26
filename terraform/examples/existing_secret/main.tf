terraform {
  required_version = ">= 1.5"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = ">= 2.21, < 3.0"
    }
  }
}

provider "snowflake" {
  preview_features_enabled = [
    "snowflake_network_rule_resource",
    "snowflake_external_access_integration_resource",
    "snowflake_function_sql_resource",
  ]
}

variable "database" {
  type = string
}

variable "schema" {
  type    = string
  default = "JEVFLAKE"
}

variable "integration_name" {
  type    = string
  default = "JEV_ACCESS"
}

variable "existing_secret" {
  type        = string
  description = "Full name of the secret that already holds the TypeSafe API key."
}

variable "caller_roles" {
  type    = list(string)
  default = []
}

variable "model" {
  type    = string
  default = "jev-1.13.0"
}

module "jevflake" {
  source = "../../"

  database         = var.database
  schema           = var.schema
  integration_name = var.integration_name
  existing_secret  = var.existing_secret
  caller_roles     = var.caller_roles
  model            = var.model
}

output "functions" {
  value = module.jevflake.functions
}

output "function_signatures" {
  value = module.jevflake.function_signatures
}

output "dbt_vars" {
  value = {
    jevflake_database = module.jevflake.database
    jevflake_schema   = module.jevflake.schema
    jevflake_model    = module.jevflake.model
  }
}
