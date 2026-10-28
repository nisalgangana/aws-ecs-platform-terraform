data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name = "${var.name_prefix}-db-ops"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

# ---------------------------------------------------------------
# Execution role: pull the image, write logs, read the master and app secrets
# ---------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.name}-exec-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "secrets" {
  statement {
    sid       = "ReadSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_master_secret_arn, var.app_secret_arn]
  }

  statement {
    sid       = "DecryptWithEnvKey"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "secrets" {
  name   = "read-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.secrets.json
}

# ---------------------------------------------------------------
# One-off psql task (no service). Run it with `aws ecs run-task` and a
# command override; psql reads PGHOST, PGUSER, PGPASSWORD... from the env.
# ---------------------------------------------------------------
resource "aws_ecs_task_definition" "this" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "db-ops"
      image     = "public.ecr.aws/docker/library/postgres:18-alpine"
      essential = true
      command   = ["psql", "-c", "SELECT current_user, version();"]

      environment = [
        { name = "PGHOST", value = var.db_address },
        { name = "PGPORT", value = "5432" },
        { name = "PGDATABASE", value = var.db_name },
        { name = "PGSSLMODE", value = "require" },
      ]

      secrets = [
        { name = "PGUSER", valueFrom = "${var.db_master_secret_arn}:username::" },
        { name = "PGPASSWORD", valueFrom = "${var.db_master_secret_arn}:password::" },
        { name = "APP_DB_PASSWORD", valueFrom = "${var.app_secret_arn}:APP_DB_PASSWORD::" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "db-ops"
        }
      }
    }
  ])

  tags = {
    Name = local.name
  }
}
