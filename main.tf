resource "aws_rds_cluster" "this" {
  cluster_identifier_prefix       = var.name
  engine                          = "aurora-postgresql"
  engine_version                  = "14.6"
  database_name                   = var.database_name
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.name}-final"
  master_username                 = "root"
  master_password                 = aws_secretsmanager_secret_version.root_password.secret_string
  db_subnet_group_name            = aws_db_subnet_group.this.name
  storage_encrypted               = true
  availability_zones              = var.availability_zones
  preferred_backup_window         = "07:00-09:00"
  backup_retention_period         = 5
  vpc_security_group_ids          = concat([aws_security_group.this.id], var.additional_security_groups)
  tags                            = var.tags
  db_cluster_parameter_group_name = var.db_cluster_parameter_group_name
  deletion_protection             = true
}

resource "aws_secretsmanager_secret" "root_password" {
  name_prefix = "aurora-root-${var.name}"
  description = "Root password for the ${var.name} aurora cluster database"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "root_password" {
  secret_id     = aws_secretsmanager_secret.root_password.id
  secret_string = random_password.password.result
}

resource "random_password" "password" {
  length           = 32
  special          = true
  min_special      = 1
  override_special = "-._~" # URL-safe characters prevent parsing errors when using this password in a connection string
}

resource "aws_secretsmanager_secret" "connection_string" {
  name_prefix = "aurora-connectionstring-${var.name}"
  description = "Connection String for the ${var.name} aurora cluster database"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "connection_string" {
  secret_id     = aws_secretsmanager_secret.connection_string.id
  secret_string = "postgresql://${aws_rds_cluster.this.master_username}:${aws_secretsmanager_secret_version.root_password.secret_string}@${aws_rds_cluster.this.endpoint}:${aws_rds_cluster.this.port}/${aws_rds_cluster.this.database_name}"
}

resource "aws_rds_cluster_instance" "this" {
  count                = var.instance_count
  engine               = "aurora-postgresql"
  engine_version       = "14.6"
  identifier_prefix    = "${var.name}-${count.index + 1}"
  cluster_identifier   = aws_rds_cluster.this.id
  instance_class       = var.instance_class
  db_subnet_group_name = aws_db_subnet_group.this.name
  tags                 = var.tags
}

resource "aws_db_subnet_group" "this" {
  name_prefix = var.name
  description = "RDS - ${var.name} Subnet Group"
  subnet_ids  = var.database_subnets
  tags        = var.tags
}

####################################
# Security Groups - Database Traffic
####################################
resource "aws_security_group" "this" {
  name_prefix = "${var.name}-database-access"
  description = "Database traffic rules"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { name = "database" })
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.database_vpc.cidr_block]
    description = "PostgreSQL traffic in"
  }
  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.database_vpc.cidr_block]
    description = "PostgreSQL traffic out"
  }
}

data "aws_vpc" "database_vpc" {
  id = var.vpc_id
}

output "db_cluster_id" {
  value = aws_rds_cluster.this.cluster_identifier
}

output "security_group_id" {
  value = aws_security_group.this.id
}
output "root_password_secret_id" {
  value = aws_secretsmanager_secret.root_password.id
}
output "connection_string_arn" {
  value = aws_secretsmanager_secret.connection_string.arn
}
