# Static marketing site: private S3 bucket read only by CloudFront (OAC),
# a CloudFront Function that maps pretty URLs to the static export's files.

# ---------------------------------------------------------------
# S3
# ---------------------------------------------------------------
resource "aws_s3_bucket" "site" {
  bucket = "${var.name_prefix}-landing-${var.aws_account_id}"
}

# Nothing in this bucket is ever public, even if someone adds an ACL later
resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Keeps the previous deploy so a bad release can be rolled back
resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 is enough for public HTML; KMS would add cost and a key policy for CloudFront
resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Only this distribution may read objects (confused-deputy protection)
data "aws_iam_policy_document" "site" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site.json

  # The public access block must exist first, or AWS may reject the policy
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# ---------------------------------------------------------------
# CloudFront
# ---------------------------------------------------------------

# Identity CloudFront uses to sign its requests to S3
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.name_prefix}-landing"
  description                       = "CloudFront access to the landing site bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# AWS managed policy (looked up by name, never hardcode the ID)
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# Lambda URLs need their own Host header, so everything else is forwarded
data "aws_cloudfront_origin_request_policy" "all_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_origin_access_control" "api" {
  count = var.api == null ? 0 : 1

  name                              = "${var.name_prefix}-landing-api"
  description                       = "CloudFront access to the landing site form Lambda"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}


# /about -> /about.html etc. Runs at the edge before the cache lookup.
resource "aws_cloudfront_function" "rewrite" {
  name    = "${var.name_prefix}-landing-rewrite"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/rewrite.js")
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  comment             = "${var.name_prefix} landing site"
  aliases             = var.aliases
  price_class         = var.price_class
  default_root_object = "index.html"

  origin {
    origin_id                = "s3"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  dynamic "origin" {
    for_each = var.api == null ? [] : [var.api]
    content {
      origin_id                = "api"
      domain_name              = origin.value.function_url_domain
      origin_access_control_id = aws_cloudfront_origin_access_control.api[0].id

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }


  # Everything is a static file: cache at the edge, HTTP -> HTTPS, read-only methods
  default_cache_behavior {
    target_origin_id       = "s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite.arn
    }
  }

  # Forms: never cached, every method. No rewrite function here:
  # it would turn /api/enquiry into /api/enquiry.html.
  dynamic "ordered_cache_behavior" {
    for_each = var.api == null ? [] : [1]
    content {
      path_pattern             = "/api/*"
      target_origin_id         = "api"
      viewer_protocol_policy   = "https-only"
      allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods           = ["GET", "HEAD"]
      cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_except_host.id
    }
  }


  # S3 answers 403 for missing keys (no ListBucket); show the site's 404 page for both
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Without a certificate (before L3) CloudFront's own *.cloudfront.net cert is used,
  # and AWS only accepts minimum_protocol_version = TLSv1 with it.
  viewer_certificate {
    cloudfront_default_certificate = var.certificate_arn == null
    acm_certificate_arn            = var.certificate_arn
    ssl_support_method             = var.certificate_arn == null ? null : "sni-only"
    minimum_protocol_version       = var.certificate_arn == null ? "TLSv1" : "TLSv1.2_2021"
  }

  tags = {
    Name = "${var.name_prefix}-landing"
  }
}

# Only this distribution may call the form Lambda (both permissions are required for OAC)
resource "aws_lambda_permission" "api_url" {
  count = var.api == null ? 0 : 1

  statement_id           = "AllowCloudFrontInvokeUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = var.api.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.site.arn
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "api_invoke" {
  count = var.api == null ? 0 : 1

  statement_id  = "AllowCloudFrontInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.api.function_name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.site.arn
}
