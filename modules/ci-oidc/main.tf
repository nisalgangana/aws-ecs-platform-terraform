locals {
  # IAM condition keys use the issuer without "https://"
  oidc_issuer = replace(var.oidc_provider_url, "https://", "")
}

# One provider per account per URL; every Bitbucket role in this account uses it
resource "aws_iam_openid_connect_provider" "bitbucket" {
  url            = var.oidc_provider_url
  client_id_list = [var.oidc_audience]

  tags = {
    Name = "${var.name_prefix}-bitbucket-oidc"
  }
}

# ---------------------------------------------------------------
# One role per repository pipeline: push images to its own ECR repo, nothing else
# ---------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  for_each = var.push_roles

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.bitbucket.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = [var.oidc_audience]
    }

    # sub = "{repoUuid}:{stepUuid}" or "{repoUuid}:{environmentUuid}:{stepUuid}"

    condition {
      test     = "StringLike"
      variable = "${local.oidc_issuer}:sub"
      values   = ["${each.value.repo_uuid}*:*"]
    }
  }
}

resource "aws_iam_role" "ecr_push" {
  for_each = var.push_roles

  name               = "${var.name_prefix}-${each.key}-ecr-push"
  description        = each.value.description
  assume_role_policy = data.aws_iam_policy_document.assume[each.key].json
}

data "aws_iam_policy_document" "ecr_push" {
  for_each = var.push_roles

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource-level permissions
  }

  statement {
    sid = "PushToRepo"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]
    resources = each.value.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  for_each = var.push_roles

  name   = "ecr-push"
  role   = aws_iam_role.ecr_push[each.key].id
  policy = data.aws_iam_policy_document.ecr_push[each.key].json
}

# ---------------------------------------------------------------
# Refactor: the single backend role became the "backend" key of the map.
# Keeps the existing role (same ARN) instead of destroy + create.
# ---------------------------------------------------------------
moved {
  from = aws_iam_role.backend_ecr_push
  to   = aws_iam_role.ecr_push["backend"]
}

moved {
  from = aws_iam_role_policy.backend_ecr_push
  to   = aws_iam_role_policy.ecr_push["backend"]
}

# ---------------------------------------------------------------
# Deploy roles: separate from the push roles. Only steps running in the
# repo's deployment environment (e.g. "dev") can assume them.
# ---------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}

data "aws_iam_policy_document" "deploy_assume" {
  for_each = var.deploy_roles

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.bitbucket.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = [var.oidc_audience]
    }

    # sub = "{repoUuid}:{environmentUuid}:{stepUuid}" only for steps with a deployment
    condition {
      test     = "StringLike"
      variable = "${local.oidc_issuer}:sub"
      values   = ["${each.value.repo_uuid}:${each.value.environment_uuid}:*"]
    }

  }
}

resource "aws_iam_role" "ecs_deploy" {
  for_each = var.deploy_roles

  name               = "${var.name_prefix}-${each.key}-ecs-deploy"
  description        = each.value.description
  assume_role_policy = data.aws_iam_policy_document.deploy_assume[each.key].json
}

data "aws_iam_policy_document" "ecs_deploy" {
  for_each = var.deploy_roles

  statement {
    sid = "ReadOnly"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeServices",
      "ecs:DescribeTasks",
      "rds:DescribeDBInstances",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "RegisterRevision"
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = ["*"] # no resource-level permissions for this action
  }

  statement {
    sid     = "RunMigrations"
    actions = ["ecs:RunTask"]
    resources = [
      for s in each.value.service_names :
      "arn:aws:ecs:${local.region}:${local.account_id}:task-definition/${s}:*"
    ]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [each.value.cluster_arn]
    }
  }

  statement {
    sid     = "UpdateServices"
    actions = ["ecs:UpdateService"]
    resources = [
      for s in each.value.service_names :
      "arn:aws:ecs:${local.region}:${local.account_id}:service/${element(split("/", each.value.cluster_arn), 1)}/${s}"
    ]
  }

  statement {
    sid       = "PassServiceRoles"
    actions   = ["iam:PassRole"]
    resources = each.value.pass_role_arns

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "ecs_deploy" {
  for_each = var.deploy_roles

  name   = "ecs-deploy"
  role   = aws_iam_role.ecs_deploy[each.key].id
  policy = data.aws_iam_policy_document.ecs_deploy[each.key].json
}

# ---------------------------------------------------------------
# Terraform repo pipeline: a read-only plan role (any step, pull requests too)
# and an admin apply role (only the "dev" deployment step, i.e. after merge to main)
# ---------------------------------------------------------------
data "aws_iam_policy_document" "terraform_plan_assume" {
  count = var.terraform_ci == null ? 0 : 1

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.bitbucket.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = [var.oidc_audience]
    }

    # any step of the Terraform repo: "{repo}:{step}" or "{repo}:{env}:{step}"
    condition {
      test     = "StringLike"
      variable = "${local.oidc_issuer}:sub"
      values   = ["${var.terraform_ci.repo_uuid}:*"]
    }
  }
}

data "aws_iam_policy_document" "terraform_apply_assume" {
  count = var.terraform_ci == null ? 0 : 1

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.bitbucket.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = [var.oidc_audience]
    }

    # only steps running in the deployment environment
    condition {
      test     = "StringLike"
      variable = "${local.oidc_issuer}:sub"
      values   = ["${var.terraform_ci.repo_uuid}:${var.terraform_ci.environment_uuid}:*"]
    }
  }
}

resource "aws_iam_role" "terraform_plan" {
  count = var.terraform_ci == null ? 0 : 1

  name               = "${var.name_prefix}-terraform-plan"
  description        = "Bitbucket pipeline of the Terraform repo: plan (read-only)"
  assume_role_policy = data.aws_iam_policy_document.terraform_plan_assume[0].json
}

resource "aws_iam_role_policy_attachment" "terraform_plan_read_only" {
  count = var.terraform_ci == null ? 0 : 1

  role       = aws_iam_role.terraform_plan[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# plan takes the state lock: it writes and deletes the .tflock object
data "aws_iam_policy_document" "terraform_state_lock" {
  count = var.terraform_ci == null ? 0 : 1

  statement {
    sid       = "StateLockFile"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.terraform_ci.state_bucket_arn}/${var.terraform_ci.state_key}.tflock"]
  }
}

resource "aws_iam_role_policy" "terraform_plan_state_lock" {
  count = var.terraform_ci == null ? 0 : 1

  name   = "state-lock"
  role   = aws_iam_role.terraform_plan[0].id
  policy = data.aws_iam_policy_document.terraform_state_lock[0].json
}

resource "aws_iam_role" "terraform_apply" {
  count = var.terraform_ci == null ? 0 : 1

  name               = "${var.name_prefix}-terraform-apply"
  description        = "Bitbucket dev deployment of the Terraform repo: apply"
  assume_role_policy = data.aws_iam_policy_document.terraform_apply_assume[0].json
}

resource "aws_iam_role_policy_attachment" "terraform_apply_admin" {
  count = var.terraform_ci == null ? 0 : 1

  role       = aws_iam_role.terraform_apply[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ---------------------------------------------------------------
# Static site deploy roles: only from the repo's deployment environment.
# Sync one bucket and invalidate one distribution, nothing else.
# ---------------------------------------------------------------
data "aws_iam_policy_document" "site_deploy_assume" {
  for_each = var.site_deploy_roles

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.bitbucket.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = [var.oidc_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_issuer}:sub"
      values   = ["${each.value.repo_uuid}:${each.value.environment_uuid}:*"]
    }
  }
}

resource "aws_iam_role" "site_deploy" {
  for_each = var.site_deploy_roles

  name               = "${var.name_prefix}-${each.key}-site-deploy"
  description        = each.value.description
  assume_role_policy = data.aws_iam_policy_document.site_deploy_assume[each.key].json
}

data "aws_iam_policy_document" "site_deploy" {
  for_each = var.site_deploy_roles

  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"] # s3 sync compares before uploading
    resources = [each.value.bucket_arn]
  }

  statement {
    sid       = "WriteObjects"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${each.value.bucket_arn}/*"]
  }

  statement {
    sid       = "Invalidate"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = [each.value.distribution_arn]
  }
}

resource "aws_iam_role_policy" "site_deploy" {
  for_each = var.site_deploy_roles

  name   = "site-deploy"
  role   = aws_iam_role.site_deploy[each.key].id
  policy = data.aws_iam_policy_document.site_deploy[each.key].json
}
