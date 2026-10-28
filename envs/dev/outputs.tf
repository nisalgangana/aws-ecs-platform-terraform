output "vpc_id" {
  description = "ID of the dev VPC"
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.network.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private-app subnet IDs"
  value       = module.network.private_app_subnet_ids
}

output "private_data_subnet_ids" {
  description = "Private-data subnet IDs"
  value       = module.network.private_data_subnet_ids
}

output "db_address" {
  description = "RDS endpoint"
  value       = module.database.db_address
}

output "db_master_secret_arn" {
  description = "Secret holding the RDS master password"
  value       = module.database.db_master_secret_arn
}

output "ecr_repository_url" {
  description = "Push the app image here"
  value       = module.ecr.repository_url
}

output "backend_ecr_push_role_arn" {
  description = "Bitbucket variable AWS_ROLE_ARN in acme-core-backend"
  value       = module.ci_oidc.ecr_push_role_arns["backend"]
}

output "admin_web_ecr_push_role_arn" {
  description = "Bitbucket variable AWS_ROLE_ARN in acme-admin-web"
  value       = module.ci_oidc.ecr_push_role_arns["admin-web"]
}

output "admin_web_ecr_repository_url" {
  description = "Bitbucket variable IMAGE_NAME in acme-admin-web"
  value       = module.ecr_admin.repository_url
}

output "acm_validation_records" {
  description = "Add these CNAMEs in the example.com zone (management account)"
  value = distinct(concat(
    module.cert_cloudfront.validation_records,
    module.cert_alb.validation_records,
    module.cert_alb_admin.validation_records,
    module.cert_landing.validation_records,
  ))

}

output "app_task_definition_arn" {
  description = "Task definition used by the app service (and the one-off migrate task)"
  value       = module.app_service.task_definition_arn
}

output "api_cdn_domain_name" {
  description = "ALIAS target for api-dev.example.com (add in the management example.com zone)"
  value       = module.api_cdn.domain_name
}

output "admin_web_task_definition_arn" {
  description = "Admin web task definition (current revision)"
  value       = module.admin_web_service.task_definition_arn
}

output "admin_cdn_domain_name" {
  description = "ALIAS target for admin-dev.example.com (add in the management example.com zone)"
  value       = module.admin_cdn.domain_name
}

output "db_ops_task_definition_arn" {
  description = "psql one-off task (master user)"
  value       = module.db_ops.task_definition_arn
}

output "backend_deploy_role_arn" {
  description = "Bitbucket deployment variable AWS_ROLE_ARN (dev) in acme-core-backend"
  value       = module.ci_oidc.deploy_role_arns["backend"]
}

output "admin_web_deploy_role_arn" {
  description = "Bitbucket deployment variable AWS_ROLE_ARN (dev) in acme-admin-web"
  value       = module.ci_oidc.deploy_role_arns["admin-web"]
}

output "terraform_plan_role_arn" {
  description = "Terraform repo: repository variable TF_PLAN_ROLE_ARN"
  value       = module.ci_oidc.terraform_plan_role_arn
}

output "terraform_apply_role_arn" {
  description = "Terraform repo: dev deployment variable TF_APPLY_ROLE_ARN"
  value       = module.ci_oidc.terraform_apply_role_arn
}

output "landing_bucket_name" {
  description = "Landing site bucket (pipeline sync target)"
  value       = module.landing.bucket_name
}

output "landing_distribution_id" {
  description = "Landing site CloudFront distribution (pipeline invalidation)"
  value       = module.landing.distribution_id
}

output "landing_distribution_domain_name" {
  description = "Test URL before DNS: https://<this>/"
  value       = module.landing.distribution_domain_name
}

output "landing_deploy_role_arn" {
  description = "Landing repo: dev deployment variable SITE_DEPLOY_ROLE_ARN"
  value       = module.ci_oidc.site_deploy_role_arns["landing"]
}
