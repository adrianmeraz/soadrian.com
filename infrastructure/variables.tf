variable "aws_region" {
  type        = string
  description = "AWS region for the site and its CloudFront certificate"
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "CloudFront certificates must be provisioned in us-east-1."
  }
}

variable "domain_name" {
  type        = string
  description = "Apex domain served by CloudFront"
  default     = "soadrian.com"
}

variable "route53_zone_name" {
  type        = string
  description = "Public Route 53 hosted zone used for certificate validation and aliases"
  default     = "soadrian.com"
}
