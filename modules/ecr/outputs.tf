output "repository_url" {
  description = "URL for docker push/pull"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the repository"
  value       = aws_ecr_repository.this.arn
}
