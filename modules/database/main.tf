# ---------------------------------------------------------------
# Where RDS may live: private-data subnets only (no internet route)
# ---------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-db-subnets"
  description = "Private-data subnets for RDS"
  subnet_ids  = var.subnet_ids

  tags = {
    Name = "${var.name_prefix}-db-subnets"
  }
}

# ---------------------------------------------------------------
# PostgreSQL settings (family follows engine_version)
# ---------------------------------------------------------------
resource "aws_db_parameter_group" "this" {
  name        = "${var.name_prefix}-pg${var.engine_version}"
  family      = "postgres${var.engine_version}"
  description = "ACME PostgreSQL ${var.engine_version} settings"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = {
    Name = "${var.name_prefix}-pg${var.engine_version}"
  }

  # The DB still uses the old group, so create the new one first, delete the old one last.
  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------
# RDS PostgreSQL
# Password: created, stored and rotated by RDS in Secrets Manager.
# ---------------------------------------------------------------
resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-db"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name                       = var.db_name
  username                      = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [var.db_sg_id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  iam_database_authentication_enabled = true

  backup_retention_period = var.backup_retention_days
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = true
  apply_immediately           = var.apply_immediately

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name_prefix}-db-final"

  tags = {
    Name = "${var.name_prefix}-db"
  }
}
