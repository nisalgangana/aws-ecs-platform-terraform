# ---------------------------------------------------------------
# Application Auto Scaling for one ECS service.
# The ecs-service module ignores desired_count, so Terraform and the
# scaler never fight over it.
# ---------------------------------------------------------------
locals {
  resource_id = "service/${var.cluster_name}/${var.service_name}"
}

resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  resource_id        = local.resource_id
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity

  # Scheduled actions move min/max during the day; Terraform must not reset them on every apply
  lifecycle {
    ignore_changes = [min_capacity, max_capacity]
  }
}

# ---------------------------------------------------------------
# Target tracking: AWS adds tasks when the metric is above target and
# removes them (slowly) when it is below.
# ---------------------------------------------------------------
resource "aws_appautoscaling_policy" "cpu" {
  count = var.cpu_target_percent == null ? 0 : 1

  name               = "${var.service_name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_percent
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "memory" {
  count = var.memory_target_percent == null ? 0 : 1

  name               = "${var.service_name}-memory"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.memory_target_percent
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

# Requests per task: reacts before CPU does on an I/O-bound API
resource "aws_appautoscaling_policy" "requests" {
  count = var.requests_per_target == null ? 0 : 1

  name               = "${var.service_name}-requests"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.requests_per_target
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = var.alb_resource_label
    }
  }
}

# ---------------------------------------------------------------
# Scheduled floor/ceiling changes: the afternoon peak in prod,
# office hours in pre-prod (0/0 at night = service stopped)
# ---------------------------------------------------------------
resource "aws_appautoscaling_scheduled_action" "this" {
  for_each = var.scheduled_actions

  name               = "${var.service_name}-${each.key}"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  schedule           = each.value.schedule
  timezone           = var.timezone

  scalable_target_action {
    min_capacity = each.value.min_capacity
    max_capacity = each.value.max_capacity
  }
}
