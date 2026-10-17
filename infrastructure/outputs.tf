output "site_url" {
  value       = "https://${var.domain_name}"
  description = "Canonical HTTPS URL"
}

output "site_bucket_name" {
  value       = aws_s3_bucket.site.id
  description = "Private S3 origin bucket"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.site.id
  description = "CloudFront distribution to invalidate after uploads"
}

output "certificate_arn" {
  value       = aws_acm_certificate_validation.site.certificate_arn
  description = "Issued ACM certificate attached to CloudFront"
}
