# EKS Cloud Resources Module for LGTM Stack

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# S3 Buckets for LGTM components
resource "aws_s3_bucket" "observability_buckets" {
  for_each = toset(var.bucket_names)

  bucket        = "${var.bucket_prefix}-${each.key}"
  force_destroy = var.force_destroy_buckets

  tags = {
    Name        = "${var.bucket_prefix}-${each.key}"
    Environment = var.environment
    ManagedBy   = "terraform"
    Component   = var.component_name
  }
}

# Enable versioning
resource "aws_s3_bucket_versioning" "observability_buckets" {
  for_each = toset(var.bucket_names)

  bucket = aws_s3_bucket.observability_buckets[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle rules
resource "aws_s3_bucket_lifecycle_configuration" "observability_buckets" {
  for_each = toset(var.bucket_names)

  bucket = aws_s3_bucket.observability_buckets[each.key].id

  rule {
    id     = "expire-old-data"
    status = "Enabled"

    expiration {
      days = var.retention_days
    }
  }
}

# IAM Role for IRSA (IAM Roles for Service Accounts)
resource "aws_iam_role" "observability_irsa" {
  name        = "${var.cluster_name}-lgtm-irsa"
  description = "IAM role for LGTM stack with IRSA"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.eks_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(var.eks_oidc_provider_arn, "/^(.*provider/)/", "")}:sub" = "system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account_name}"
            "${replace(var.eks_oidc_provider_arn, "/^(.*provider/)/", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# IAM Policy for S3 access
resource "aws_iam_role_policy" "observability_s3_access" {
  name = "lgtm-s3-access"
  role = aws_iam_role.observability_irsa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          for bucket in aws_s3_bucket.observability_buckets : bucket.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          for bucket in aws_s3_bucket.observability_buckets : "${bucket.arn}/*"
        ]
      }
    ]
  })
}
