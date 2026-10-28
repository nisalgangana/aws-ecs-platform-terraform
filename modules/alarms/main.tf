locals {
  actions   = [aws_sns_topic.alerts.arn]
  namespace = "Acme" # custom metrics from log filters
}

# ---------------------------------------------------------------
# Where alarms go. No KMS: CloudWatch cannot publish to a topic encrypted
# with the AWS managed SNS key, and alerts carry no secrets.
# ---------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ---------------------------------------------------------------
# ALB: errors from the app, and from the ALB itself (no healthy target)
# ---------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name        = "${var.name_prefix}-alb-target-5xx"
  alarm_description = "Apps behind the ALB returned 5xx responses"
  namespace         = "AWS/ApplicationELB"
  metric_name       = "HTTPCode_Target_5XX_Count"
  dimensions        = { LoadBalancer = var.alb_arn_suffix }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.http_5xx_threshold
  treat_missing_data  = "notBreaching" # no traffic at night

  alarm_actions = local.actions
  ok_actions    = local.actions
}

resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name        = "${var.name_prefix}-alb-elb-5xx"
  alarm_description = "The ALB itself returned 5xx (no healthy target, timeouts)"
  namespace         = "AWS/ApplicationELB"
  metric_name       = "HTTPCode_ELB_5XX_Count"
  dimensions        = { LoadBalancer = var.alb_arn_suffix }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.http_5xx_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = local.actions
  ok_actions    = local.actions
}

# Unhealthy (not "healthy < 1"): the scheduler runs 0 tasks at night,
# which must not raise an alarm every evening
resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  for_each = var.target_groups

  alarm_name        = "${var.name_prefix}-${each.key}-unhealthy-targets"
  alarm_description = "${each.key}: targets failing the ALB health check for 3 minutes"
  namespace         = "AWS/ApplicationELB"
  metric_name       = "UnHealthyHostCount"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = each.value
  }

  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = local.actions
  ok_actions    = local.actions
}

# ---------------------------------------------------------------
# RDS
# ---------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name        = "${var.name_prefix}-db-cpu"
  alarm_description = "RDS CPU above ${var.db_cpu_percent}% for 15 minutes"
  namespace         = "AWS/RDS"
  metric_name       = "CPUUtilization"
  dimensions        = { DBInstanceIdentifier = var.db_instance_identifier }

  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.db_cpu_percent
  treat_missing_data  = "notBreaching" # stopped at night

  alarm_actions = local.actions
  ok_actions    = local.actions
}

resource "aws_cloudwatch_metric_alarm" "db_storage" {
  alarm_name        = "${var.name_prefix}-db-free-storage"
  alarm_description = "RDS free storage below ${var.db_free_storage_gib} GiB"
  namespace         = "AWS/RDS"
  metric_name       = "FreeStorageSpace" # bytes
  dimensions        = { DBInstanceIdentifier = var.db_instance_identifier }

  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = var.db_free_storage_gib * 1024 * 1024 * 1024
  treat_missing_data  = "notBreaching"

  alarm_actions = local.actions
  ok_actions    = local.actions
}

# ---------------------------------------------------------------
# App errors from the JSON logs (catches worker failures that never reach the ALB)
# ---------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "errors" {
  for_each = var.error_log_groups

  name           = "${var.name_prefix}-${each.key}-errors"
  log_group_name = each.value
  pattern        = "{ $.level = \"ERROR\" }"

  metric_transformation {
    namespace = local.namespace
    name      = "${var.name_prefix}-${each.key}-error-logs"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "error_logs" {
  for_each = var.error_log_groups

  alarm_name        = "${var.name_prefix}-${each.key}-error-logs"
  alarm_description = "${each.key}: ${var.error_log_threshold}+ ERROR log lines in 5 minutes"
  namespace         = local.namespace
  metric_name       = aws_cloudwatch_log_metric_filter.errors[each.key].metric_transformation[0].name

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.error_log_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = local.actions
  ok_actions    = local.actions
}
