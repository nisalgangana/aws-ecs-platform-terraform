# waf

One WAFv2 web ACL per CloudFront distribution (pre-prod and prod only; dev has no WAF to save
≈ $10/month).

CloudFront web ACLs live in **us-east-1**: call the module with
`providers = { aws = aws.us_east_1 }`.

## Rules

| Priority | Rule | Action | Why |
|---|---|---|---|
| 0 | `allow-list` (`allowed_ip_cidrs`) | allow | office, UAT providers and the k6 runner skip every rule below |
| 1 | `geo-allow-list` (`allowed_country_codes`) | block | the service is sold in a few countries only |
| 2 | `rate-limit` (`rate_limit_per_5_min` per IP) | block | brute force, scrapers |
| 3 | `AWSManagedRulesAmazonIpReputationList` | managed | known bad sources |
| 4 | `AWSManagedRulesCommonRuleSet` | managed | OWASP-style checks; single rules → count with `common_rule_set_count_rules` |
| 5 | `AWSManagedRulesKnownBadInputsRuleSet` | managed | Log4j, bad hosts/paths |
| 6 | `AWSManagedRulesSQLiRuleSet` | managed | backend is PostgreSQL |

- `managed_rules_mode = "count"` for the first weeks of a new environment: matches are logged,
  nothing is blocked. Switch to `block` after reading the logs.
- `restrict_to_allowed_ips = true` turns the ACL into a private allow-list (default action
  block). Used for the pre-prod admin panel.
- Logs go to CloudWatch Logs `aws-waf-logs-<name>` with `authorization` and `cookie` redacted.

## Cost

≈ $5 per web ACL + $1 per rule per month + $0.60 per million requests.
