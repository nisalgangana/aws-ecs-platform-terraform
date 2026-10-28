output "bucket_name" {
  description = "Bucket the pipeline syncs the static export into"
  value       = aws_s3_bucket.site.id
}

output "bucket_arn" {
  description = "Bucket ARN (for the CI deploy role policy)"
  value       = aws_s3_bucket.site.arn
}

output "distribution_id" {
  description = "For cache invalidations from the pipeline"
  value       = aws_cloudfront_distribution.site.id
}

output "distribution_arn" {
  description = "For the CI deploy role policy"
  value       = aws_cloudfront_distribution.site.arn
}

output "distribution_domain_name" {
  description = "d123.cloudfront.net; ALIAS target in Route 53"
  value       = aws_cloudfront_distribution.site.domain_name
}

output "hosted_zone_id" {
  description = "CloudFront's fixed zone ID for ALIAS records"
  value       = aws_cloudfront_distribution.site.hosted_zone_id
}
