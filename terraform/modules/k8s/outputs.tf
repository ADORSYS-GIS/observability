output "cluster_name" {
  value = module.gke.cluster_name
}

output "cluster_location" {
  value       = module.gke.location
  description = "K8s Cluster location"
}

output "cluster_id" {
  value = module.gke.cluster_id
}