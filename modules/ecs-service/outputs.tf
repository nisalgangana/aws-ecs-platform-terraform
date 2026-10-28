output "execution_role_arn" {
  description = "ECS task execution role"
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "Role the app runs as"
  value       = aws_iam_role.task.arn
}

output "log_group_name" {
  description = "CloudWatch log group"
  value       = aws_cloudwatch_log_group.this.name
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "Current task definition revision"
  value       = aws_ecs_task_definition.this.arn
}

output "task_role_name" {
  description = "For extra inline policies (e.g. the uploads bucket)"
  value       = aws_iam_role.task.name
}
