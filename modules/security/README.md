# Module: security

Security groups (SG-to-SG rules), locked default SG, environment KMS key, app secret container.

| SG | Inbound | Outbound |
|---|---|---|
| alb | CloudFront VPC origin SG : 443 | app, admin-web : `app_port` |
| app | alb : `app_port` | all |
| db | app : `db_port` | none |

## Inputs
| Name | Default | Description |
|---|---|---|
| `name_prefix` | — | e.g. `acme-dev` |
| `vpc_id` | — | from `module.network.vpc_id` |
| `app_port` | `8080` | Go API port |
| `db_port` | `5432` | PostgreSQL |
| `kms_deletion_window_days` | `7` | 7 dev, 30 prod |
| `secret_recovery_window_days` | `7` | |

## Outputs
`alb_sg_id`, `app_sg_id`, `db_sg_id`, `kms_key_arn`, `kms_alias_name`, `app_secret_arn`

Secret **values** are never managed by Terraform (they would be stored in plain text in state).
