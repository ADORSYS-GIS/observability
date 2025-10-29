resource "google_compute_address" "default" {
  count        = var.regional ? 1 : 0
  name         = local.name
  region       = var.region
  project      = var.project_id
  address_type = "EXTERNAL"
}

resource "google_compute_global_address" "default" {
  count        = var.regional ? 0 : 1
  name         = local.name
  project      = var.project_id
  address_type = "EXTERNAL"
}