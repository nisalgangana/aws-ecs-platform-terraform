output "web_acl_arn" {
  description = "Pass to cloudfront-alb as web_acl_arn"
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_id" {
  description = "Web ACL ID"
  value       = aws_wafv2_web_acl.this.id
}

output "log_group_name" {
  description = "WAF log group (us-east-1); query it with Logs Insights"
  value       = aws_cloudwatch_log_group.waf.name
}
