resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.name}-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

locals {
  s3_origin_id  = "s3-site"
  ec2_origin_id = "ec2-v2ray"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name} — static site + v2ray WS + speedtest"
  default_root_object = "index.html"
  price_class         = "PriceClass_All" # adds ME + Asia + SA edges (~+15% per GB)

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  origin {
    domain_name = aws_instance.v2ray.public_dns
    origin_id   = local.ec2_origin_id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # AWS-managed CachingOptimized.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # /ping — short text response, never cache.
  ordered_cache_behavior {
    path_pattern             = "/ping"
    target_origin_id         = local.ec2_origin_id
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "33f36d7e-f396-46d9-90e0-52428a34d9dc" # AllViewerAndCloudFrontHeaders-2022-06
    compress                 = false
  }

  # /stats.json — live host metrics JSON, never cache.
  ordered_cache_behavior {
    path_pattern             = "/stats.json"
    target_origin_id         = local.ec2_origin_id
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "33f36d7e-f396-46d9-90e0-52428a34d9dc" # AllViewerAndCloudFrontHeaders-2022-06
    compress                 = true
  }

  # /speedtest — random payload, never cache (we want real bytes from EC2).
  ordered_cache_behavior {
    path_pattern             = "/speedtest"
    target_origin_id         = local.ec2_origin_id
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "33f36d7e-f396-46d9-90e0-52428a34d9dc" # AllViewerAndCloudFrontHeaders-2022-06
    compress                 = false
  }

  # v2ray WebSocket path — all methods, no cache, pass everything through.
  ordered_cache_behavior {
    path_pattern             = var.ws_path
    target_origin_id         = local.ec2_origin_id
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "33f36d7e-f396-46d9-90e0-52428a34d9dc" # AllViewerAndCloudFrontHeaders-2022-06
    compress                 = false
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
