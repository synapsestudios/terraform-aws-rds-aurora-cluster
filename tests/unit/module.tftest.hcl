# Fast tests of the module's own logic against the mock provider: defaults
# picked by conditionals, for_each keys, plan-time lengths, and names built
# from interpolation. tests/emulator applies, updates, and destroys the module
# against AWS Emulator.

mock_provider "aws" {
  # The mock provider fabricates random strings for computed attributes. The
  # AWS provider's input validators reject some of them, and outputs.tf can't
  # decode or index others. Override those so plan/apply doesn't fail on
  # unrelated checks.
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
    condition     = aws_rds_cluster.this.database_name == "main"
    error_message = "database_name should default to 'main' when not restoring from a snapshot"
  }

  assert {
    condition     = aws_rds_cluster.this.master_username == "root"
    error_message = "master_username should be 'root' when not restoring from a snapshot"
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

# A restored cluster takes its master username from the snapshot. That value
# is unknown at plan, and the mock provider fills it with a random string at
# apply, so tests/emulator/restore.tftest.hcl covers it against a real snapshot.

# The runs below apply against the mock provider and share state, so each run
# starts from the cluster the run before it left behind.
run "final_snapshot_name_ends_in_a_suffix" {
  command = apply

  assert {
    condition     = can(regex("^test-cluster-final-[0-9a-f]{8}$", output.final_snapshot_identifier))
    error_message = "The final snapshot name should be the cluster name, then -final-, then an 8 character suffix"
  }
}

run "final_snapshot_name_survives_an_update_in_place" {
  command = apply

  variables {
    tags = {
      Team = "data"
    }
  }

  assert {
    condition     = output.final_snapshot_identifier == run.final_snapshot_name_ends_in_a_suffix.final_snapshot_identifier
    error_message = "An update that keeps the cluster should keep its final snapshot name, or every plan would show a change"
  }
}

# Replacing the cluster destroys the old one, which takes its final snapshot.
# The new cluster needs a different name or its own destroy fails with
# DBClusterSnapshotAlreadyExistsFault.
run "final_snapshot_name_changes_when_the_cluster_is_replaced" {
  command = apply

  plan_options {
    replace = [aws_rds_cluster.this]
  }

  assert {
    condition     = output.final_snapshot_identifier != run.final_snapshot_name_survives_an_update_in_place.final_snapshot_identifier
    error_message = "A replaced cluster should get a new final snapshot name, because the old cluster's snapshot already holds the old one"
  }
}
