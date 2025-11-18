resource "helm_release" "wazuh" {
  count = 1

  name             = "wazuh-release"
  namespace        = kubernetes_namespace.wazuh_namespace.metadata[0].name
  create_namespace = false

  repository = "https://adorsys-gis.github.io/wazuh-helm"
  chart      = "wazuh-helm"
  version    = var.helm_chart_version
  
  values = [
    file("${path.module}/files/.wazuh-helm/charts/wazuh/values-high-ressources.yaml"),
    file("${path.module}/files/.wazuh-helm/charts/wazuh/values-gke.yaml"),
    file("${path.module}/files/.wazuh-helm/charts/wazuh/values-gke-pv.yaml"),
    file("${path.module}/files/.wazuh-helm/charts/wazuh/values-gke-svc.yaml"),
    file("${path.module}/files/.wazuh-helm/charts/wazuh/values-gke-autopilot.yaml"),
    file("${path.module}/files/.wazuh-helm/charts/wazuh/values-permission-fix.yaml"),
    templatefile("${path.module}/files/wazuh.values.yaml", {
      dashboard_domain           = var.ip_addresses.dashboard.domain
      dashboard_certificate_name = local.dashboard_certificate_name
      dashboard_name             = var.ip_addresses.dashboard.ip_name
      dashboard_ip               = var.ip_addresses.dashboard.ip

      manager_domain           = var.ip_addresses.manager.domain
      manager_certificate_name = local.manager_certificate_name
      manager_name             = var.ip_addresses.manager.ip_name
      manager_ip               = var.ip_addresses.manager.ip

      openid_connect_url = var.openid_connect_url
    })
  ]

  set_sensitive {
    name  = "cluster.auth.key"
    value = random_id.hex_16.hex
  }
  
  set_sensitive {
    name  = "indexer.keycloak.client_id"
    value = var.openid_client_id
  }
  
  set_sensitive {
    name  = "indexer.keycloak.client_secret"
    value = var.openid_client_secret
  }

  set {
    name  = "cluster.rootCaSecretName"
    value = local.root_secret_name
  }

  cleanup_on_fail = false
  wait            = false

  depends_on = [kubernetes_namespace.wazuh_namespace, helm_release.other_resources]
}

resource "random_id" "hex_16" {
  byte_length = 16
}

resource "kubernetes_namespace" "wazuh_namespace" {
  metadata {
    name = "wazuh"
  }
}
# --- Root CA key ---
resource "tls_private_key" "root_ca_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# --- Self-signed Root CA cert ---
resource "tls_self_signed_cert" "root_ca" {
  private_key_pem       = tls_private_key.root_ca_key.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 365 * 10 * 24 # ~10 years

  subject {
    country      = var.subject.country
    locality     = var.subject.locality
    organization = var.subject.organization
    common_name  = var.subject.common_name
  }

  # Conservative, CA-appropriate usages
  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
    "key_encipherment",
  ]

  # Keep it SHA-256 like your openssl command
  early_renewal_hours = 0
}

# --- Kubernetes Secret with the PEMs ---
resource "kubernetes_secret" "wazuh_root_ca" {
  metadata {
    name      = local.root_secret_name
    namespace = kubernetes_namespace.wazuh_namespace.metadata[0].name
  }

  type = "Opaque"

  data = {
    "root-ca.pem"     = tls_self_signed_cert.root_ca.cert_pem
    "root-ca-key.pem" = tls_private_key.root_ca_key.private_key_pem
  }
}
