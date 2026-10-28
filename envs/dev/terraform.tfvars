environment       = "dev"
aws_region        = "ap-south-1"
project           = "acme"
vpc_cidr          = "10.10.0.0/16"
nat_gateway_count = 0

# Windows are UTC; keep them outside the office-hours schedule (dev runs 08:00-20:00 local).
db = {
  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  multi_az              = false
  backup_retention_days = 1
  deletion_protection   = false
  skip_final_snapshot   = true
  backup_window         = "05:00-05:30"
  maintenance_window    = "mon:05:30-mon:06:30"
}

bitbucket = {
  oidc_provider_url   = "https://api.bitbucket.org/2.0/workspaces/your-workspace/pipelines-config/identity/oidc"
  oidc_audience       = "ari:cloud:bitbucket::workspace/00000000-0000-0000-0000-000000000000"
  backend_repo_uuid   = "{00000000-0000-0000-0000-000000000001}"
  admin_web_repo_uuid = "{00000000-0000-0000-0000-000000000002}"
  iaac_repo_uuid      = "{00000000-0000-0000-0000-000000000003}" # acme-terraform
  landing_repo_uuid   = "{00000000-0000-0000-0000-000000000004}" # acme-landing-page

  # Deployment environment UUIDs (OIDC page → Select Environment). NOT the repo UUID.
  iaac_dev_env_uuid      = "{00000000-0000-0000-0000-000000000013}"
  backend_dev_env_uuid   = "{00000000-0000-0000-0000-000000000011}"
  admin_web_dev_env_uuid = "{00000000-0000-0000-0000-000000000012}"
  landing_dev_env_uuid   = "{00000000-0000-0000-0000-000000000014}" # landing has one site: Production
}

# Landing site enquiries (each address must confirm the SNS e-mail once)
landing_form_emails = ["ops@example.com"]

hostnames = {
  frontend    = "dev.example.com"
  admin       = "admin-dev.example.com"
  api         = "api-dev.example.com"
  landing     = "example.com"
  landing_www = "www.example.com"
}

certificates_validated = true

landing_certificate_validated = true

app_image_tag = "replace-with-git-sha"

app_environment = {
  APP_ENV                    = "local" # allows http://localhost origins while the admin web runs locally; use "staging" otherwise
  LOG_LEVEL                  = "debug"
  OPS_TIMEZONE               = "Etc/UTC"
  HTTP_PORT                  = "8080"
  HTTP_TRUSTED_PROXY_HOPS    = "2" # CloudFront + ALB
  AUTH_COOKIE_SECURE         = "true"
  AUTH_ALLOWED_ORIGINS       = "https://dev.example.com,https://admin-dev.example.com,http://localhost:3000" # localhost: dev only, for admin web running locally
  SMS_PROVIDER               = "log"
  CUSTOMER_OTP_FIXED_CODE    = "123456" # dev only; the app refuses it in prod
  PAYMENT_PROVIDER           = "stripe"
  STRIPE_PUBLISHABLE_KEY     = "pk_test_replace_me"
  NEAREST_POINT_MAX_RADIUS_M = "25000"
}

budget_alert_emails = ["ops@example.com"]

# Initial image only: after Phase 10 the pipeline sets the running image (ignore_changes)
admin_web_image_tag = "replace-with-git-sha"

admin_web_environment = {
  ENVIRONMENT       = "staging" # development would expose /docs publicly
  ACME_API_BASE_URL = "https://api-dev.example.com/api/v1"
  APP_ORIGIN        = "https://admin-dev.example.com" # must be in the API's AUTH_ALLOWED_ORIGINS
  API_TIMEOUT_MS    = "15000"
  PORT              = "8080"
  HOSTNAME          = "0.0.0.0" # Next.js standalone listens on all interfaces
}
