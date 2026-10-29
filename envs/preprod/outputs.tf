# ---------------------------------------------------------------
# Network
# ---------------------------------------------------------------
output "vpc_id" {
  description = "ID of the preprod VPC"
  value       = module.network.vpc_id
}

output "private_app_subnet_ids" {
  description = "Private-app subnet IDs (ECS tasks, ALB)"
  value       = module.network.private_app_subnet_ids
}

output "nat_public_ips" {
  description = "Elastic IPs of the NAT gateways: give these to the SMS and payment sandboxes for allow-listing"
  value       = module.network.nat_public_ips
}

# ---------------------------------------------------------------
# Database
# ---------------------------------------------------------------
output "db_address" {
  description = "RDS endpoint"
  value       = module.database.db_address
}

output "db_master_secret_arn" {
  description = "Secret holding the RDS master password"
  value       = module.database.db_master_secret_arn
}

output "db_ops_task_definition_arn" {
  description = "psql one-off task (master user)"
  value       = module.db_ops.task_definition_arn
}

# ---------------------------------------------------------------
# DNS: add these in the example.com zone (management account)
# ---------------------------------------------------------------
output "acm_validation_records" {
  description = "CNAMEs to add before setting certificates_validated = true"
  value = distinct(concat(
    module.cert_cloudfront.validation_records,
    module.cert_alb.validation_records,
    module.cert_alb_admin.validation_records,
  ))
}

output "api_cdn_domain_name" {
  description = "ALIAS target for the API hostname (add in the management example.com zone)"
  value       = module.api_cdn.domain_name
}

output "admin_cdn_domain_name" {
  description = "ALIAS target for the admin web hostname (add in the management example.com zone)"
  value       = module.admin_cdn.domain_name
}

# ---------------------------------------------------------------
# Bitbucket variables (copy into the repos / deployments named)
# ---------------------------------------------------------------
output "ecr_repository_urls" {
  description = "Image repositories by service"
  value = {
    api       = module.ecr.repository_url
    worker    = module.ecr_worker.repository_url
    scheduler = module.ecr_scheduler.repository_url
    admin-web = module.ecr_admin.repository_url
  }
}

output "ecr_push_role_arns" {
  description = "Repository variable ECR_PUSH_ROLE_ARN (preprod) in acme-core-backend / acme-admin-web"
  value       = module.ci_oidc.ecr_push_role_arns
}

output "ecs_deploy_role_arns" {
  description = "Deployment variable ECS_DEPLOY_ROLE_ARN in the preprod deployment of acme-core-backend / acme-admin-web"
  value       = module.ci_oidc.deploy_role_arns
}

output "terraform_plan_role_arn" {
  description = "Terraform repo: repository variable PREPROD_TF_PLAN_ROLE_ARN"
  value       = module.ci_oidc.terraform_plan_role_arn
}

output "terraform_apply_role_arn" {
  description = "Terraform repo: preprod deployment variable TF_APPLY_ROLE_ARN"
  value       = module.ci_oidc.terraform_apply_role_arn
}

# ---------------------------------------------------------------
# Workloads
# ---------------------------------------------------------------
output "uploads_bucket_name" {
  description = "Private bucket for presigned uploads"
  value       = module.uploads.bucket_name
}

output "waf_log_groups" {
  description = "WAF logs (us-east-1): read these before switching managed_rules_mode to block"
  value = {
    api       = module.waf_api.log_group_name
    admin-web = module.waf_admin.log_group_name
  }
}
