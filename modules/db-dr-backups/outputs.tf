output "replication_arn" {
  description = "Automated backups replication ARN (DR Region)"
  value       = aws_db_instance_automated_backups_replication.this.id
}

output "kms_key_arn" {
  description = "KMS key the DR backups are encrypted with; a restore in the DR Region needs it"
  value       = aws_kms_key.dr.arn
}
