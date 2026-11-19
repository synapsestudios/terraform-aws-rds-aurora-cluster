# A cluster and a snapshot of it, for the restore test. The master username is
# not "root", so the test can tell whether the module kept the snapshot's value.

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "subnet_ids" {
  description = "IDs of the subnets for the source cluster's DB subnet group."
  type        = list(string)
}

locals {
  master_username = "snapuser"
}

resource "aws_db_subnet_group" "source" {
  name_prefix = "snapshot-source"
  subnet_ids  = var.subnet_ids
}

resource "aws_rds_cluster" "source" {
  cluster_identifier_prefix   = "snapshot-source"
  engine                      = "aurora-postgresql"
  engine_version              = "14"
  database_name               = "sourcedb"
  master_username             = local.master_username
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.source.name
  skip_final_snapshot         = true
}

resource "aws_db_cluster_snapshot" "source" {
  db_cluster_identifier          = aws_rds_cluster.source.id
  db_cluster_snapshot_identifier = "${aws_rds_cluster.source.id}-snapshot"
}

output "snapshot_identifier" {
  description = "Identifier of the snapshot the restore test restores from."
  value       = aws_db_cluster_snapshot.source.db_cluster_snapshot_identifier
}

output "master_username" {
  description = "Master username of the source cluster, which the restored cluster should keep."
  value       = local.master_username
}
