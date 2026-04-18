# terraform-aws-rds-aurora-cluster

## Upgrading from < v3.1.0

v3.1.0 migrates the Postgres SG rules from the legacy `aws_security_group_rule` to the current-best-practice `aws_vpc_security_group_{ingress,egress}_rule` resources. To upgrade without a connectivity gap, look up the existing rule IDs and pass them once via `legacy_rule_ids`:

```sh
aws ec2 describe-security-group-rules \
  --filters Name=group-id,Values=<output.security_group_id> \
  --query 'SecurityGroupRules[?FromPort==`5432`].[SecurityGroupRuleId,IsEgress]' \
  --output text
```

Then for one apply:

```hcl
module "aurora" {
  source = "..."
  # ...

  legacy_rule_ids = {
    ingress = "sgr-0abc..."  # IsEgress = false
    egress  = "sgr-0def..."  # IsEgress = true
  }
}
```

Terraform adopts the existing rules into the new resource addresses — zero AWS-side changes, zero connectivity gap. Remove the `legacy_rule_ids` argument on the next apply.

Fresh installs ignore this argument entirely.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_rds_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster) | resource |
| [aws_rds_cluster_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.postgres](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.postgres](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_iam_policy_document.rds_monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_secretsmanager_secret_version.root_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/secretsmanager_secret_version) | data source |
| [aws_vpc.database_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_security_groups"></a> [additional\_security\_groups](#input\_additional\_security\_groups) | Any additional security groups the cluster should be added to | `list(string)` | `[]` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | Availability zones for the database | `list(string)` | n/a | yes |
| <a name="input_database_name"></a> [database\_name](#input\_database\_name) | Name of the default database to create | `string` | `"main"` | no |
| <a name="input_database_subnets"></a> [database\_subnets](#input\_database\_subnets) | Subnets for the database | `list(string)` | n/a | yes |
| <a name="input_db_cluster_parameter_group_name"></a> [db\_cluster\_parameter\_group\_name](#input\_db\_cluster\_parameter\_group\_name) | parameter group | `string` | n/a | yes |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Enable deletion protection. DO NOT DISABLE IN PRODUCTION, THIS IS ONLY FOR TESTING. | `bool` | `true` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | The engine version to use | `string` | `"14"` | no |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | Instance class | `string` | `"db.t4g.medium"` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | How many RDS instances to create | `number` | `1` | no |
| <a name="input_legacy_rule_ids"></a> [legacy\_rule\_ids](#input\_legacy\_rule\_ids) | One-time zero-gap migration helper for upgrading from pre-v3.1.0 releases<br/>that managed the Postgres SG rules via `aws_security_group_rule`. Populate<br/>with the AWS-assigned rule IDs (format: sgr-xxxxxxxxxxxxx) of the existing<br/>ingress and egress rules to have Terraform adopt them as the new<br/>`aws_vpc_security_group_{ingress,egress}_rule` resources instead of<br/>destroying and recreating them.<br/><br/>Find the IDs with:<br/><br/>    aws ec2 describe-security-group-rules \<br/>      --filters Name=group-id,Values=<module.aurora.security\_group\_id><br/><br/>Leave empty on fresh installs. Remove the argument on the apply *after*<br/>the migration succeeds. | <pre>object({<br/>    ingress = optional(string)<br/>    egress  = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Determines naming convention of assets. Generally follows DNS naming convention. Service name or abbreviation. | `string` | n/a | yes |
| <a name="input_snapshot_identifier"></a> [snapshot\_identifier](#input\_snapshot\_identifier) | Identifier of a DB cluster snapshot to restore from. When set, database\_name and master\_username are ignored (the snapshot's values are used). | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A mapping of tags to assign to the AWS resources. | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The ID of the vpc the database belongs to | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_database_name"></a> [database\_name](#output\_database\_name) | The name of the default database. Null when the cluster was restored from a snapshot — the restored databases exist at the Postgres layer and are not exposed via the RDS API. |
| <a name="output_db_cluster_id"></a> [db\_cluster\_id](#output\_db\_cluster\_id) | The ID of the RDS cluster |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | The writer endpoint of the RDS cluster |
| <a name="output_master_user_secret_arn"></a> [master\_user\_secret\_arn](#output\_master\_user\_secret\_arn) | The ARN of the AWS-managed secret containing the master user credentials. Rotates automatically; prefer reading this over caching a derived connection string.<br/><br/>Note: these are master/root credentials and are not intended for application access. Applications should connect using a dedicated, least-privilege database user created at the Postgres layer. The master credentials are reserved for real-user/operator interaction (DBA operations, break-glass access, initial provisioning of app users). |
| <a name="output_master_username"></a> [master\_username](#output\_master\_username) | The master username for the RDS cluster |
| <a name="output_port"></a> [port](#output\_port) | The port the RDS cluster accepts connections on |
| <a name="output_reader_endpoint"></a> [reader\_endpoint](#output\_reader\_endpoint) | The read-only endpoint of the RDS cluster |
| <a name="output_root_credentials"></a> [root\_credentials](#output\_root\_credentials) | A map containing the username and password for the root user of the RDS cluster. Caution: This output will display the password in plain text. |
| <a name="output_root_password_id"></a> [root\_password\_id](#output\_root\_password\_id) | The ID of the secret that stores the root password for the RDS cluster |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | The ID of the EC2 security group that controls access to the RDS cluster |
<!-- END_TF_DOCS -->