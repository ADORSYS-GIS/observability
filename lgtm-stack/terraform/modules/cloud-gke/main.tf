# GKE Cloud Resources Module for LGTM Stack

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# GCS Buckets for LGTM components
resource "google_storage_bucket" "observability_buckets" {
  for_each = toset(var.bucket_names)

  name          = "${var.project_id}-${each.key}"
  location      = var.region
  force_destroy = var.force_destroy_buckets

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.retention_days
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
    component   = var.component_name
  }
}

# GCP Service Account for Workload Identity
resource "google_service_account" "observability_sa" {
  account_id   = var.service_account_name
  display_name = "LGTM Observability Service Account"
  description  = "Service account for LGTM stack with Workload Identity"
}

# Grant Storage Object Admin on all buckets
resource "google_storage_bucket_iam_member" "bucket_object_admin" {
  for_each = toset(var.bucket_names)

  bucket = google_storage_bucket.observability_buckets[each.key].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.observability_sa.email}"
}

# Grant Legacy Bucket Writer role
resource "google_storage_bucket_iam_member" "bucket_legacy_writer" {
  for_each = toset(var.bucket_names)

  bucket = google_storage_bucket.observability_buckets[each.key].name
  role   = "roles/storage.legacyBucketWriter"
  member = "serviceAccount:${google_service_account.observability_sa.email}"
}

# Workload Identity binding
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.observability_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_service_account_name}]"
}
