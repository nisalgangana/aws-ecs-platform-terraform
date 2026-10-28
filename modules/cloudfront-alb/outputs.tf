output "distribution_id" {
  description = "CloudFront distribution ID (cache invalidations, logs)"
  value       = aws_cloudfront_distribution.this.id
}

output "domain_name" {
  description = "dxxxx.cloudfront.net, the ALIAS target for the API hostname"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "hosted_zone_id" {
  description = "CloudFront's Route 53 zone ID for ALIAS records (always Z2FDTNDATAQYW2)"
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}

output "vpc_origin_id" {
  description = "VPC origin used by this distribution (pass to other distributions of the same ALB)"
  value       = local.vpc_origin_id
}
