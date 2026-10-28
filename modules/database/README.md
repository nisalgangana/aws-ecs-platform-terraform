# Module: database

RDS PostgreSQL 16 in private-data subnets. TLS forced, IAM auth on,
master password created and rotated by RDS in Secrets Manager (never in code or state).

## Inputs
| Name | Description |
|---|---|
| `name_prefix` | e.g. `acme-dev` |
| `subnet_ids` | private-data subnet IDs (2 AZs) |
| `db_sg_id`, `kms_key_arn` | from `module.security` |
| `instance_class`, `allocated_storage`, `multi_az` | size per environment |
| `backup_retention_days`, `backup_window`, `maintenance_window` | windows in UTC |
| `deletion_protection`, `skip_final_snapshot` | dev: false / true, prod: true / false |
| `engine_version` (16), `db_name` (acme), `master_username` (acme_admin), `apply_immediately` | defaults |

## Outputs
`db_address`, `db_port`, `db_master_secret_arn`, `db_subnet_group_name`, `db_parameter_group_name`

⚠️ Changing `identifier`, `db_name`, `username`, `kms_key_id` or `storage_encrypted`
**replaces** the instance (data loss). Check every plan for `-/+`.
