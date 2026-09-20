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

variable "typesafe_api_key" {
  type      = string
  default   = null
  sensitive = true
}

variable "existing_secret" {
  type    = string
  default = null
}

variable "caller_roles" {
  type    = list(string)
  default = []
}

module "jevflake" {
  source = "../../"

  database         = var.database
  schema           = var.schema
  integration_name = var.integration_name
  api_key          = var.typesafe_api_key
  existing_secret  = var.existing_secret
  caller_roles     = var.caller_roles
}

output "functions" {
  value = module.jevflake.functions
}

output "dbt_vars" {
  value = {
    jevflake_database = module.jevflake.database
    jevflake_schema   = module.jevflake.schema
  }
}
