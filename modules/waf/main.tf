# ---------------------------------------------------------------
# WAFv2 web ACL for a CloudFront distribution.
# Scope CLOUDFRONT => every resource here must be created in us-east-1
# (pass providers = { aws = aws.us_east_1 } from the root module).
#
# Rule order (lower priority number wins):
#   0  allow-list IPs        allow   office / UAT providers / k6 runner
#   1  geo allow-list        block   everything outside allowed_country_codes
#   2  rate limit per IP     block   brute force, scrapers
#   3  IP reputation         AWS managed: known bad sources
#   4  common rule set       AWS managed: OWASP-style checks
#   5  known bad inputs      AWS managed: Log4j, bad hosts/paths
#   6  SQL injection         AWS managed: the backend is PostgreSQL
# ---------------------------------------------------------------
locals {
  name = "${var.name_prefix}-${var.name}"

  # count = observe only; none = the rule group's own action (block) applies
  managed_override = var.managed_rules_mode == "count" ? "count" : "none"
}

resource "aws_wafv2_ip_set" "allow" {
  count = length(var.allowed_ip_cidrs) > 0 ? 1 : 0

  name               = "${local.name}-allow-list"
  description        = "Sources that always pass the ${var.name} web ACL"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.allowed_ip_cidrs

  tags = {
    Name = "${local.name}-allow-list"
  }
}

resource "aws_wafv2_web_acl" "this" {
  name        = local.name
  description = "${var.name_prefix}: ${var.name} distribution"
  scope       = "CLOUDFRONT"

  # Private UAT: only the allow-list gets in. Otherwise everything that is not blocked passes.
  default_action {
    dynamic "allow" {
      for_each = var.restrict_to_allowed_ips ? [] : [1]
      content {}
    }
    dynamic "block" {
      for_each = var.restrict_to_allowed_ips ? [1] : []
      content {}
    }
  }

  # 0. Allow-list: skips every rule below
  dynamic "rule" {
    for_each = length(var.allowed_ip_cidrs) > 0 ? [1] : []
    content {
      name     = "allow-list"
      priority = 0

      action {
        allow {}
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.allow[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.name}-allow-list"
        sampled_requests_enabled   = true
      }
    }
  }

  # 1. Geo allow-list: block requests from any other country
  dynamic "rule" {
    for_each = length(var.allowed_country_codes) > 0 ? [1] : []
    content {
      name     = "geo-allow-list"
      priority = 1

      action {
        block {}
      }

      statement {
        not_statement {
          statement {
            geo_match_statement {
              country_codes = var.allowed_country_codes
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.name}-geo-block"
        sampled_requests_enabled   = true
      }
    }
  }

  # 2. Rate limit per source IP (5-minute window)
  rule {
    name     = "rate-limit"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit_per_5_min
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # 3. Amazon IP reputation list
  rule {
    name     = "aws-ip-reputation"
    priority = 3

    override_action {
      dynamic "count" {
        for_each = local.managed_override == "count" ? [1] : []
        content {}
      }
      dynamic "none" {
        for_each = local.managed_override == "none" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAmazonIpReputationList"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # 4. Common rule set (OWASP top 10 style). Individual rules can be set to count.
  rule {
    name     = "aws-common"
    priority = 4

    override_action {
      dynamic "count" {
        for_each = local.managed_override == "count" ? [1] : []
        content {}
      }
      dynamic "none" {
        for_each = local.managed_override == "none" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"

        dynamic "rule_action_override" {
          for_each = toset(var.common_rule_set_count_rules)
          content {
            name = rule_action_override.value
            action_to_use {
              count {}
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-common"
      sampled_requests_enabled   = true
    }
  }

  # 5. Known bad inputs (Log4j JNDI, malformed hosts and paths)
  rule {
    name     = "aws-known-bad-inputs"
    priority = 5

    override_action {
      dynamic "count" {
        for_each = local.managed_override == "count" ? [1] : []
        content {}
      }
      dynamic "none" {
        for_each = local.managed_override == "none" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # 6. SQL injection
  rule {
    name     = "aws-sqli"
    priority = 6

    override_action {
      dynamic "count" {
        for_each = local.managed_override == "count" ? [1] : []
        content {}
      }
      dynamic "none" {
        for_each = local.managed_override == "none" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-sqli"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.name
    sampled_requests_enabled   = true
  }

  tags = {
    Name = local.name
  }
}

# ---------------------------------------------------------------
# Logs: CloudWatch Logs in us-east-1. The group name must start with
# "aws-waf-logs-". Credentials never reach the log.
# ---------------------------------------------------------------
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${local.name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "aws-waf-logs-${local.name}"
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}
