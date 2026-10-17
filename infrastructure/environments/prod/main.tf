terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  backend "s3" {}
}

module "site" {
  source            = "../../"
  aws_region        = "us-east-1"
  domain_name       = "soadrian.com"
  route53_zone_name = "soadrian.com"
}

output "site_url" {
  value = module.site.site_url
}

output "site_bucket_name" {
  value = module.site.site_bucket_name
}

output "cloudfront_distribution_id" {
  value = module.site.cloudfront_distribution_id
}

output "certificate_arn" {
  value = module.site.certificate_arn
}
