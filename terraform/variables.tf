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
