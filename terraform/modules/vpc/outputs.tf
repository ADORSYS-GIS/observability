output "network_id" {
  value = module.vpc.network_id
}

output "network_name" {
  value = module.vpc.network_name
}

output "subnets_ips" {
  value = module.vpc.subnets_ips
}

output "pub_sub_network_name" {
  value = local.pub_sub_network_name
}

output "priv_sub_network_name" {
  value = local.priv_sub_network_name
}

output "network_self_link" {
  value = module.vpc.network_self_link
}

output "subnets" {
  value = module.vpc.subnets
}

output "ip_range_pod" {
  value = local.ip_range_name_pod
}

output "ip_range_services" {
  value = local.ip_range_name_services
}