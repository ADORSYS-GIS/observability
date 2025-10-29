output "dns_ns" {
  value       = module.dns.name_servers
  description = "The Zone NS"
}

output "k8s_name" {
  value = module.k8s.cluster_name
}

output "k8s_host" {
  value = module.gke_auth.host
}

output "wazuh_domains" {
  value = {
    for k, v in local.wazuh_domains : k => {
      ip        = module.ip[k].address
      name      = module.ip[k].address_name
      cert_name = module.ip[k].address_name
      domain    = "https://${v.domain}"
    }
  }
}
