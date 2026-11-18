# Restores the module's cluster from a snapshot inside AWS Emulator.
# Start the emulator with tests/emulator/run.sh, which also runs this suite.

# run.sh sets this with -var. It has no default, so the file can't run
# without the script. Variable blocks in test files need Terraform 1.13.
variable "emulator_endpoint" {
  type = string
}

variables {
  name                            = "restored"
  deletion_protection             = false
  db_cluster_parameter_group_name = "set-by-setup"
  vpc_id                          = "set-by-setup"
  availability_zones              = []
  database_subnets                = []
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

run "setup" {
  command = apply

  module {
    source = "./tests/emulator/setup"
  }
}

run "snapshot" {
  command = apply

  module {
    source = "./tests/emulator/snapshot_source"
  }

  variables {
    subnet_ids = run.setup.subnet_ids
  }
}

run "restores_with_the_snapshot_master_username" {
  command = apply

  variables {
    vpc_id                          = run.setup.vpc_id
    availability_zones              = run.setup.availability_zones
    database_subnets                = run.setup.subnet_ids
    db_cluster_parameter_group_name = run.setup.db_cluster_parameter_group_name
    snapshot_identifier             = run.snapshot.snapshot_identifier
  }

  assert {
    condition     = output.master_username == run.snapshot.master_username
    error_message = "A restored cluster should keep the snapshot's master username, got ${output.master_username}"
  }

  assert {
    condition     = jsondecode(data.aws_secretsmanager_secret_version.root_password.secret_string).username == run.snapshot.master_username
    error_message = "The managed secret of a restored cluster should hold the snapshot's master username"
  }
}
