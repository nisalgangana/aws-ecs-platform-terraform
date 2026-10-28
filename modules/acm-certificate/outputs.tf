output "certificate_arn" {
  description = "Use this ARN; after validation it only exists once the certificate is issued"
  value       = var.wait_for_validation ? aws_acm_certificate_validation.this[0].certificate_arn : aws_acm_certificate.this.arn
}

output "validation_records" {
  description = "CNAME records to add in the example.com zone"
  value = [
    for o in aws_acm_certificate.this.domain_validation_options : {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  ]
}
