# Inputs the module needs, looked up or created inside AWS Emulator.
#
# The tests use the emulator's default VPC because of aws/aws-emulator#46: in
# any other VPC the emulator refuses the call the AWS provider makes to remove
# a new security group's default egress rule, so aws_security_group fails.
# https://github.com/aws/aws-emulator/issues/46

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  availability_zones = ["us-east-1a", "us-east-1b"]
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet" "default" {
  for_each = toset(local.availability_zones)

  vpc_id            = data.aws_vpc.default.id
  availability_zone = each.value
  default_for_az    = true
}

resource "aws_rds_cluster_parameter_group" "this" {
  name_prefix = "emulator-test"
  family      = "aurora-postgresql14"
}

# Stands in for an application's security group, for the ingress test.
resource "aws_security_group" "client" {
  name_prefix = "emulator-test-client"
  description = "Client allowed to reach the test cluster"
  vpc_id      = data.aws_vpc.default.id
}

output "vpc_id" {
  value = data.aws_vpc.default.id
}

output "vpc_cidr_block" {
  value = data.aws_vpc.default.cidr_block
}

output "availability_zones" {
  value = local.availability_zones
}

output "subnet_ids" {
  value = [for az in local.availability_zones : data.aws_subnet.default[az].id]
}

output "db_cluster_parameter_group_name" {
  value = aws_rds_cluster_parameter_group.this.name
}

output "client_security_group_id" {
  value = aws_security_group.client.id
}
