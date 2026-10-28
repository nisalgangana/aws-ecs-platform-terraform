output "alb_sg_id" {
  description = "Security group ID for the internal ALB"
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.app.id
}

output "db_sg_id" {
  description = "Security group ID for RDS"
  value       = aws_security_group.db.id
}

output "kms_key_arn" {
  description = "ARN of the environment KMS key"
  value       = aws_kms_key.this.arn
}

output "kms_alias_name" {
  description = "Alias of the environment KMS key"
  value       = aws_kms_alias.this.name
}

output "app_secret_arn" {
  description = "ARN of the app integrations secret (values set outside Terraform)"
  value       = aws_secretsmanager_secret.app.arn
}

output "admin_web_sg_id" {
  description = "Security group ID for admin web tasks"
  value       = aws_security_group.admin_web.id
}

output "admin_web_secret_arn" {
  description = "ARN of the admin web secret (SESSION_SECRET)"
  value       = aws_secretsmanager_secret.admin_web.arn
}
