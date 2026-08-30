variable "aws_region" {
  description = "The AWS region to deploy to"
  type        = string
  default     = "us-east-1"
}

variable "qa_api_url" {
  description = "URL of the QA Automation API (service-b)"
  type        = string
  default     = "http://localhost:8081"
}

variable "azure_openai_deployment_name" {
  description = "Azure OpenAI deployment name"
  type        = string
  default     = ""
}

variable "azure_openai_endpoint" {
  description = "Azure OpenAI endpoint URL"
  type        = string
  default     = ""
}

variable "azure_openai_api_key" {
  description = "Azure OpenAI API key — NEVER hardcode this value"
  type        = string
  sensitive   = true  # Terraform will redact this from logs
  default     = ""
}

# ─────────────────────────────────────────────────────────────────────────────
# RDS PostgreSQL — data-service
# ─────────────────────────────────────────────────────────────────────────────
variable "db_username" {
  description = "Usuario maestro de la base de datos RDS PostgreSQL"
  type        = string
  default     = "koncilia"
}

variable "db_password" {
  description = "Contraseña del usuario maestro de RDS — NUNCA hardcodear. Usar terraform.tfvars o CI/CD secrets."
  type        = string
  sensitive   = true  # Terraform redacta este valor en todos los logs y plan output
}

variable "db_instance_class" {
  description = "Tipo de instancia RDS. Usar db.t3.micro para dev/test, db.t3.small o superior para producción."
  type        = string
  default     = "db.t3.micro"
}
