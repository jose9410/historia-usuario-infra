# ═══════════════════════════════════════════════════════════════════════════════
# terraform/rds.tf
# AWS RDS PostgreSQL para data-service
#
# Recursos creados:
#   - aws_db_subnet_group     : Subnet group para la instancia RDS
#   - aws_security_group      : SG que solo permite tráfico desde ECS (port 5432)
#   - aws_db_instance         : Instancia RDS PostgreSQL 16
#   - aws_secretsmanager_secret: Secreto con el ConnectionString completo
#   - aws_secretsmanager_secret_version: Valor del secreto
#
# IMPORTANTE: La contraseña de la BD se pasa via variable 'db_password' (sensitive).
# NUNCA hardcodear contraseñas aquí. Usar terraform.tfvars o variables de CI/CD.
#
# Para obtener el ARN del secreto (necesario para ecs.tf):
#   terraform output db_secret_arn
# ═══════════════════════════════════════════════════════════════════════════════

# ── Leer la red existente ──────────────────────────────────────────────────────
# Referencia las subnets públicas ya definidas en network.tf
# RDS se coloca en subnets privadas idealmente, pero se reutiliza la red existente
# para mantener la consistencia con la infraestructura actual.

# ── Security Group: RDS PostgreSQL ────────────────────────────────────────────
resource "aws_security_group" "rds_sg" {
  name        = "koncilia-rds-sg"
  description = "Permite trafico PostgreSQL (5432) solo desde los contenedores ECS de Koncilia"
  vpc_id      = aws_vpc.main.id

  # Solo acepta conexiones desde el Security Group de ECS
  ingress {
    description     = "PostgreSQL desde ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  # Sin egress hacia internet — RDS solo responde a quienes se conectan
  egress {
    description = "Respuestas al cliente ECS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "koncilia-rds-sg"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# ── DB Subnet Group ────────────────────────────────────────────────────────────
# RDS necesita al menos 2 subnets en AZs diferentes para Multi-AZ
resource "aws_db_subnet_group" "main" {
  name        = "koncilia-db-subnet-group"
  description = "Subnet group para RDS PostgreSQL de Koncilia data-service"
  subnet_ids  = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name      = "koncilia-db-subnet-group"
    ManagedBy = "terraform"
  }
}

# ── RDS Instance — PostgreSQL 16 ───────────────────────────────────────────────
resource "aws_db_instance" "koncilia_data" {
  # ── Identificador y motor ──────────────────────────────────────────────────
  identifier     = "koncilia-data-db"
  engine         = "postgres"
  engine_version = "16.3"
  instance_class = var.db_instance_class # "db.t3.micro" para dev, "db.t3.small" para prod

  # ── Almacenamiento ─────────────────────────────────────────────────────────
  allocated_storage     = 20  # GB mínimo para gp2
  max_allocated_storage = 100 # Auto-scaling hasta 100 GB
  storage_type          = "gp2"
  storage_encrypted     = true # Cifrado en reposo con AWS KMS

  # ── Base de datos inicial ──────────────────────────────────────────────────
  db_name  = "koncilia_data"
  username = var.db_username
  password = var.db_password # Variable sensitive — no aparece en logs

  # ── Red ────────────────────────────────────────────────────────────────────
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false # Solo accesible desde dentro de la VPC

  # ── Disponibilidad ─────────────────────────────────────────────────────────
  multi_az          = false # Cambiar a true para producción real
  availability_zone = "${var.aws_region}a"

  # ── Mantenimiento y backups ────────────────────────────────────────────────
  backup_retention_period         = 0 # 0 para evitar errores de capa gratuita (Free Tier)
  # backup_window                 = "03:00-04:00" # Deshabilitado porque no hay backups automáticos
  maintenance_window              = "sun:04:00-sun:05:00"
  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # ── Seguridad ──────────────────────────────────────────────────────────────
  deletion_protection = false # Cambiar a true en producción
  skip_final_snapshot = true  # Cambiar a false en producción
  # final_snapshot_identifier = "koncilia-data-final-snapshot"  # descomentar en prod

  # ── Parámetros de PostgreSQL ───────────────────────────────────────────────
  # Parámetros por defecto de PG16 son adecuados para este workload.
  # Para tuning avanzado, crear un aws_db_parameter_group separado.

  tags = {
    Name        = "koncilia-data-db"
    Service     = "data-service"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# ── AWS Secrets Manager — ConnectionString ─────────────────────────────────────
# El secreto almacena el ConnectionString completo de EF Core + Npgsql.
# ECS lo referencia en la task definition via "secrets" (no "environment").
# Esto evita que la contraseña aparezca en texto plano en la consola ECS.
resource "aws_secretsmanager_secret" "db_connection_string" {
  name                    = "koncilia/data-service/db-connection-string"
  description             = "ConnectionString de PostgreSQL para data-service (formato Npgsql)"
  recovery_window_in_days = 0 # 0 para permitir recreación inmediata en caso de destroy y re-apply

  tags = {
    Service   = "data-service"
    ManagedBy = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "db_connection_string" {
  secret_id = aws_secretsmanager_secret.db_connection_string.id

  # Formato compatible con Npgsql / EF Core Npgsql provider
  secret_string = "Host=${aws_db_instance.koncilia_data.address};Port=5432;Database=koncilia_data;Username=${var.db_username};Password=${var.db_password};SSL Mode=Require;Trust Server Certificate=true;Application Name=data-service"
}
