data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  service_arns = [
    for name in keys(var.services) :
    "arn:aws:ecs:${local.region}:${local.account_id}:service/${var.cluster_name}/${name}"
  ]
  db_arn = "arn:aws:rds:${local.region}:${local.account_id}:db:${var.db_instance_identifier}"
}

resource "aws_scheduler_schedule_group" "this" {
  name = "${var.name_prefix}-office-hours"
}

# ---------------------------------------------------------------
# Role the scheduler uses: only these services and this database
# ---------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.name_prefix}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    sid       = "ScaleServices"
    actions   = ["ecs:UpdateService"]
    resources = local.service_arns
  }

  statement {
    sid       = "StartStopDatabase"
    actions   = ["rds:StartDBInstance", "rds:StopDBInstance"]
    resources = [local.db_arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "start-stop"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}

# ---------------------------------------------------------------
# Database: start before the services, stop after them
# ---------------------------------------------------------------
resource "aws_scheduler_schedule" "db_start" {
  name                         = "${var.name_prefix}-db-start"
  group_name                   = aws_scheduler_schedule_group.this.name
  schedule_expression          = var.db_start_cron
  schedule_expression_timezone = var.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:startDBInstance"
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ DbInstanceIdentifier = var.db_instance_identifier })
  }
}

resource "aws_scheduler_schedule" "db_stop" {
  name                         = "${var.name_prefix}-db-stop"
  group_name                   = aws_scheduler_schedule_group.this.name
  schedule_expression          = var.db_stop_cron
  schedule_expression_timezone = var.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:stopDBInstance"
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ DbInstanceIdentifier = var.db_instance_identifier })
  }
}

# ---------------------------------------------------------------
# ECS services: one start and one stop schedule per service
# ---------------------------------------------------------------
resource "aws_scheduler_schedule" "service_start" {
  for_each = var.services

  name                         = "${each.key}-start"
  group_name                   = aws_scheduler_schedule_group.this.name
  schedule_expression          = var.services_start_cron
  schedule_expression_timezone = var.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
    role_arn = aws_iam_role.scheduler.arn
    input = jsonencode({
      Cluster      = var.cluster_name
      Service      = each.key
      DesiredCount = each.value
    })
  }
}

resource "aws_scheduler_schedule" "service_stop" {
  for_each = var.services

  name                         = "${each.key}-stop"
  group_name                   = aws_scheduler_schedule_group.this.name
  schedule_expression          = var.services_stop_cron
  schedule_expression_timezone = var.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
    role_arn = aws_iam_role.scheduler.arn
    input = jsonencode({
      Cluster      = var.cluster_name
      Service      = each.key
      DesiredCount = 0
    })
  }
}
