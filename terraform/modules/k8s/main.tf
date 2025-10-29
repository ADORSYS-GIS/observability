module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/gke-autopilot-cluster"
  version = "~> 38.0"

  project    = var.project_id
  name       = local.name
  location   = var.region
  network    = var.network_name
  subnetwork = var.sub_network_name

  deletion_protection = false

  ip_allocation_policy = {
    cluster_secondary_range_name  = var.ip_range_pod
    services_secondary_range_name = var.ip_range_services
  }

  private_cluster_config = {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_global_access_config = {
      enabled = true
    }
  }
  
  addons_config = {
    gcp_filestore_csi_driver_config = {
      enabled = true
    }
  }
  
  confidential_nodes = {
    enabled = false
  }
}
