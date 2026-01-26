output "storage_volumes" {
  description = "Map of storage names to PVC names"
  value = {
    for name, pvc in kubernetes_persistent_volume_claim.lgtm_storage :
    name => pvc.metadata[0].name
  }
}

output "storage_paths" {
  description = "Map of storage names to host paths"
  value = {
    for name in var.storage_names :
    name => "${var.host_path_base}/${name}"
  }
}
