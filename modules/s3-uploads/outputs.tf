output "bucket_name" {
  description = "Give to the app as its uploads bucket env var"
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "Uploads bucket ARN"
  value       = aws_s3_bucket.this.arn
}
