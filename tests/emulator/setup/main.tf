# Inputs the module needs, created inside AWS Emulator.

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

resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "this" {
  for_each = { for index, az in local.availability_zones : az => index }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, each.value)
}

resource "aws_rds_cluster_parameter_group" "this" {
  name_prefix = "emulator-test"
  family      = "aurora-postgresql14"
}

# Stands in for an application's security group, for the ingress test.
resource "aws_security_group" "client" {
  name_prefix = "emulator-test-client"
  description = "Client allowed to reach the test cluster"
  vpc_id      = aws_vpc.this.id
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "availability_zones" {
  value = local.availability_zones
}

output "subnet_ids" {
  value = [for az in local.availability_zones : aws_subnet.this[az].id]
}

output "db_cluster_parameter_group_name" {
  value = aws_rds_cluster_parameter_group.this.name
}

output "client_security_group_id" {
  value = aws_security_group.client.id
}
