output "resource_id" {
  description = "service/<cluster>/<service>"
  value       = aws_appautoscaling_target.this.resource_id
}

output "policy_arns" {
  description = "Scaling policy ARNs by kind"
  value = {
    for k, v in {
      cpu      = aws_appautoscaling_policy.cpu
      memory   = aws_appautoscaling_policy.memory
      requests = aws_appautoscaling_policy.requests
    } : k => one(v[*].arn) if length(v) > 0
  }
}
