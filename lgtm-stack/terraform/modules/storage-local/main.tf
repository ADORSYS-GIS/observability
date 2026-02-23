# Generic Kubernetes Storage Module for LGTM Stack
# Uses PersistentVolumes instead of cloud storage

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# Create PersistentVolumes for each component
resource "kubernetes_persistent_volume" "lgtm_storage" {
  for_each = toset(var.storage_names)

  metadata {
    name = "lgtm-${each.key}-pv"
    labels = {
      component   = each.key
      managed-by  = "terraform"
      environment = var.environment
    }
  }

  spec {
    capacity = {
      storage = var.storage_sizes[each.key]
    }

    access_modes       = ["ReadWriteMany"]
    storage_class_name = var.storage_class

    persistent_volume_source {
      host_path {
        path = "${var.host_path_base}/${each.key}"
        type = "DirectoryOrCreate"
      }
    }
  }
}

# Create PVCs
resource "kubernetes_persistent_volume_claim" "lgtm_storage" {
  for_each = toset(var.storage_names)

  metadata {
    name      = "lgtm-${each.key}-pvc"
    namespace = var.k8s_namespace
    labels = {
      component   = each.key
      managed-by  = "terraform"
      environment = var.environment
    }
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = var.storage_class

    resources {
      requests = {
        storage = var.storage_sizes[each.key]
      }
    }

    volume_name = kubernetes_persistent_volume.lgtm_storage[each.key].metadata[0].name
  }
}
