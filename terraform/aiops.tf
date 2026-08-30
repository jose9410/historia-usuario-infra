# ═══════════════════════════════════════════════════════════════════════════════
# terraform/aiops.tf
# AIOps Module: CloudWatch Alarms, Anomaly Detection & SNS to Lambda Correlation
# ═══════════════════════════════════════════════════════════════════════════════

# ── 1. SNS Topic para las alertas ──────────────────────────────────────────────
resource "aws_sns_topic" "aiops_alerts" {
  name = "data-service-aiops-alerts"

  tags = {
    Environment = "production"
    Service     = "data-service"
    ManagedBy   = "terraform"
  }
}

# ── 2. IAM Role & Policy para la Lambda ────────────────────────────────────────
resource "aws_iam_role" "aiops_lambda_role" {
  name = "aiops-correlation-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "aiops_lambda_policy" {
  name        = "aiops-correlation-lambda-policy"
  description = "Policy for AIOps Lambda to read CW Logs and Describe Alarms"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Permisos básicos de ejecución de Lambda (escribir sus propios logs)
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        # Permisos para buscar Trace IDs en los logs del data-service
        Effect = "Allow"
        Action = [
          "logs:FilterLogEvents",
          "logs:StartQuery",
          "logs:GetQueryResults",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/ecs/data-service:*"
      },
      {
        # Permiso para consultar el estado de la otra alarma (Correlación)
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "aiops_lambda_policy_attach" {
  role       = aws_iam_role.aiops_lambda_role.name
  policy_arn = aws_iam_policy.aiops_lambda_policy.arn
}

# ── 3. Función AWS Lambda (Motor de Correlación) ───────────────────────────────

data "archive_file" "aiops_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/aiops_correlation.py"
  output_path = "${path.module}/lambda/aiops_correlation.zip"
}

resource "aws_lambda_function" "aiops_correlation_engine" {
  filename         = data.archive_file.aiops_lambda_zip.output_path
  source_code_hash = data.archive_file.aiops_lambda_zip.output_base64sha256
  function_name    = "aiops-correlation-engine"
  role             = aws_iam_role.aiops_lambda_role.arn
  handler          = "aiops_correlation.lambda_handler"
  runtime          = "python3.12"
  timeout          = 15

  tags = {
    Environment = "production"
    Service     = "aiops"
    ManagedBy   = "terraform"
  }
}

# Permiso para que SNS invoque a la Lambda
resource "aws_lambda_permission" "sns_invoke_lambda" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aiops_correlation_engine.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.aiops_alerts.arn
}

# Suscripción: Conectar el Topic SNS con la Lambda
resource "aws_sns_topic_subscription" "lambda_subscription" {
  topic_arn = aws_sns_topic.aiops_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.aiops_correlation_engine.arn
}

# ── 4. CloudWatch Alarms ───────────────────────────────────────────────────────

# Alarma 1: SLO de Latencia Estática (P99 > 500ms)
resource "aws_cloudwatch_metric_alarm" "latency_p99" {
  alarm_name          = "data-service-high-latency-p99"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 500 # 500ms
  treat_missing_data  = "notBreaching"

  metric_name = "http.server.duration"
  namespace          = "Koncilia/Metrics" # Asumiendo este namespace para las métricas de la app
  period             = 60
  extended_statistic = "p99"

  dimensions = {
    ServiceName = "data-service"
  }

  alarm_description = "Alarma de latencia P99. Dispara si el 99% de las peticiones superan los 500ms en 1 minuto."
  alarm_actions     = [aws_sns_topic.aiops_alerts.arn]
}

# Alarma 2: Anomaly Detection para Errores HTTP 5XX
resource "aws_cloudwatch_metric_alarm" "anomaly_errors" {
  alarm_name          = "data-service-anomaly-errors"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 1
  threshold_metric_id = "ad_band"
  treat_missing_data  = "notBreaching"

  alarm_description = "Anomaly Detection Alarm: Dispara si la tasa de errores HTTP 5XX sobrepasa el modelo de comportamiento esperado (Machine Learning)."
  alarm_actions     = [aws_sns_topic.aiops_alerts.arn]

  metric_query {
    id          = "ad_band"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)" # 2 desviaciones estándar de la banda
    label       = "Error Rate (Expected)"
    return_data = true
  }

  metric_query {
    id          = "m1"
    return_data = true
    metric {
      metric_name = "http.server.active_requests" # Sustituir por la métrica real de errores de OTel
      namespace   = "Koncilia/Metrics"
      period      = 60
      stat        = "Sum"
      dimensions = {
        ServiceName = "data-service"
        StatusCode  = "500"
      }
    }
  }
}
