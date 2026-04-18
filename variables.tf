variable "name" {
  type        = string
  description = "Determines naming convention of assets. Generally follows DNS naming convention. Service name or abbreviation."
}

variable "database_name" {
  type        = string
  description = "Name of the default database to create"
  default     = "main"
}

variable "engine_version" {
  type        = string
  description = "The engine version to use"
  default     = "14"
}

variable "vpc_id" {
  type        = string
  description = "The ID of the vpc the database belongs to"
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones for the database"
}

variable "database_subnets" {
  type        = list(string)
  description = "Subnets for the database"
}

variable "additional_security_groups" {
  type        = list(string)
  default     = []
  description = "Any additional security groups the cluster should be added to"
}

variable "tags" {
  type        = map(string)
  description = "A mapping of tags to assign to the AWS resources."
  default     = {}
}

variable "instance_count" {
  type        = number
  description = "How many RDS instances to create"
  default     = 1
}

variable "db_cluster_parameter_group_name" {
  type        = string
  description = "parameter group"
}

variable "instance_class" {
  type        = string
  description = "Instance class"
  default     = "db.t4g.medium"
}

variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection. DO NOT DISABLE IN PRODUCTION, THIS IS ONLY FOR TESTING."
  default     = true
}

variable "snapshot_identifier" {
  type        = string
  default     = null
  description = "Identifier of a DB cluster snapshot to restore from. When set, database_name and master_username are ignored (the snapshot's values are used)."
}

variable "legacy_rule_ids" {
  type = object({
    ingress = optional(string)
    egress  = optional(string)
  })
  default     = {}
  description = <<-EOT
    One-time zero-gap migration helper for upgrading from pre-v3.1.0 releases
    that managed the Postgres SG rules via `aws_security_group_rule`. Populate
    with the AWS-assigned rule IDs (format: sgr-xxxxxxxxxxxxx) of the existing
    ingress and egress rules to have Terraform adopt them as the new
    `aws_vpc_security_group_{ingress,egress}_rule` resources instead of
    destroying and recreating them.

    Find the IDs with:

        aws ec2 describe-security-group-rules \
          --filters Name=group-id,Values=<module.aurora.security_group_id>

    Leave empty on fresh installs. Remove the argument on the apply *after*
    the migration succeeds.
  EOT
}