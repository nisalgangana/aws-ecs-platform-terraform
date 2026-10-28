output "schedule_group_name" {
  description = "Disable/enable all schedules together from this group"
  value       = aws_scheduler_schedule_group.this.name
}
