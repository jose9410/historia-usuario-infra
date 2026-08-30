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

resource "aws_cloudwatch_log_group" "data_service_logs" {
  name              = "/ecs/data-service"
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
# Data Service Task Definition
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "data_service" {
  family                   = "data-service-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "data-service"
      image     = "066686950339.dkr.ecr.${var.aws_region}.amazonaws.com/data-service:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        # El sidecar aws-otel-collector escucha en localhost:4317 dentro de la tarea
        { name = "OpenTelemetry__OtlpEndpoint", value = "http://localhost:4317" },
        { name = "DEPLOY_ENV",                  value = "aws" },
        { name = "ASPNETCORE_ENVIRONMENT",       value = "production" }
      ]
      # ConnectionString inyectado desde Secrets Manager (NO como variable de entorno en texto plano)
      # ECS mapea el valor del secreto a la variable de entorno indicada en 'name'
      secrets = [
        {
          name      = "ConnectionStrings__PostgreSQL"
          valueFrom = aws_secretsmanager_secret.db_connection_string.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.data_service_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      # Health check nativo de ECS (complementa el health check del ALB si se añade)
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60  # Dar tiempo a las migraciones de BD al arranque inicial
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

# IAM: Permitir al execution role leer el secreto del ConnectionString desde Secrets Manager
# Sin este permiso, ECS no puede inyectar el secreto en el contenedor data-service.
resource "aws_iam_role_policy" "ecs_execution_secrets_manager" {
  name = "koncilia-ecs-secrets-manager-policy"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.db_connection_string.arn
      }
    ]
  })
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

resource "aws_ecs_service" "data_service" {
  name            = "data-service-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.data_service.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  # Dependencia explícita: data-service requiere que la BD esté disponible
  depends_on = [aws_db_instance.koncilia_data]
}