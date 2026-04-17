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

# Note: we don't assert that database_name/master_username are null on the
# cluster resource when snapshot_identifier is set. Under `command = plan`,
# those attributes read as "(known after apply)" because the AWS API populates
# them from the snapshot. Under `command = apply`, the mock provider replaces
# nulls with fabricated strings. The conditional null-ing is trivially readable
# in main.tf — tests can't add confidence here without asserting against mocks.
