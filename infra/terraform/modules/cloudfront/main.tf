terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70"
    }
  }
}

variable "name_prefix" { type = string }
variable "alb_dns_name" { type = string }
variable "spa_bucket_regional_domain_name" { type = string }
variable "spa_bucket_id" { type = string }

resource "aws_cloudfront_origin_access_control" "spa" {
  name                              = "${var.name_prefix}-spa-oac"
  description                       = "OAC for SPA bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# AWS-managed cache policies (well-known IDs).
locals {
  managed_caching_optimized        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  managed_caching_disabled         = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
  managed_origin_request_all_viewer = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer
  managed_response_headers_security = "67f7725c-6f97-4210-82d7-5512b31e9d03" # SecurityHeadersPolicy
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name_prefix} CloudFront"
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # US/CA/EU edges only — cheapest

  origin {
    origin_id                = "spa"
    domain_name              = var.spa_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.spa.id
  }

  origin {
    origin_id   = "alb"
    domain_name = var.alb_dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "spa"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = local.managed_caching_optimized
    response_headers_policy_id = local.managed_response_headers_security
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = local.managed_caching_disabled
    origin_request_policy_id = local.managed_origin_request_all_viewer
  }

  # SPA routing: rewrite 403/404 from S3 back to /index.html so deep links work.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output "distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "distribution_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "distribution_arn" {
  value = aws_cloudfront_distribution.this.arn
}
