# db-dr-backups

RDS **cross-Region automated backups** (prod only): snapshots and transaction logs are copied
continuously from Mumbai (`ap-south-1`) to Hyderabad (`ap-south-2`). RPO ≈ 5 minutes, RTO ≤ 4 h
(restore to a point in time in Hyderabad, then `terraform apply` the prod root with the DR
Region).

- Creates a KMS key in the DR Region (the primary key cannot be used there) and the
  replication itself. Call the module with `providers = { aws = aws.dr }`.
- `retention_days` is independent of the primary retention (35 days PITR in prod).
- Cost: storage of the replicated backups in Hyderabad + cross-Region data transfer.

Drill (quarterly, in the roadmap): restore the latest point in time in `ap-south-2`, run the
app against it, measure the time, delete it.
