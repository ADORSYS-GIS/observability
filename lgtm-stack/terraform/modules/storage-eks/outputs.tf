output "storage_buckets" {
  description = "Map of bucket names to their S3 URLs"
  value = {
    for name, bucket in aws_s3_bucket.observability_buckets :
    name => bucket.bucket
  }
}

output "irsa_role_arn" {
  description = "ARN of the IAM role for IRSA"
  value       = aws_iam_role.observability_irsa.arn
}

output "irsa_role_name" {
  description = "Name of the IAM role"
  value       = aws_iam_role.observability_irsa.name
}

output "service_account_annotation" {
  description = "Annotation to add to Kubernetes service account"
  value       = "eks.amazonaws.com/role-arn=${aws_iam_role.observability_irsa.arn}"
}
