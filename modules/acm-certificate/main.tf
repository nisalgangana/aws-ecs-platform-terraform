# DNS validation: ACM gives one CNAME per hostname. They are added by hand
# in the example.com zone (management account) and must stay there for renewals.
resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  tags = {
    Name = var.domain_name
  }

  # A changed hostname list creates the new certificate before the old one is removed
  lifecycle {
    create_before_destroy = true
  }
}

# Waits until ACM sees the CNAMEs and issues the certificate
resource "aws_acm_certificate_validation" "this" {
  count = var.wait_for_validation ? 1 : 0

  certificate_arn = aws_acm_certificate.this.arn
}
