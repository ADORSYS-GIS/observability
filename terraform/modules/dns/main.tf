module "dns-public-zone" {
  source  = "terraform-google-modules/cloud-dns/google"
  version = "~> 6.0"

  project_id                         = var.project_id
  type                               = "public"
  name                               = local.zone_name
  domain                             = "${var.root_domain_name}."
  labels                             = var.labels
  private_visibility_config_networks = [var.network_self_link]
  
  recordsets = [
    for k, v in var.records :
    {
      name    = k
      type    = v.type
      ttl     = v.ttl
      records = v.records
    }
  ]
}
