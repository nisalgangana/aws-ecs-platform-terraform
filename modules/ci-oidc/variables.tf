variable "name_prefix" {
  description = "Prefix for resource names, e.g. acme-dev"
  type        = string
}

variable "oidc_provider_url" {
  description = "Bitbucket workspace OIDC identity provider URL"
  type        = string
}

variable "oidc_audience" {
  description = "Bitbucket OIDC audience (ari:cloud:bitbucket::workspace/<uuid>)"
  type        = string
}

variable "push_roles" {
  description = "One ECR push role per repository: key => repo UUID (with braces) and the ECR repos it may push to"
  type = map(object({
    repo_uuid           = string
    ecr_repository_arns = list(string)
    description         = string
  }))
}

variable "deploy_roles" {
  description = "One ECS deploy role per repository, assumable only from that repo's deployment environment"
  type = map(object({
    repo_uuid        = string
    environment_uuid = string # Bitbucket deployment environment, e.g. dev
    description      = string
    cluster_arn      = string
    service_names    = list(string) # task definition family = service name
    pass_role_arns   = list(string) # execution + task roles of those services
  }))
  default = {}
}

variable "terraform_ci" {
  description = "Pipeline roles for the Terraform repo itself; null = none"
  type = object({
    repo_uuid        = string
    environment_uuid = string # deployment environment allowed to apply, e.g. dev
    state_bucket_arn = string
    state_key        = string # e.g. dev/terraform.tfstate
  })
  default = null
}

variable "site_deploy_roles" {
  description = "One static-site deploy role per repository: sync one bucket, invalidate one distribution"
  type = map(object({
    repo_uuid        = string
    environment_uuid = string # Bitbucket deployment environment, e.g. dev
    description      = string
    bucket_arn       = string
    distribution_arn = string
  }))
  default = {}
}
