# Checks the values tests/unit/ invents with mock overrides against what AWS
# Emulator returns. Each pair of runs applies the same assertions, once with
# the mock provider and once with the emulator. If an emulator run fails, a
# mock override in tests/unit/ no longer matches the API.
#
# state_key keeps the mock and emulator applies in separate state.

# run.sh sets this with -var. It has no default, so the file can't run
# without the script. Variable blocks in test files need Terraform 1.13.
variable "emulator_endpoint" {
  type = string
}

variables {
  name                            = "contract"
  deletion_protection             = false
  db_cluster_parameter_group_name = "test-pg"
  vpc_id                          = "vpc-12345678"
  availability_zones              = ["us-east-1a", "us-east-1b"]
  database_subnets                = ["subnet-11111111", "subnet-22222222"]
}

# See lifecycle.tftest.hcl for why every endpoint is set.
provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = ["000000000000"]

  endpoints {
    ec2            = var.emulator_endpoint
    iam            = var.emulator_endpoint
    rds            = var.emulator_endpoint
    secretsmanager = var.emulator_endpoint
    sts            = var.emulator_endpoint
  }
}

# The same overrides as tests/unit/module.tftest.hcl, plus the ARNs an apply
# needs. Keep the two in step.
mock_provider "aws" {
  alias = "mock"

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
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:us-west-2:123456789012:secret:mock-master-user-secret"
        secret_status = "active"
        kms_key_id    = ""
      }]
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-rds-monitoring-role"
    }
  }
}

run "setup" {
  command = apply

  module {
    source = "./tests/emulator/setup"
  }
}

run "mock" {
  command = apply

  providers = {
    aws = aws.mock
  }
  state_key = "mock"

  assert {
    condition     = length(aws_rds_cluster.this.master_user_secret) == 1
    error_message = "outputs.tf reads master_user_secret[0], so the cluster should report exactly one managed secret"
  }

  assert {
    condition     = can(jsondecode(data.aws_secretsmanager_secret_version.root_password.secret_string).password)
    error_message = "The managed secret should be JSON with a password key"
  }

  assert {
    condition     = jsondecode(data.aws_secretsmanager_secret_version.root_password.secret_string).username == aws_rds_cluster.this.master_username
    error_message = "The managed secret's username should match the cluster's master username"
  }

  assert {
    condition     = can(regex("^arn:aws:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:", output.master_user_secret_arn))
    error_message = "master_user_secret_arn should be a Secrets Manager ARN, got ${output.master_user_secret_arn}"
  }

  assert {
    condition     = can(cidrhost(aws_vpc_security_group_egress_rule.postgres.cidr_ipv4, 0))
    error_message = "The VPC CIDR the security group rules use should be a valid CIDR block"
  }
}

run "emulator" {
  command = apply

  state_key = "emulator"

  variables {
    vpc_id                          = run.setup.vpc_id
    availability_zones              = run.setup.availability_zones
    database_subnets                = run.setup.subnet_ids
    db_cluster_parameter_group_name = run.setup.db_cluster_parameter_group_name
  }

  assert {
    condition     = length(aws_rds_cluster.this.master_user_secret) == 1
    error_message = "outputs.tf reads master_user_secret[0], so the cluster should report exactly one managed secret"
  }

  assert {
    condition     = can(jsondecode(data.aws_secretsmanager_secret_version.root_password.secret_string).password)
    error_message = "The managed secret should be JSON with a password key"
  }

  assert {
    condition     = jsondecode(data.aws_secretsmanager_secret_version.root_password.secret_string).username == aws_rds_cluster.this.master_username
    error_message = "The managed secret's username should match the cluster's master username"
  }

  assert {
    condition     = can(regex("^arn:aws:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:", output.master_user_secret_arn))
    error_message = "master_user_secret_arn should be a Secrets Manager ARN, got ${output.master_user_secret_arn}"
  }

  assert {
    condition     = can(cidrhost(aws_vpc_security_group_egress_rule.postgres.cidr_ipv4, 0))
    error_message = "The VPC CIDR the security group rules use should be a valid CIDR block"
  }
}
