resource "aws_rds_cluster" "this" {
  cluster_identifier              = var.namespace
  engine                          = "aurora-postgresql"
  engine_version                  = "14.6"
  database_name                   = var.database_name
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.namespace}-final"
  master_username                 = "root"
  master_password                 = aws_secretsmanager_secret_version.this.secret_string
  db_subnet_group_name            = aws_db_subnet_group.this.name
  storage_encrypted               = true
  availability_zones              = var.availability_zones
  preferred_backup_window         = "07:00-09:00"
  backup_retention_period         = 5
  vpc_security_group_ids          = concat([aws_security_group.database.id], var.additional_security_groups)
  tags                            = var.tags
  db_cluster_parameter_group_name = var.db_cluster_parameter_group_name
  deletion_protection             = true
}

resource "aws_secretsmanager_secret" "this" {
  name        = "aurora-root-${var.namespace}"
  description = "Root password for the ${var.namespace} aurora cluster database"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = random_password.password.result
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_%"
}

resource "aws_secretsmanager_secret" "connection_string" {
  name        = "aurora-connectionstring-${var.namespace}"
  description = "Connection String for the ${var.namespace} aurora cluster database"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "connection_string" {
  secret_id     = aws_secretsmanager_secret.connection_string.id
  secret_string = jsonencode(local.connection_string)
}

locals {
  connection_string = {
    POSTGRES_HOST     = aws_rds_cluster.this.endpoint
    POSTGRES_DATABASE = aws_rds_cluster.this.database_name
    POSTGRES_USER     = aws_rds_cluster.this.master_username
    POSTGRES_PASSWORD = aws_secretsmanager_secret_version.this.secret_string
    POSTGRES_PORT     = aws_rds_cluster.this.port
  }
}

resource "aws_rds_cluster_instance" "this" {
  count                = var.instance_count
  engine               = "aurora-postgresql"
  engine_version       = "14.6"
  identifier           = "${var.namespace}-${count.index + 1}"
  cluster_identifier   = aws_rds_cluster.this.id
  instance_class       = var.instance_class
  db_subnet_group_name = aws_db_subnet_group.this.name
  tags                 = var.tags
}

resource "aws_db_subnet_group" "this" {
  name        = var.namespace
  description = "RDS - ${var.namespace} Subnet Group"
  subnet_ids  = var.database_subnets
  tags        = var.tags
}

####################################
# Security Groups - Database Traffic
####################################
resource "aws_security_group" "database" {
  name        = "${var.namespace}-database-access"
  description = "Database traffic rules"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { name = "database" })
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.database_vpc.cidr_block]
  }
  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.database_vpc.cidr_block]
  }
}

data "aws_vpc" "database_vpc" {
  id = var.vpc_id
}

output "db_cluster_id" {
  value = aws_rds_cluster.this.cluster_identifier
}

output "security_group_id" {
  value = aws_security_group.database.id
}
output "db_password_secret_id" {
  value = aws_secretsmanager_secret.this.id
}
output "connection_string_arn" {
  value = aws_secretsmanager_secret.connection_string.arn
}
