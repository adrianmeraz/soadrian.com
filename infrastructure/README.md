# Infrastructure

Terraform serves `soadrian.com` from a private, encrypted, versioned S3 bucket through CloudFront. ACM issues the certificate in `us-east-1`, Route 53 supplies DNS validation and apex aliases, and CloudFront redirects HTTP to HTTPS with TLS 1.2 or newer.

The layout and deployment conventions follow the `smart-margin` and `ResumePilot` repositories:

- Terraform owns application infrastructure and DNS records.
- GitHub Actions authenticates to AWS with OIDC rather than long-lived access keys.
- S3 remains private; CloudFront reads it through Origin Access Control.
- The certificate is created before CloudFront and retained during replacement.

## One-time bootstrap

Authenticate the AWS CLI to the account that owns the `soadrian.com` Route 53 zone, then run:

```powershell
cd infrastructure\bootstrap
.\bootstrap.ps1
```

The script is idempotent. It reuses the account-wide GitHub OIDC provider if one of the reference projects already created it, and creates:

- `soadrian-com-tfstate`, the encrypted/versioned Terraform state bucket;
- `soadrian-com-tflock`, the state lock table;
- `soadrian-com-deploy-prod`, the repo- and environment-scoped deployment role.

Create a GitHub environment named `prod` and store the printed ARN there as the `AWS_DEPLOY_ROLE_PROD` secret.

## Deployment

A push to `main` applies Terraform, uploads `dist/`, and invalidates CloudFront. The initial run can take several minutes while ACM validates the domain and CloudFront creates the distribution. Existing apex DNS changes to the CloudFront alias during that apply.
