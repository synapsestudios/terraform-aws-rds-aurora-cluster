output "db_cluster_id" {
  description = "The ID of the RDS cluster"
  value       = aws_rds_cluster.this.cluster_identifier
}

output "security_group_id" {
  description = "The ID of the EC2 security group that controls access to the RDS cluster"
  value       = aws_security_group.this.id
}

output "endpoint" {
  description = "The writer endpoint of the RDS cluster"
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "The read-only endpoint of the RDS cluster"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "The port the RDS cluster accepts connections on"
  value       = aws_rds_cluster.this.port
}

output "database_name" {
  description = "The name of the default database. Null when the cluster was restored from a snapshot — the restored databases exist at the Postgres layer and are not exposed via the RDS API."
  value       = aws_rds_cluster.this.database_name
}

output "master_username" {
  description = "The master username for the RDS cluster"
  value       = aws_rds_cluster.this.master_username
}

output "master_user_secret_arn" {
  description = <<EOT
The ARN of the AWS-managed secret containing the master user credentials. Rotates automatically; prefer reading this over caching a derived connection string.

Note: these are master/root credentials and are not intended for application access. Applications should connect using a dedicated, least-privilege database user created at the Postgres layer. The master credentials are reserved for real-user/operator interaction (DBA operations, break-glass access, initial provisioning of app users).
EOT
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}

output "root_password_id" {
  description = "The ID of the secret that stores the root password for the RDS cluster"
  value       = data.aws_secretsmanager_secret_version.root_password.id
}

output "root_credentials" {
  description = "A map containing the username and password for the root user of the RDS cluster. Caution: This output will display the password in plain text."
  value = {
    username = aws_rds_cluster.this.master_username
    password = data.aws_secretsmanager_secret_version.root_password.secret_string
  }

  sensitive = true
}
