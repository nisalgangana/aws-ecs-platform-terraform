# AWS managed policies (looked up by name, never hardcode their IDs)
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

locals {
  vpc_origin_id = var.vpc_origin_id != null ? var.vpc_origin_id : aws_cloudfront_vpc_origin.alb[0].id
}

# ---------------------------------------------------------------
# VPC origin: created once per ALB, shared by every distribution
# in front of it. Takes ~15 minutes to create.
# ---------------------------------------------------------------
resource "aws_cloudfront_vpc_origin" "alb" {
  count = var.vpc_origin_id == null ? 1 : 0

  vpc_origin_endpoint_config {
    name                   = "${var.name_prefix}-alb"
    arn                    = var.alb_arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = {
    Name = "${var.name_prefix}-alb-vpc-origin"
  }
}

# The single VPC origin became optional (count): keep the existing one
moved {
  from = aws_cloudfront_vpc_origin.alb
  to   = aws_cloudfront_vpc_origin.alb[0]
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  comment         = "${var.name_prefix} ${var.description}"
  aliases         = var.aliases
  price_class     = var.price_class
  web_acl_id      = var.web_acl_arn

  origin {
    origin_id   = "alb"
    domain_name = var.alb_dns_name

    vpc_origin_config {
      vpc_origin_id            = local.vpc_origin_id
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }
  }

  # Default: nothing is cached, every header/cookie/query string reaches the app
  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = var.viewer_protocol_policy
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  }

  # Hashed build assets never change: cache them at the edge.
  # AllViewer still forwards Host, so the ALB rule and TLS name match.
  dynamic "ordered_cache_behavior" {
    for_each = var.static_cache_paths
    content {
      path_pattern           = ordered_cache_behavior.value
      target_origin_id       = "alb"
      viewer_protocol_policy = var.viewer_protocol_policy
      allowed_methods        = ["GET", "HEAD", "OPTIONS"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      cache_policy_id          = data.aws_cloudfront_cache_policy.optimized.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "${var.name_prefix}-${var.name}"
  }
}
