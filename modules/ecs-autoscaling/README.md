# ecs-autoscaling

Application Auto Scaling for one ECS service. Separate from `ecs-service` so dev (fixed
`desired_count`, office-hours scheduler) is untouched.

- **Target tracking** on average CPU (default 60 %), optionally memory and ALB requests per
  target. Scale-out cooldown 60 s, scale-in 300 s.
- **Scheduled actions** change the min/max from a given time: the prod afternoon peak
  (`min 4` at 15:30, back to `min 2` at 17:30) and pre-prod office hours (`0/0` at night, so
  the service is stopped without fighting the scaler).
- `min_capacity`/`max_capacity` are ignored after creation: the scheduled actions own them.

```hcl
module "api_scaling" {
  source = "../../modules/ecs-autoscaling"

  cluster_name = module.ecs_cluster.cluster_name
  service_name = module.app_service.service_name
  min_capacity = 2
  max_capacity = 8
  timezone     = "Asia/Kolkata"

  scheduled_actions = {
    peak-start = { schedule = "cron(30 15 ? * * *)", min_capacity = 4, max_capacity = 8 }
    peak-end   = { schedule = "cron(30 17 ? * * *)", min_capacity = 2, max_capacity = 8 }
  }
}
```
