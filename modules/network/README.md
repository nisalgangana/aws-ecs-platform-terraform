# Module: network

VPC with 3 subnet tiers across 2 AZs, internet gateway, optional NAT gateways, S3 gateway endpoint.

| Tier | AZ a | AZ b | Internet |
|---|---|---|---|
| public | x.x.0.0/24 | x.x.1.0/24 | IGW |
| private-app | x.x.10.0/24 | x.x.11.0/24 | NAT (only if `nat_gateway_count` > 0) |
| private-data | x.x.20.0/24 | x.x.21.0/24 | none |

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name_prefix` | string | — | e.g. `acme-dev` |
| `vpc_cidr` | string | — | e.g. `10.10.0.0/16` |
| `nat_gateway_count` | number | `0` | 0 dev, 1 preprod, 2 prod |

## Outputs

| Name | Description |
|---|---|
| `vpc_id` | ID of the VPC |
| `vpc_cidr_block` | CIDR block of the VPC |
| `public_subnet_ids` | public subnet IDs (AZ a, AZ b) |
| `private_app_subnet_ids` | private-app subnet IDs (AZ a, AZ b) |
| `private_data_subnet_ids` | private-data subnet IDs (AZ a, AZ b) |
| `nat_public_ips` | NAT gateway public IPs (empty when no NAT) |
