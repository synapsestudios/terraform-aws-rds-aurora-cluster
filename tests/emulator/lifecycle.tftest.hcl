# Runs the module through create, update, and destroy against AWS Emulator.
# Start the emulator with tests/emulator/run.sh, which also runs this suite.

# run.sh and CI set this with -var. It has no default, so the file won't run
# without it. Variable blocks in test files need Terraform 1.13.
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

# Every service the module and fixtures call points at the local emulator, so
# this file can't reach AWS even with real credentials in the environment. allowed_account_ids is a second
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
    condition     = aws_vpc_security_group_egress_rule.postgres.cidr_ipv4 == run.setup.vpc_cidr_block
    error_message = "Postgres egress should allow the CIDR of the VPC passed in as vpc_id"
  }

  assert {
    condition     = jsondecode(data.aws_secretsmanager_secret_version.root_password.secret_string).username == "root"
    error_message = "The secret the module reads from master_user_secret should hold the master username"
  }

  # RDS stores the managed credentials as JSON with username and password keys.
  assert {
    condition     = output.root_credentials.password == jsondecode(data.aws_secretsmanager_secret_version.root_password.secret_string).password
    error_message = "root_credentials.password should be the password key of the managed secret"
  }

  assert {
    condition     = output.root_credentials.password != data.aws_secretsmanager_secret_version.root_password.secret_string
    error_message = "root_credentials.password should be the password alone, not the whole secret JSON"
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

run "admits_a_new_client_without_replacing_the_cluster" {
  command = apply

  variables {
    vpc_id                          = run.setup.vpc_id
    availability_zones              = run.setup.availability_zones
    database_subnets                = run.setup.subnet_ids
    db_cluster_parameter_group_name = run.setup.db_cluster_parameter_group_name
    instance_count                  = 2
    allowed_security_group_ids = {
      app = run.setup.client_security_group_id
    }
  }

  assert {
    condition     = output.db_cluster_id == run.creates_a_cluster_with_one_writer.db_cluster_id
    error_message = "Adding an allowed security group should not replace the cluster"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.allowed_security_group["app"].referenced_security_group_id == run.setup.client_security_group_id
    error_message = "The ingress rule should admit the client security group"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.allowed_security_group["app"].security_group_id == output.security_group_id
    error_message = "The ingress rule should belong to the cluster's security group"
  }
}
