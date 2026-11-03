mock_provider "aws" {
  # The mock provider fabricates random strings for computed attributes, which
  # the AWS provider's own input validators then reject. Override the handful
  # of values that get validated so plan/apply doesn't fail on unrelated checks.
  # See hashicorp/terraform-provider-aws#42834.
  #
  # These mocks exist so the module can plan/apply successfully under a fake
  # provider — assertions in run blocks target the module's own logic, not
  # these mock values.
  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.0.0.0/16"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_secretsmanager_secret_version" {
    defaults = {
      secret_string = "{\"username\":\"root\",\"password\":\"mock-password\"}"
    }
  }

  mock_resource "aws_rds_cluster" {
    defaults = {
      # master_user_secret is a nested block the module reads; mock provider
      # returns an empty list by default, which breaks outputs.tf's [0] index.
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:us-west-2:123456789012:secret:mock-master-user-secret"
        secret_status = "active"
        kms_key_id    = ""
      }]
    }
  }
}

variables {
  name                            = "test-cluster"
  vpc_id                          = "vpc-12345678"
  availability_zones              = ["us-west-2a", "us-west-2b"]
  database_subnets                = ["subnet-11111111", "subnet-22222222"]
  db_cluster_parameter_group_name = "test-pg"
}

run "fresh_cluster_defaults" {
  command = plan

  assert {
    condition     = aws_rds_cluster.this.snapshot_identifier == null
    error_message = "snapshot_identifier should be null by default"
  }

  assert {
    condition     = aws_rds_cluster.this.database_name == "main"
    error_message = "database_name should default to 'main' when not restoring from a snapshot"
  }

  assert {
    condition     = aws_rds_cluster.this.master_username == "root"
    error_message = "master_username should be 'root' when not restoring from a snapshot"
  }
}

run "fresh_cluster_honors_database_name_override" {
  command = plan

  variables {
    database_name = "custom_db"
  }

  assert {
    condition     = aws_rds_cluster.this.database_name == "custom_db"
    error_message = "database_name input should propagate when not restoring from a snapshot"
  }
}

run "restore_from_snapshot_passes_identifier_through" {
  command = plan

  variables {
    snapshot_identifier = "test-snapshot-id"
  }

  assert {
    condition     = aws_rds_cluster.this.snapshot_identifier == "test-snapshot-id"
    error_message = "snapshot_identifier should be forwarded to the cluster resource"
  }
}

run "no_ingress_by_default" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.allowed_security_group) == 0
    error_message = "The cluster's security group should admit nothing unless allowed_security_group_ids names a source"
  }
}

run "one_ingress_rule_per_allowed_security_group" {
  command = plan

  variables {
    allowed_security_group_ids = {
      api    = "sg-11111111"
      worker = "sg-22222222"
    }
  }

  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.allowed_security_group)) == toset(["api", "worker"])
    error_message = "There should be one ingress rule per allowed_security_group_ids entry, keyed by the entry's name"
  }

  assert {
    condition = alltrue([
      for key, rule in aws_vpc_security_group_ingress_rule.allowed_security_group :
      rule.referenced_security_group_id == var.allowed_security_group_ids[key]
    ])
    error_message = "Each ingress rule should admit the security group its entry names"
  }

  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_ingress_rule.allowed_security_group :
      rule.from_port == 5432 && rule.to_port == 5432 && rule.ip_protocol == "tcp"
    ])
    error_message = "Each ingress rule should admit PostgreSQL only, TCP 5432"
  }

  assert {
    condition = alltrue([
      for key, rule in aws_vpc_security_group_ingress_rule.allowed_security_group :
      strcontains(rule.description, key)
    ])
    error_message = "Each ingress rule's description should name its source"
  }
}

# Callers often create a client's security group in the same apply as the
# cluster, so its ID is unknown at plan. for_each over the IDs themselves
# would fail to plan there. The plan succeeding is the assertion.
run "plans_when_allowed_security_group_ids_are_unknown" {
  command = plan

  module {
    source = "./tests/unit/fixtures/client_in_same_apply"
  }
}

run "sg_egress_postgres_to_vpc_cidr" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_egress_rule.postgres.from_port == 5432
    error_message = "Postgres egress from_port should be 5432"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.postgres.to_port == 5432
    error_message = "Postgres egress to_port should be 5432"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.postgres.ip_protocol == "tcp"
    error_message = "Postgres egress ip_protocol should be tcp"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.postgres.cidr_ipv4 == data.aws_vpc.database_vpc.cidr_block
    error_message = "Postgres egress cidr_ipv4 should equal the VPC CIDR"
  }
}

run "rds_monitoring_role_has_enhanced_monitoring_policy_attached" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.rds_monitoring.role == aws_iam_role.this.name
    error_message = "Enhanced monitoring policy attachment should target the module's IAM role"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.rds_monitoring.policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
    error_message = "Enhanced monitoring policy attachment should attach the AWS-managed AmazonRDSEnhancedMonitoringRole policy"
  }
}

run "instance_identifiers_has_one_entry_per_instance_before_the_identifiers_are_known" {
  command = plan

  variables {
    instance_count = 2
  }

  assert {
    condition     = length(output.instance_identifiers) == 2
    error_message = "Callers key per-instance resources on this list, so its length must be known at plan"
  }
}

# Note: we don't assert that database_name/master_username are null on the
# cluster resource when snapshot_identifier is set. Under `command = plan`,
# those attributes read as "(known after apply)" because the AWS API populates
# them from the snapshot. Under `command = apply`, the mock provider replaces
# nulls with fabricated strings. The conditional null-ing is trivially readable
# in main.tf — tests can't add confidence here without asserting against mocks.
