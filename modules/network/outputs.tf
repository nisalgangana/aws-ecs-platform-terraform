output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs (AZ a, AZ b)"
  value       = [for k in local.subnet_keys_by_tier["public"] : aws_subnet.this[k].id]
}

output "private_app_subnet_ids" {
  description = "Private-app subnet IDs (AZ a, AZ b)"
  value       = [for k in local.subnet_keys_by_tier["private-app"] : aws_subnet.this[k].id]
}

output "private_data_subnet_ids" {
  description = "Private-data subnet IDs (AZ a, AZ b)"
  value       = [for k in local.subnet_keys_by_tier["private-data"] : aws_subnet.this[k].id]
}

output "nat_public_ips" {
  description = "Public IPs of the NAT gateways (empty when nat_gateway_count = 0)"
  value       = aws_eip.nat[*].public_ip
}