output "name_servers" {
  value = module.dns-public-zone.name_servers
  description = "The Zone NS"
}

output "zone_name" {
  description = "Name of the managed Cloud DNS zone."
  value       = local.zone_name
}
