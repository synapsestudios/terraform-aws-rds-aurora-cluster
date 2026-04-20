resource "aws_rds_cluster" "this" {
  # checkov:skip=CKV2_AWS_8: Using snapshots for backups
  # checkov:skip=CKV2_AWS_27: Parameter group is passed in as a variable
  # checkov:skip=CKV_AWS_327: We will use AWS managed keys because CMK are expensive and not necessary for our use case
  # checkov:skip=CKV_AWS_162: IAM Authentication does not fit into our use cases
  cluster_identifier_prefix       = var.name
  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  database_name                   = var.snapshot_identifier == null ? var.database_name : null
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.name}-final"
  master_username                 = var.snapshot_identifier == null ? "root" : null
  manage_master_user_password     = true
  snapshot_identifier             = var.snapshot_identifier
  db_subnet_group_name            = aws_db_subnet_group.this.name
  storage_encrypted               = true
  availability_zones              = var.availability_zones
  preferred_backup_window         = "07:00-09:00"
  backup_retention_period         = 5
  vpc_security_group_ids          = concat([aws_security_group.this.id], var.additional_security_groups)
  tags                            = var.tags
  db_cluster_parameter_group_name = var.db_cluster_parameter_group_name
  deletion_protection             = var.deletion_protection
  copy_tags_to_snapshot           = true

  enabled_cloudwatch_logs_exports = [
    "postgresql",
  ]

  lifecycle {
    # snapshot_identifier is only meaningful on create; ignoring it prevents
    # Terraform from planning to re-restore the cluster on subsequent applies.
    ignore_changes = [snapshot_identifier]
  }
}

data "aws_secretsmanager_secret_version" "root_password" {
  secret_id = aws_rds_cluster.this.master_user_secret[0].secret_arn
}

data "aws_iam_policy_document" "rds_monitoring" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                = "${var.name}-rds-monitoring-role"
  assume_role_policy  = data.aws_iam_policy_document.rds_monitoring.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"]
}

resource "aws_rds_cluster_instance" "this" {
  # checkov:skip=CKV_AWS_354: We will use AWS managed keys because CMK are expensive and not necessary for our use case
  count                        = var.instance_count
  engine                       = "aurora-postgresql"
  engine_version               = var.engine_version
  identifier_prefix            = "${var.name}-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.this.id
  instance_class               = var.instance_class
  db_subnet_group_name         = aws_db_subnet_group.this.name
  tags                         = var.tags
  auto_minor_version_upgrade   = true
  monitoring_interval          = 5
  monitoring_role_arn          = aws_iam_role.this.arn
  performance_insights_enabled = true
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
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = data.aws_vpc.database_vpc.cidr_block
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  description       = "PostgreSQL traffic in"
  tags              = var.tags
}

resource "aws_vpc_security_group_egress_rule" "postgres" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = data.aws_vpc.database_vpc.cidr_block
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  description       = "PostgreSQL traffic out"
  tags              = var.tags
}

data "aws_vpc" "database_vpc" {
  id = var.vpc_id
}
