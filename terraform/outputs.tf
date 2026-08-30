output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "historia_api_service_name" {
  description = "The name of the Historia API service"
  value       = aws_ecs_service.historia_api.name
}

output "qa_automation_api_service_name" {
  description = "The name of the QA Automation API service"
  value       = aws_ecs_service.qa_automation_api.name
}

output "data_service_service_name" {
  description = "The name of the Data Service ECS service"
  value       = aws_ecs_service.data_service.name
}

output "rds_endpoint" {
  description = "Endpoint de la instancia RDS PostgreSQL (host:port)"
  value       = "${aws_db_instance.koncilia_data.address}:${aws_db_instance.koncilia_data.port}"
}

output "db_secret_arn" {
  description = "ARN del secreto en Secrets Manager que contiene el ConnectionString del data-service"
  value       = aws_secretsmanager_secret.db_connection_string.arn
  sensitive   = false # El ARN no es sensible; el valor del secreto sí lo es
}

output "next_steps" {
  description = "Instructions for getting the public IP addresses"
  value       = <<EOT
To access your services, they have been deployed to ECS Fargate with public IPs assigned.
Because we are not using an Application Load Balancer (for cost reasons in this academic lab),
you can find the public IP for each service by running:

aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.historia_api.name}
aws ecs describe-tasks --cluster ${aws_ecs_cluster.main.name} --tasks <task-arn>

(Look for the "publicIpv4Address" under the task's network interfaces in the AWS Console or CLI).
EOT
}
