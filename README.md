# soadrian.com

The personal portfolio of Adrian Meraz: a buildless, responsive static site with an original retro-futurist visual system.

## Structure

```text
dist/                  Production-ready website
  assets/              Original generated editorial artwork
infrastructure/        AWS edge hosting, TLS, and DNS as Terraform
.openai/hosting.json   Sites deployment manifest
.github/workflows/     Repository checks
```

## Local preview

```powershell
python -m http.server 4173 --directory dist
```

Then open `http://localhost:4173`.

## Production deployment

The production artifact is the `dist/` directory. Every push to `main` applies the production Terraform stack, syncs the exact committed artifact to a private S3 bucket, and invalidates CloudFront.

The edge stack follows the same pattern as smart-margin and ResumePilot: private S3 with Origin Access Control, CloudFront HTTPS redirects, an ACM certificate validated through Route 53, TLS 1.2+, and short-lived GitHub Actions credentials through OIDC. Run `infrastructure/bootstrap/bootstrap.ps1` once before the first deployment, then save the printed role ARN as the `AWS_DEPLOY_ROLE_PROD` secret in the GitHub `prod` environment.

## Design notes

The visual system uses original 16-bit pixel art, CRT scanlines, bitmap typography, neon channel shifts, and arcade-interface details to frame the site's agentic-development narrative.
