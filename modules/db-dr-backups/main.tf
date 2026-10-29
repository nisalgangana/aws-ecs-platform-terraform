# ---------------------------------------------------------------
# Cross-Region automated backups for RDS (prod only).
# RDS continuously copies snapshots AND transaction logs to the DR
# Region, so a point-in-time restore there loses ~5 minutes at most
# (a nightly snapshot copy would lose up to 24 hours).
#
# Everything here is created IN THE DR REGION: call the module with
# providers = { aws = aws.dr }.
# ---------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# A KMS key in the DR Region: the primary Region's key cannot encrypt here
resource "aws_kms_key" "dr" {
  description             = "${var.name_prefix} DR key: replicated RDS backups in ${data.aws_region.current.region}"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-db-dr-kms"
  }
}

resource "aws_kms_alias" "dr" {
  name          = "alias/${var.name_prefix}-db-dr"
  target_key_id = aws_kms_key.dr.key_id
}

resource "aws_db_instance_automated_backups_replication" "this" {
  source_db_instance_arn = var.source_db_instance_arn
  kms_key_id             = aws_kms_key.dr.arn
  retention_period       = var.retention_days
}
