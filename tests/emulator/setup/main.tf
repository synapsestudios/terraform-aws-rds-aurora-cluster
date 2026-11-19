# Inputs the module needs, created inside AWS Emulator.

terraform {
  required_version = ">= 1.7"

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
  description = "ID of the VPC the test cluster runs in."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the test VPC."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Availability zones the test subnets span."
  value       = local.availability_zones
}

output "subnet_ids" {
  description = "IDs of the test subnets, one per availability zone."
  value       = [for az in local.availability_zones : aws_subnet.this[az].id]
}

output "db_cluster_parameter_group_name" {
  description = "Name of the cluster parameter group the test cluster uses."
  value       = aws_rds_cluster_parameter_group.this.name
}

output "client_security_group_id" {
  description = "ID of the security group that stands in for an application client in the ingress test."
  value       = aws_security_group.client.id
}
