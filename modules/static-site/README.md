# Module: static-site

Static website (Next.js `output: "export"`) in a private S3 bucket, served by CloudFront.
S3 is read only by this one distribution (OAC + bucket policy with `AWS:SourceArn`).
A CloudFront Function maps pretty URLs to the export's files
(`/about` → `/about.html`, `/x/` → `/x/index.html`); missing keys (S3 403) become the site's
`/404.html`.

## Inputs
| Name | Description |
|---|---|
| `name_prefix` | e.g. `acme-dev` |
| `aws_account_id` | appended to the bucket name (`<prefix>-landing-<account-id>`) |
| `aliases` | hostnames served, e.g. `["example.com", "www.example.com"]`; `[]` = `*.cloudfront.net` only |
| `certificate_arn` | ACM cert in **us-east-1** covering every alias; `null` = CloudFront default cert (TLSv1 forced by AWS) |
| `price_class` | default `PriceClass_All` |

## Outputs
`bucket_name`, `bucket_arn` (CI deploy role), `distribution_id` (invalidations),
`distribution_arn` (CI deploy role), `distribution_domain_name`, `hosted_zone_id` (Route 53 ALIAS)

## Deploying content
The pipeline of the site repo (not Terraform) does:
```
aws s3 sync out/ s3://<bucket_name> --delete
aws cloudfront create-invalidation --distribution-id <distribution_id> --paths "/*"
```
Cache headers: `/_next/static/*` immutable, HTML `max-age=0, must-revalidate`.

## Notes
- `rewrite.js` assumes `trailingSlash: false` (default). With `trailingSlash: true` every page is
  `x/index.html` and the `.html` branch is never used; both forms are handled.
- The bucket policy references the distribution and the distribution references the bucket:
  Terraform orders bucket → distribution → policy. Do not inline the policy in the bucket.
- 404s are cached at the edge for 60 s (`error_caching_min_ttl`); the pipeline invalidation clears them.

⚠️ Changing `bucket` (name prefix or account ID) **replaces** the bucket and deletes its contents.
Check every plan for `-/+`.
