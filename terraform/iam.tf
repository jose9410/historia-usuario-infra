# 1. ECS Task Execution Role (Allows ECS to pull images and push to CloudWatch)
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "koncilia-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 2. ECS Task Role (Permissions for the running containers, e.g., OTel Collector)
resource "aws_iam_role" "ecs_task_role" {
  name = "koncilia-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Grant AWS X-Ray write permissions for tracing
resource "aws_iam_role_policy_attachment" "ecs_task_role_xray" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Grant CloudWatch Logs permissions for logging (OTel Collector pushing logs)
resource "aws_iam_policy" "cw_logs_policy" {
  name        = "koncilia-ecs-cw-logs-policy"
  description = "Allows OTel collector to write to CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_cw" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.cw_logs_policy.arn
}
