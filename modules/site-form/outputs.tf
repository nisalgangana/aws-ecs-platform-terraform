output "function_name" {
  description = "For the CloudFront invoke permission"
  value       = aws_lambda_function.this.function_name
}

output "function_url_domain" {
  description = "CloudFront origin domain (xxxx.lambda-url.<region>.on.aws)"
  value       = trimsuffix(trimprefix(aws_lambda_function_url.this.function_url, "https://"), "/")
}

output "topic_arn" {
  description = "Enquiries SNS topic"
  value       = aws_sns_topic.enquiries.arn
}
