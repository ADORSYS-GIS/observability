terraform {
  required_version = ">= 1.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

resource "helm_release" "cert_manager" {
  count = var.install_cert_manager ? 1 : 0

  name             = var.release_name
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = var.namespace
  create_namespace = true
  version          = var.cert_manager_version

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "global.leaderElection.namespace"
    value = var.namespace
  }

  wait            = true
  wait_for_jobs   = true
  timeout         = 900
  atomic          = false
  cleanup_on_fail = false

  provisioner "local-exec" {
    when       = destroy
    command    = <<-EOT
      echo "[cert-manager] Cleaning up CRDs before Helm uninstall..."
      kubectl delete crd certificaterequests.cert-manager.io --ignore-not-found=true --timeout=60s || true
      kubectl delete crd certificates.cert-manager.io --ignore-not-found=true --timeout=60s || true
      kubectl delete crd challenges.acme.cert-manager.io --ignore-not-found=true --timeout=60s || true
      kubectl delete crd clusterissuers.cert-manager.io --ignore-not-found=true --timeout=60s || true
      kubectl delete crd issuers.cert-manager.io --ignore-not-found=true --timeout=60s || true
      kubectl delete crd orders.acme.cert-manager.io --ignore-not-found=true --timeout=60s || true
      echo "[cert-manager] ✓ CRD cleanup completed"
    EOT
    on_failure = continue
  }
}

locals {
  issuer_namespace = var.cert_issuer_kind == "Issuer" ? coalesce(var.issuer_namespace, var.namespace) : ""

  issuer_wait_script = var.cert_issuer_kind == "Issuer" ? join("\n", [
    "# Wait for namespace to exist (Issuer is namespace-scoped)",
    "NAMESPACE=\"${local.issuer_namespace}\"",
    "echo \"[cert-manager] Waiting for namespace $NAMESPACE to exist (max 10 minutes)...\"",
    "RETRY=0",
    "MAX_RETRIES=300",
    "while [ $RETRY -lt $MAX_RETRIES ]; do",
    "  if kubectl get namespace \"$NAMESPACE\" >/dev/null 2>&1; then",
    "    echo \"[cert-manager] ✓ Namespace $NAMESPACE exists\"",
    "    break",
    "  fi",
    "  RETRY=$((RETRY + 1))",
    "  if [ $RETRY -ge $MAX_RETRIES ]; then",
    "    echo \"[cert-manager] ✗ ERROR: Timeout waiting for namespace $NAMESPACE after $MAX_RETRIES retries\"",
    "    echo \"[cert-manager] This namespace should be created by the hub-cluster module\"",
    "    exit 1",
    "  fi",
    "  if [ $((RETRY % 15)) -eq 0 ]; then",
    "    echo \"[cert-manager] Still waiting for namespace $NAMESPACE... ($RETRY/$MAX_RETRIES)\"",
    "  fi",
    "  sleep 2",
    "done",
  ]) : ""

  issuer_manifest = join("\n", [
    "apiVersion: cert-manager.io/v1",
    "kind: ${var.cert_issuer_kind}",
    "metadata:",
    "  name: ${var.cert_issuer_name}",
    var.cert_issuer_kind == "Issuer" ? "  namespace: ${local.issuer_namespace}" : "",
    "spec:",
    "  acme:",
    "    server: ${var.issuer_server}",
    "    email: ${var.letsencrypt_email}",
    "    privateKeySecretRef:",
    "      name: ${var.cert_issuer_name}-key",
    "    solvers:",
    "    - http01:",
    "        ingress:",
    "          class: ${var.ingress_class_name}",
  ])
}

# Issuer for Let's Encrypt
resource "null_resource" "letsencrypt_issuer" {
  count = var.install_cert_manager && var.create_issuer ? 1 : 0

  triggers = {
    cert_issuer_kind = var.cert_issuer_kind
    cert_issuer_name = var.cert_issuer_name
    namespace        = local.issuer_namespace
    manifest_hash    = md5(local.issuer_manifest)
  }

  provisioner "local-exec" {
    command = <<-EOT
      ${local.issuer_wait_script}
      
      # Apply the ${var.cert_issuer_kind}
      kubectl apply -f - <<EOF
${local.issuer_manifest}
EOF
    EOT
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "kubectl delete ${self.triggers.cert_issuer_kind} ${self.triggers.cert_issuer_name} --ignore-not-found=true ${self.triggers.cert_issuer_kind == "Issuer" ? "--namespace ${self.triggers.namespace}" : ""}"
    on_failure = continue
  }

  depends_on = [helm_release.cert_manager]
}

# Explicit namespace cleanup on destroy
resource "null_resource" "namespace_cleanup" {
  count = var.install_cert_manager ? 1 : 0

  triggers = {
    namespace = var.namespace
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "kubectl delete namespace ${self.triggers.namespace} --ignore-not-found=true --timeout=60s || true"
    on_failure = continue
  }

  depends_on = [helm_release.cert_manager]
}
