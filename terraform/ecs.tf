resource "aws_ecs_cluster" "main" {
  name = "koncilia-cluster"
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "historia_api_logs" {
  name              = "/ecs/historia-api"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "qa_automation_api_logs" {
  name              = "/ecs/qa-automation-api"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "otel_collector_logs" {
  name              = "/ecs/otel-collector"
  retention_in_days = 7
}

# -----------------------------------------------------------------------------
# Historia API Task Definition
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "historia_api" {
  family                   = "historia-api-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "historia-api"
      image     = "066686950339.dkr.ecr.us-east-1.amazonaws.com/historia-usuario-api:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
        }
      ]
      environment = [
        { name = "OpenTelemetry__OtlpEndpoint", value = "http://localhost:4317" },
        { name = "DEPLOY_ENV", value = "aws" },
        { name = "Services__QAAutomationApi", value = var.qa_api_url },
        { name = "AzureOpenAI__DeploymentName", value = var.azure_openai_deployment_name },
        { name = "AzureOpenAI__Endpoint",        value = var.azure_openai_endpoint },
        { name = "AzureOpenAI__ApiKey",           value = var.azure_openai_api_key }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.historia_api_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },
    {
      name      = "aws-otel-collector"
      image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.otel_collector_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# QA Automation API Task Definition
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "qa_automation_api" {
  family                   = "qa-automation-api-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "qa-automation-api"
      image     = "066686950339.dkr.ecr.us-east-1.amazonaws.com/qa-automation-api:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
        }
      ]
      environment = [
        { name = "OpenTelemetry__OtlpEndpoint", value = "http://localhost:4317" },
        { name = "DEPLOY_ENV", value = "aws" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.qa_automation_api_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },
    {
      name      = "aws-otel-collector"
      image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.otel_collector_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# ECS Services
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "historia_api" {
  name            = "historia-api-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.historia_api.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}

resource "aws_ecs_service" "qa_automation_api" {
  name            = "qa-automation-api-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.qa_automation_api.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}