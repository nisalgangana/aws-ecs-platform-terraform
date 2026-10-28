output "task_definition_arn" {
  description = "Run with aws ecs run-task and a command override"
  value       = aws_ecs_task_definition.this.arn
}

output "log_group_name" {
  description = "Where psql output goes"
  value       = aws_cloudwatch_log_group.this.name
}
