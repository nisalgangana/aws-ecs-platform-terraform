output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.this.name
}

output "db_parameter_group_name" {
  description = "DB parameter group name"
  value       = aws_db_parameter_group.this.name
}

output "db_address" {
  description = "RDS endpoint hostname"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "RDS port"
  value       = aws_db_instance.this.port
}

output "db_master_secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed master password"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
