# Module: db-ops-task

One-off `psql` task (ECS Fargate, ARM64, `postgres:18-alpine`) for admin SQL on the private RDS
database. Connects as the **master user**, whose credentials come from the RDS-managed secret at
start, so it keeps working after RDS rotates the password. No service; run it when needed.

## Run

```bash
NET=$(aws ecs describe-services --cluster acme-dev-cluster --services acme-dev-app \
      --query 'services[0].networkConfiguration' --output json)
aws ecs run-task --cluster acme-dev-cluster --launch-type FARGATE \
  --task-definition "$(terraform output -raw db_ops_task_definition_arn)" \
  --network-configuration "$NET" \
  --overrides '{"containerOverrides":[{"name":"db-ops","command":["psql","-c","SELECT 1;"]}]}'
aws logs tail /ecs/acme-dev-db-ops --since 5m
