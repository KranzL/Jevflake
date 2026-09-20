variable "database" {
  description = "Database that holds the Jevflake schema. It must already exist."
  type        = string
}

variable "schema" {
  description = "Schema that holds the network rule, the secret, and the functions."
  type        = string
  default     = "JEVFLAKE"
}

variable "create_schema" {
  description = "Create the schema. Set to false if it already exists."
  type        = bool
  default     = true
}

variable "api_key" {
  description = "TypeSafe API key. Terraform creates a Snowflake secret from it, and the key is stored in Terraform state. Leave null and set existing_secret to keep the key out of state."
  type        = string
  default     = null
  sensitive   = true
}

variable "existing_secret" {
  description = "Full name (DATABASE.SCHEMA.NAME) of a generic string secret that already holds the TypeSafe API key. Set this or api_key, not both."
  type        = string
  default     = null
}

variable "secret_name" {
  description = "Name of the secret Terraform creates when api_key is set."
  type        = string
  default     = "JEV_API_KEY"
}

variable "network_rule_name" {
  description = "Name of the egress network rule."
  type        = string
  default     = "JEV_EGRESS"
}

variable "integration_name" {
  description = "Name of the external access integration. Integrations are account level objects."
  type        = string
  default     = "JEV_ACCESS"
}

variable "caller_roles" {
  description = "Roles that may call the functions. Each gets usage on the schema and on all current and future functions in it."
  type        = list(string)
  default     = []
}

variable "model" {
  description = "Jev model ID the functions send. Keep the dbt var jevflake_model set to the same value."
  type        = string
  default     = "jev-1.13.0"
}

variable "rows_per_request" {
  description = "Rows packed into one API call. Values above 1 are experimental."
  type        = number
  default     = 1
}

variable "concurrency" {
  description = "API calls in flight per batch of rows."
  type        = number
  default     = 8
}

variable "max_batch_size" {
  description = "Most rows Snowflake hands the function at once."
  type        = number
  default     = 64
}

variable "max_retries" {
  description = "Retries for rate limited or failed API calls."
  type        = number
  default     = 6
}

variable "timeout_seconds" {
  description = "Timeout for one API call."
  type        = number
  default     = 30
}

variable "python_version" {
  description = "Snowflake Python runtime for the function."
  type        = string
  default     = "3.11"
}
