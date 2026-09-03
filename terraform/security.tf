# ═══════════════════════════════════════════════════════════════════════════════
# terraform/security.tf
# Módulo C: Observabilidad de Red y Seguridad (Network and Security Observability)
# ═══════════════════════════════════════════════════════════════════════════════

# ── 1. VPC FLOW LOGS (Observabilidad de Red) ───────────────────────────────────
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flow-logs"
  retention_in_days = 30
}

data "aws_iam_policy_document" "vpc_flow_logs_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "vpc_flow_logs_role" {
  name               = "VPCFlowLogsRole"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_logs_assume_role.json
}

data "aws_iam_policy_document" "vpc_flow_logs_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs_policy" {
  name   = "VPCFlowLogsPolicy"
  role   = aws_iam_role.vpc_flow_logs_role.id
  policy = data.aws_iam_policy_document.vpc_flow_logs_policy.json
}

resource "aws_flow_log" "vpc_flow_log" {
  iam_role_arn    = aws_iam_role.vpc_flow_logs_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

# ── 2. AWS SECURITY HUB (Observabilidad de Seguridad) ──────────────────────────
# Deshabilitado temporalmente si la cuenta no tiene suscripción activa a Security Hub
# resource "aws_securityhub_account" "main" {}

# ── 3. GOLDEN SIGNALS DE SEGURIDAD (Métricas y Alertas) ────────────────────────

# A) Tráfico Anómalo (Métricas de Red - REJECTED)
resource "aws_cloudwatch_log_metric_filter" "vpc_flow_logs_rejects" {
  name           = "VPCFlowLogsRejectedConnections"
  pattern        = "[version, account_id, interface_id, srcaddr, dstaddr, srcport, dstport, protocol, packets, bytes, start, end, action=\"REJECT\", log_status]"
  log_group_name = aws_cloudwatch_log_group.vpc_flow_logs.name

  metric_transformation {
    name      = "RejectedConnections"
    namespace = "SecurityGoldenSignals"
    value     = "1"
  }
}

# B) Intentos de Autenticación Fallidos (RDS PostgreSQL)
# El log group lo crea RDS automáticamente al tener 'enabled_cloudwatch_logs_exports = ["postgresql"]'
resource "aws_cloudwatch_log_metric_filter" "rds_failed_auth" {
  name           = "RDSFailedAuthentication"
  pattern        = "\"password authentication failed\""
  log_group_name = "/aws/rds/instance/${aws_db_instance.koncilia_data.identifier}/postgresql"
  depends_on     = [aws_db_instance.koncilia_data]

  metric_transformation {
    name      = "FailedDBAuthentications"
    namespace = "SecurityGoldenSignals"
    value     = "1"
  }
}

# C) Vulnerabilidades (CVEs activos en Inspector/ECR) - Simulación de Alarma
resource "aws_cloudwatch_metric_alarm" "critical_cve_alarm" {
  alarm_name          = "Critical-CVE-Detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CriticalVulnerabilities"
  namespace           = "SecurityGoldenSignals"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Se activará si Amazon Inspector/ECR detecta un CVE de severidad CRITICAL o HIGH"
}

# ── 4. DASHBOARD DE CLOUDWATCH (Seguridad) ─────────────────────────────────────
resource "aws_cloudwatch_dashboard" "security_dashboard" {
  dashboard_name = "Security-Golden-Signals"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["SecurityGoldenSignals", "FailedDBAuthentications"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Intentos de Autenticación Fallidos en RDS"
          stat    = "Sum"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["SecurityGoldenSignals", "RejectedConnections"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Tasa de Paquetes Rechazados (VPC REJECTS)"
          stat    = "Sum"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["SecurityGoldenSignals", "CriticalVulnerabilities"]
          ]
          view    = "singleValue"
          region  = var.aws_region
          title   = "Contador de Alertas de Seguridad Críticas (CVEs)"
          stat    = "Maximum"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            # Ejemplo ilustrativo para tráfico Norte-Sur vs Este-Oeste
            # (En ECS Fargate se usan métricas de NAT Gateway o Load Balancer para medir esto con precisión)
            ["AWS/NATGateway", "BytesOutToDestination", "NatGatewayId", "nat-xxxxxxxxxxxx"],
            ["AWS/NATGateway", "BytesInFromSource", "NatGatewayId", "nat-xxxxxxxxxxxx"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Conexiones Este-Oeste vs Norte-Sur (Muestra)"
          stat    = "Average"
          period  = 300
        }
      }
    ]
  })
}
