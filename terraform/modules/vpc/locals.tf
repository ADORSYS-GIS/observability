locals {
  name                  = "${var.name}-vpc"
  router_name           = "${var.name}-router"
  nat_name              = "${var.name}-nat"
  pub_sub_network_name  = "${local.name}-subnet-01"
  priv_sub_network_name = "${local.name}-subnet-02"

  ip_range_name_pod      = "${local.name}-ip-range-pods"
  ip_range_name_services = "${local.name}-ip-range-services"
}
