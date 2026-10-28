data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}


# ---------------------------------------------------------------
# Lock the VPC's default security group: no rules at all.
# Anything accidentally launched without an SG gets no traffic.
# ---------------------------------------------------------------
resource "aws_default_security_group" "this" {
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-default-sg-do-not-use"
  }
}

# ---------------------------------------------------------------
# Security groups (rules are separate resources below)
# ---------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Internal ALB - HTTPS from CloudFront VPC origin"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-alb-sg"
  }
}

resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app-sg"
  description = "ECS tasks - traffic from the ALB only"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-app-sg"
  }
}

resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "RDS PostgreSQL - traffic from the app only"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-db-sg"
  }
}

resource "aws_security_group" "admin_web" {
  name        = "${var.name_prefix}-admin-web-sg"
  description = "Admin web (Next.js) tasks - traffic from the ALB only, no database access"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-admin-web-sg"
  }
}


# ---------------------------------------------------------------
# CloudFront -> ALB (VPC origin)
# New environment: prefix list first (the VPC origin SG does not exist yet).
# Then: allow the VPC origin SG, test, and switch the prefix list off.
# ---------------------------------------------------------------
data "aws_ec2_managed_prefix_list" "cloudfront" {
  count = var.allow_cloudfront_prefix_list ? 1 : 0

  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  count = var.allow_cloudfront_prefix_list ? 1 : 0

  security_group_id = aws_security_group.alb.id
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront[0].id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from CloudFront (any distribution)"
}

# The prefix-list rule became optional (count): keep the existing rule
moved {
  from = aws_vpc_security_group_ingress_rule.alb_from_cloudfront
  to   = aws_vpc_security_group_ingress_rule.alb_from_cloudfront[0]
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_vpc_origin" {
  count = var.cloudfront_vpc_origin_sg_id == null ? 0 : 1

  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = var.cloudfront_vpc_origin_sg_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from this account s CloudFront VPC origins only"
}



# ---------------------------------------------------------------
# ALB -> app
# ---------------------------------------------------------------
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  description                  = "To ECS tasks"
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  description                  = "From the ALB"
}

# ---------------------------------------------------------------
# ALB -> admin web (Next.js listens on the same port as the API)
# ---------------------------------------------------------------
resource "aws_vpc_security_group_egress_rule" "alb_to_admin_web" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.admin_web.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  description                  = "To admin web tasks"
}

resource "aws_vpc_security_group_ingress_rule" "admin_web_from_alb" {
  security_group_id            = aws_security_group.admin_web.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  description                  = "From the ALB"
}

# Admin web -> anywhere (ECR pull, Secrets Manager, the API via CloudFront)
resource "aws_vpc_security_group_egress_rule" "admin_web_all_out" {
  security_group_id = aws_security_group.admin_web.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}


# ---------------------------------------------------------------
# App -> anywhere (ECR pulls, Secrets Manager, SMS, the payment gateway, RDS)
# ---------------------------------------------------------------
resource "aws_vpc_security_group_egress_rule" "app_all_out" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# ---------------------------------------------------------------
# App -> DB (no egress rule on the DB SG at all)
# ---------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  description                  = "PostgreSQL from the app"
}

# ---------------------------------------------------------------
# KMS: one customer managed key per environment
# (RDS, Secrets Manager, CloudWatch Logs, S3 uploads)
# ---------------------------------------------------------------
resource "aws_kms_key" "this" {
  description             = "${var.name_prefix} encryption key (RDS, Secrets Manager, logs, S3)"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # REQUIRED: without this nobody can manage the key again (lockout)
        Sid       = "EnableRootAccountPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${local.region}:${local.account_id}:log-group:*"
          }
        }
      }
    ]
  })


  tags = {
    Name = "${var.name_prefix}-kms"
  }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.this.key_id
}

# ---------------------------------------------------------------
# Secrets Manager: container only. Values are set outside Terraform
# so they never land in the state file.
# ---------------------------------------------------------------
resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.name_prefix}/app/integrations"
  description             = "Go app runtime secrets (DB, Redis, auth keys, Stripe). Values set outside Terraform (write-only)."
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = var.secret_recovery_window_days

  tags = {
    Name = "${var.name_prefix}-app-integrations"
  }
}

# Write-only: the value goes to AWS but is never saved in plan or state.
resource "aws_secretsmanager_secret_version" "app" {
  count = var.manage_app_secret_value ? 1 : 0

  secret_id                = aws_secretsmanager_secret.app.id
  secret_string_wo         = jsonencode(var.app_secret_values)
  secret_string_wo_version = var.app_secret_version
}

# ---------------------------------------------------------------
# Admin web secret: only SESSION_SECRET (no API/DB/Stripe secrets)
# ---------------------------------------------------------------
resource "aws_secretsmanager_secret" "admin_web" {
  name                    = "${var.name_prefix}/admin-web/app"
  description             = "Admin web (Next.js BFF) runtime secrets. Values set write-only."
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = var.secret_recovery_window_days

  tags = {
    Name = "${var.name_prefix}-admin-web-app"
  }
}

resource "aws_secretsmanager_secret_version" "admin_web" {
  count = var.manage_admin_web_secret_value ? 1 : 0

  secret_id                = aws_secretsmanager_secret.admin_web.id
  secret_string_wo         = jsonencode(var.admin_web_secret_values)
  secret_string_wo_version = var.admin_web_secret_version
}
