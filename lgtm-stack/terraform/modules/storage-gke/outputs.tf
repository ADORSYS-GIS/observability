output "storage_buckets" {
  description = "Map of bucket names to their full GCS URIs"
  value = {
    for name, bucket in google_storage_bucket.observability_buckets :
    name => bucket.name
  }
}

output "service_account_email" {
  description = "Email of the GCP service account"
  value       = google_service_account.observability_sa.email
}

output "service_account_name" {
  description = "Name of the GCP service account"
  value       = google_service_account.observability_sa.name
}

output "workload_identity_annotation" {
  description = "Annotation to add to Kubernetes service account"
  value       = "iam.gke.io/gcp-service-account=${google_service_account.observability_sa.email}"
}
