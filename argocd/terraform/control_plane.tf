resource "kubernetes_namespace" "argocd_control_plane" {
  provider = kubernetes.control_plane

  metadata {
    name = var.argocd_namespace

    labels = merge(
      var.labels_common,
      {
        "cluster-role" = "control-plane"
      }
    )
    annotations = var.annotations_common
  }

  lifecycle {
    ignore_changes = [metadata]
  }
}

# resource "kubernetes_secret" "argocd_server_tls_cp" {
#   # Managed by cert-manager (Ingress)
# }

# resource "kubernetes_secret" "argocd_ca_cert_cp" {
#   # Managed by cert-manager
# }

resource "helm_release" "cert_manager" {
  provider = helm.control_plane

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.13.3"

  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "kubernetes_manifest" "letsencrypt_issuer" {
  provider = kubernetes.control_plane

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.acme_email
        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}

# FIXED: Simplified Helm configuration with proper timeout
resource "helm_release" "argocd_control_plane" {
  provider = helm.control_plane

  name             = "argocd"
  repository       = var.helm_repository_url
  chart            = "argo-cd"
  namespace        = kubernetes_namespace.argocd_control_plane.metadata[0].name
  create_namespace = false
  version          = var.argocd_version

  # ADDED: Increased timeout and wait settings
  timeout         = 1200  # 20 minutes
  wait            = true
  wait_for_jobs   = true
  cleanup_on_fail = false  # Keep resources for debugging if it fails

  values = [
    yamlencode({
      global = {
        domain = var.control_plane_cluster.server_address
      }

      # Simplified configs section
      configs = {
        params = {
          "server.insecure" = tostring(!var.control_plane_cluster.tls_enabled)
        }
        cm = {
          "admin.enabled" = "true"
          "timeout.reconciliation" = "180s"
        }
      }

      server = {
        replicas = 1
        
        service = {
          type = var.server_service_type
        }
        
        ingress = {
          enabled = true
          annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
            "kubernetes.io/ingress.class"    = "nginx"
          }
          hosts = [
            var.domain_name
          ]
          tls = [
            {
              secretName = "argocd-server-tls"
              hosts      = [var.domain_name]
            }
          ]
        }

        # Simplified metrics
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false
          }
        }

        # Resource limits to prevent OOM issues
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "264Mi"
          }
        }
      }

      repoServer = {
        replicas = var.repo_server_replicas

        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false
          }
        }

        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "264Mi"
          }
        }
      }

      controller = {
        replicas = var.controller_replicas

        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false
          }
        }

        resources = {
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "1000m"
            memory = "512Mi"
          }
        }
      }

      dex = {
        enabled = true
        resources = {
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "128Mi"
          }
        }
      }

      redis = {
        enabled = true
        # Disable persistence for local clusters to avoid PVC issues
        persistence = {
          enabled = false
        }
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }

      # RBAC
      rbac = {
        create = true
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd_control_plane,
    # kubernetes_secret.argocd_server_tls_cp,
    # kubernetes_secret.argocd_ca_cert_cp
  ]
}

resource "kubernetes_service" "argocd_server_grpc_cp" {
  provider = kubernetes.control_plane

  metadata {
    name      = "argocd-server-grpc"
    namespace = kubernetes_namespace.argocd_control_plane.metadata[0].name

    labels = merge(
      var.labels_common,
      { "component" = "server-grpc" }
    )

    annotations = merge(
      var.annotations_common,
      {
        "description" = "gRPC service for Argo CD agent communication with mTLS"
      }
    )
  }

  spec {
    type = "ClusterIP"

    port {
      name        = "grpc"
      port        = var.control_plane_cluster.server_port
      target_port = 8080
      protocol    = "TCP"
    }

    selector = {
      "app" = "argocd-agent-principal"
    }
  }

  depends_on = [helm_release.argocd_control_plane]
}

resource "kubernetes_service" "argocd_principal_external_cp" {
  provider = kubernetes.control_plane

  metadata {
    name      = "argocd-principal"
    namespace = kubernetes_namespace.argocd_control_plane.metadata[0].name

    labels = merge(
      var.labels_common,
      { "component" = "principal" }
    )
    annotations = var.annotations_common
  }

  spec {
    type = var.server_service_type

    port {
      name        = "http"
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }

    port {
      name        = "https"
      port        = 443
      target_port = 8080
      protocol    = "TCP"
    }

    selector = {
      "app.kubernetes.io/name" = "argocd-server"
    }
  }

  depends_on = [helm_release.argocd_control_plane]
}

resource "kubernetes_config_map" "argocd_principal_config_cp" {
  provider = kubernetes.control_plane

  metadata {
    name      = "argocd-principal-config"
    namespace = kubernetes_namespace.argocd_control_plane.metadata[0].name

    labels = merge(
      var.labels_common,
      { "component" = "principal-config" }
    )
    annotations = var.annotations_common
  }

  data = {
    "principal.address"                  = var.control_plane_cluster.server_address
    "principal.port"                     = tostring(var.control_plane_cluster.server_port)
    "principal.tls.enabled"              = tostring(var.control_plane_cluster.tls_enabled)
    "principal.tls.insecure_skip_verify" = tostring(!var.control_plane_cluster.tls_enabled)
    "principal.mode"                     = "principal"
  }

  depends_on = [kubernetes_namespace.argocd_control_plane]
}

resource "kubernetes_deployment" "argocd_agent_principal" {
  provider = kubernetes.control_plane

  metadata {
    name      = "argocd-agent-principal"
    namespace = kubernetes_namespace.argocd_control_plane.metadata[0].name

    labels = merge(
      var.labels_common,
      { "component" = "agent-principal" }
    )
    annotations = var.annotations_common
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app       = "argocd-agent-principal"
        component = "agent-principal"
      }
    }

    template {
      metadata {
        labels = merge(
          var.labels_common,
          {
            app       = "argocd-agent-principal"
            component = "agent-principal"
          }
        )
        annotations = var.annotations_common
      }

      spec {
        service_account_name = "argocd-server" # Reusing argocd-server SA for simplicity, or create a new one

        container {
          name              = "agent"
          image             = "ghcr.io/argoproj-labs/argocd-agent:v2.13.3"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "grpc"
            container_port = 8080
            protocol       = "TCP"
          }

          env {
            name  = "ARGOCD_AGENT_MODE"
            value = "principal"
          }

          env {
            name  = "ARGOCD_IN_CLUSTER"
            value = "true"
          }

          env {
            name  = "ARGOCD_NAMESPACE"
            value = kubernetes_namespace.argocd_control_plane.metadata[0].name
          }
          
          # TLS Configuration for the Principal Server (listening for agents)
          env {
            name  = "ARGOCD_AGENT_TLS_ENABLED"
            value = "true"
          }
          
          env {
             name = "ARGOCD_AGENT_TLS_CERT_FILE"
             value = "/etc/agent/tls/tls.crt"
          }
          
          env {
             name = "ARGOCD_AGENT_TLS_KEY_FILE"
             value = "/etc/agent/tls/tls.key"
          }
          
          env {
             name = "ARGOCD_AGENT_TLS_CA_FILE"
             value = "/etc/agent/ca/ca.crt"
          }

          volume_mount {
            name       = "server-tls"
            mount_path = "/etc/agent/tls"
            read_only  = true
          }

          volume_mount {
            name       = "ca-cert"
            mount_path = "/etc/agent/ca"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }

        volume {
          name = "server-tls"
          secret {
            secret_name = "argocd-server-tls" # Managed by cert-manager
          }
        }

        volume {
          name = "ca-cert"
          secret {
            secret_name = "argocd-ca-cert" # Managed by cert-manager
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.argocd_control_plane,
    # kubernetes_secret.argocd_server_tls_cp,
    helm_release.argocd_control_plane
  ]
}

