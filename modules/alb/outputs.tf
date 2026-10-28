output "alb_arn" {
  description = "ALB ARN (CloudFront VPC origin needs it)"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "Internal DNS name of the ALB"
  value       = aws_lb.this.dns_name
}

output "target_group_arn" {
  description = "Target group for the app service"
  value       = aws_lb_target_group.app.arn
}

output "listener_arn" {
  description = "HTTP listener"
  value       = aws_lb_listener.https.arn

}

output "host_target_group_arns" {
  description = "Target group per extra hostname, key => ARN"
  value       = { for k, tg in aws_lb_target_group.host : k => tg.arn }
}

output "alb_arn_suffix" {
  description = "For CloudWatch metrics (dimension LoadBalancer)"
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffixes" {
  description = "Target group key => ARN suffix, for CloudWatch metrics (dimension TargetGroup)"
  value = merge(
    { api = aws_lb_target_group.app.arn_suffix },
    { for k, tg in aws_lb_target_group.host : k => tg.arn_suffix },
  )
}
