# Runs the module through create, update, and destroy against AWS Emulator.
# Start the emulator with tests/emulator/run.sh, which also runs this suite.

# run.sh sets this with -var. It has no default, so the file can't run
# without the script. Variable blocks in test files need Terraform 1.13.
variable "emulator_endpoint" {
  type = string
}

variables {
  name                            = "lifecycle"
  deletion_protection             = false
  db_cluster_parameter_group_name = "set-by-setup"
  vpc_id                          = "set-by-setup"
  availability_zones              = []
  database_subnets                = []
}

# Every endpoint points at the local proxy, so this file can't reach AWS even
# with real credentials in the environment. allowed_account_ids is a second
# guard: the emulator always answers as account 000000000000.
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

run "setup" {
  command = apply

  module {
    source = "./tests/emulator/setup"
  }
}

run "creates_a_cluster_with_one_writer" {
  command = apply

  variables {
    vpc_id                          = run.setup.vpc_id
    availability_zones              = run.setup.availability_zones
    database_subnets                = run.setup.subnet_ids
    db_cluster_parameter_group_name = run.setup.db_cluster_parameter_group_name
  }

  assert {
    condition     = startswith(output.instance_identifiers[0], "lifecycle-1")
    error_message = "The first instance identifier should start with <name>-1, got ${output.instance_identifiers[0]}"
  }

  assert {
    condition     = startswith(output.db_cluster_id, "lifecycle")
    error_message = "The cluster identifier should start with the module name, got ${output.db_cluster_id}"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.postgres.cidr_ipv4 == run.setup.vpc_cidr_block
    error_message = "Postgres ingress should allow the CIDR of the VPC passed in as vpc_id"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.postgres.cidr_ipv4 == run.setup.vpc_cidr_block
    error_message = "Postgres egress should allow the CIDR of the VPC passed in as vpc_id"
  }

  assert {
    condition     = jsondecode(data.aws_secretsmanager_secret_version.root_password.secret_string).username == "root"
    error_message = "The secret the module reads from master_user_secret should hold the master username"
  }

  assert {
    condition     = startswith(output.master_user_secret_arn, "arn:aws:secretsmanager:us-east-1:000000000000:secret:")
    error_message = "master_user_secret_arn should be a Secrets Manager ARN, got ${output.master_user_secret_arn}"
  }
}

run "adds_a_second_instance_without_replacing_the_cluster" {
  command = apply

  variables {
    vpc_id                          = run.setup.vpc_id
    availability_zones              = run.setup.availability_zones
    database_subnets                = run.setup.subnet_ids
    db_cluster_parameter_group_name = run.setup.db_cluster_parameter_group_name
    instance_count                  = 2
  }

  assert {
    condition     = output.db_cluster_id == run.creates_a_cluster_with_one_writer.db_cluster_id
    error_message = "Raising instance_count should add an instance, not replace the cluster"
  }

  assert {
    condition     = output.instance_identifiers[0] == run.creates_a_cluster_with_one_writer.instance_identifiers[0]
    error_message = "Raising instance_count should keep the first instance"
  }

  assert {
    condition     = startswith(output.instance_identifiers[1], "lifecycle-2")
    error_message = "The second instance identifier should start with <name>-2, got ${output.instance_identifiers[1]}"
  }
}
