output "db_cluster_id" {
  value = aws_rds_cluster.this.cluster_identifier
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "root_password_secret_id" {
  value = data.aws_secretsmanager_secret_version.root_password.secret_id
}

output "connection_string_arn" {
  value = aws_secretsmanager_secret.connection_string.arn
}
