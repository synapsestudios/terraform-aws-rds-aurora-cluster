output "db_cluster_id" {
  description = "The ID of the RDS cluster"
  value       = aws_rds_cluster.this.cluster_identifier
}

output "security_group_id" {
  description = "The ID of the EC2 security group that controls access to the RDS cluster"
  value       = aws_security_group.this.id
}

output "root_password_secret_id" {
  description = "The ID of the secret that stores the root password for the RDS cluster"
  value       = data.aws_secretsmanager_secret_version.root_password.secret_id
}

output "connection_string_arn" {
  description = <<EOT
The ARN of the secret that stores the connection string for the RDS cluster.
The secret stored inside is formatted as: postgresql://<username>:<password>@<endpoint>:<port>/<database>
EOT
  value       = aws_secretsmanager_secret.connection_string.arn
}
