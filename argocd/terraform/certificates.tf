# Cert-Manager Resources for Internal CA and Agent mTLS

# 1. Self-Signed Issuer to bootstrap the CA
resource "kubernetes_manifest" "selfsigned_issuer" {
  provider = kubernetes.control_plane

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "selfsigned-issuer"
      namespace = var.argocd_namespace
    }
    spec = {
      selfSigned = {}
    }
  }
}

# 2. Internal CA Certificate (Root CA for Agents)
resource "kubernetes_manifest" "ca_certificate" {
  provider = kubernetes.control_plane

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "argocd-ca"
      namespace = var.argocd_namespace
    }
    spec = {
      isCA       = true
      commonName = "Argo CD Internal CA"
      secretName = "argocd-ca-cert" # This secret will contain ca.crt and tls.key
      privateKey = {
        algorithm = "RSA"
        size      = 4096
      }
      issuerRef = {
        name = "selfsigned-issuer"
        kind = "Issuer"
        group = "cert-manager.io"
      }
    }
  }

  depends_on = [kubernetes_manifest.selfsigned_issuer]
}

# 3. Internal Issuer (Uses the CA Certificate to sign other certs)
resource "kubernetes_manifest" "internal_issuer" {
  provider = kubernetes.control_plane

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "argocd-internal-issuer"
      namespace = var.argocd_namespace
    }
    spec = {
      ca = {
        secretName = "argocd-ca-cert"
      }
    }
  }

  depends_on = [kubernetes_manifest.ca_certificate]
}

# 4. Agent Client Certificate (Signed by Internal Issuer)
resource "kubernetes_manifest" "agent_certificate" {
  provider = kubernetes.control_plane

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "argocd-agent-client-cert"
      namespace = var.argocd_namespace
    }
    spec = {
      secretName = "argocd-agent-client-tls"
      duration   = "8760h0m0s" # 1 year
      renewBefore = "360h0m0s" # 15 days
      commonName = var.workload_clusters[0].agent_name
      dnsNames   = [var.workload_clusters[0].agent_name]
      usages     = ["client auth", "digital signature", "key encipherment"]
      issuerRef = {
        name = "argocd-internal-issuer"
        kind = "Issuer"
        group = "cert-manager.io"
      }
    }
  }

  depends_on = [kubernetes_manifest.internal_issuer]
}

