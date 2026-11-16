# A caller that creates its client's security group in the same apply as the
# cluster. The group's ID is unknown at plan, so this only plans if the module
# keys its ingress rules on something the caller wrote.

resource "aws_security_group" "app" {
  name_prefix = "app"
  vpc_id      = "vpc-12345678"
}

module "aurora" {
  source = "../../../.."

  name                            = "test-cluster"
  vpc_id                          = "vpc-12345678"
  availability_zones              = ["us-west-2a", "us-west-2b"]
  database_subnets                = ["subnet-11111111", "subnet-22222222"]
  db_cluster_parameter_group_name = "test-pg"

  allowed_security_group_ids = {
    app = aws_security_group.app.id
  }
}
