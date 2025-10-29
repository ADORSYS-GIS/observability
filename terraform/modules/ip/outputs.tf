output "address" {
  value       = coalesce(try(google_compute_global_address.default[0].address, null), try(google_compute_address.default[0].address, null))
  description = "IP Address"
}

output "address_name" {
  value       = local.name
  description = "IP Address name"
}
