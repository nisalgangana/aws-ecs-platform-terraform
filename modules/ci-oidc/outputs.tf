output "oidc_provider_arn" {
  description = "Bitbucket OIDC provider (reuse for the Terraform deploy role in Phase 10)"
  value       = aws_iam_openid_connect_provider.bitbucket.arn
}

output "ecr_push_role_arns" {
  description = "Repo key => role ARN; put it in that repo as Bitbucket variable AWS_ROLE_ARN"
  value       = { for k, r in aws_iam_role.ecr_push : k => r.arn }
}

output "deploy_role_arns" {
  description = "Repo key => deploy role ARN; Bitbucket deployment variable AWS_ROLE_ARN (dev)"
  value       = { for k, r in aws_iam_role.ecs_deploy : k => r.arn }
}

output "terraform_plan_role_arn" {
  description = "Terraform repo: repository variable TF_PLAN_ROLE_ARN (null if terraform_ci is null)"
  value       = one(aws_iam_role.terraform_plan[*].arn)
}

output "terraform_apply_role_arn" {
  description = "Terraform repo: dev deployment variable TF_APPLY_ROLE_ARN"
  value       = one(aws_iam_role.terraform_apply[*].arn)
}

output "site_deploy_role_arns" {
  description = "Repo key => static-site deploy role ARN; Bitbucket deployment variable SITE_DEPLOY_ROLE_ARN (dev)"
  value       = { for k, r in aws_iam_role.site_deploy : k => r.arn }
}
