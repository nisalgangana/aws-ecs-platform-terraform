output "alerts_topic_arn" {
  description = "SNS topic every alarm publishes to (reuse for future alarms)"
  value       = aws_sns_topic.alerts.arn
}
