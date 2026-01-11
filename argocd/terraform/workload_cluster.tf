# Workload Cluster Resources (Agent Deployment)

resource "kubernetes_namespace" "argocd_workload" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name = var.argocd_namespace

    labels = merge(
      var.labels_common,
      {
        "cluster-role" = "workload"
      }
    )
    annotations = var.annotations_common
  }
}

# resource "kubernetes_secret" "argocd_agent_client_tls" {
#   # Managed by cert-manager
# }

# resource "kubernetes_secret" "argocd_ca_cert_workload" {
#   # Managed by cert-manager
# }

resource "helm_release" "argocd_workload" {
  provider = helm.workload_cluster_1

  name             = "argocd"
  repository       = var.helm_repository_url
  chart            = "argo-cd"
  namespace        = var.argocd_namespace
  create_namespace = false
  version          = var.argocd_version

  timeout         = 900
  wait            = true
  wait_for_jobs   = true
  cleanup_on_fail = false

  values = [
    yamlencode({
      global = {
        domain = "argocd-workload"
      }

      configs = {
        params = {
          "server.insecure" = "true"
        }
        cm = {
          "server.disable.auth" = "true"
          "timeout.reconciliation" = "180s"
        }
      }

      server = {
        replicas = 1
        
        service = {
          type = "ClusterIP"
        }

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
            memory = "512Mi"
          }
        }
      }

      repoServer = {
        replicas = 1

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
            memory = "512Mi"
          }
        }
      }

      controller = {
        replicas = 1

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
            memory = "1Gi"
          }
        }
      }

      dex = {
        enabled = false
      }

      redis = {
        enabled = true
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

      rbac = {
        create = true
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd_workload]
}

resource "kubernetes_config_map" "argocd_agent_config" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name      = "argocd-agent-config"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name

    labels = merge(
      var.labels_common,
      { "component" = "agent-config" }
    )
    annotations = var.annotations_common
  }

  data = {
    "server.address"      = var.workload_clusters[0].principal_address
    "server.port"         = tostring(var.workload_clusters[0].principal_port)
    "server.tls.enabled"  = tostring(var.workload_clusters[0].tls_enabled)
    "agent.name"          = var.workload_clusters[0].agent_name
    "agent.mode"          = var.agent_mode
    "agent.tls.enabled"   = tostring(var.workload_clusters[0].tls_enabled)
    "agent.tls.cert.path" = "/etc/agent/tls/tls.crt"
    "agent.tls.key.path"  = "/etc/agent/tls/tls.key"
    "agent.tls.ca.path"   = "/etc/agent/ca/ca.crt"
  }

  depends_on = [kubernetes_namespace.argocd_workload]
}

resource "kubernetes_service_account" "argocd_agent" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name      = "argocd-agent"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name

    labels = merge(
      var.labels_common,
      { "component" = "agent" }
    )
    annotations = var.annotations_common
  }

  depends_on = [kubernetes_namespace.argocd_workload]
}

# FIXED: Proper ClusterRole with valid permissions
resource "kubernetes_cluster_role" "argocd_agent" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name = "argocd-agent"

    labels = merge(
      var.labels_common,
      { "component" = "agent" }
    )
    annotations = var.annotations_common
  }

  # Core API resources
  rule {
    api_groups = [""]
    resources = [
      "pods",
      "services",
      "configmaps",
      "secrets",
      "namespaces",
      "events",
      "serviceaccounts",
      "endpoints",
      "persistentvolumeclaims"
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Apps resources
  rule {
    api_groups = ["apps"]
    resources = [
      "deployments",
      "replicasets",
      "statefulsets",
      "daemonsets"
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Batch resources
  rule {
    api_groups = ["batch"]
    resources = [
      "jobs",
      "cronjobs"
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # RBAC resources
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources = [
      "roles",
      "rolebindings",
      "clusterroles",
      "clusterrolebindings"
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Networking resources
  rule {
    api_groups = ["networking.k8s.io"]
    resources = [
      "ingresses",
      "networkpolicies",
      "ingressclasses"
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Storage resources
  rule {
    api_groups = ["storage.k8s.io"]
    resources = [
      "storageclasses"
    ]
    verbs = ["get", "list", "watch"]
  }

  # ArgoCD custom resources
  rule {
    api_groups = ["argoproj.io"]
    resources = [
      "applications",
      "applicationsets",
      "appprojects"
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Metrics
  rule {
    api_groups = ["metrics.k8s.io"]
    resources = [
      "pods",
      "nodes"
    ]
    verbs = ["get", "list"]
  }

  # API Extensions
  rule {
    api_groups = ["apiextensions.k8s.io"]
    resources = [
      "customresourcedefinitions"
    ]
    verbs = ["get", "list", "watch"]
  }

  # Auto-scaling
  rule {
    api_groups = ["autoscaling"]
    resources = [
      "horizontalpodautoscalers"
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Policy
  rule {
    api_groups = ["policy"]
    resources = [
      "poddisruptionbudgets"
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_cluster_role_binding" "argocd_agent" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name = "argocd-agent"

    labels = merge(
      var.labels_common,
      { "component" = "agent" }
    )
    annotations = var.annotations_common
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.argocd_agent.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.argocd_agent.metadata[0].name
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name
  }

  depends_on = [kubernetes_cluster_role.argocd_agent]
}

resource "kubernetes_deployment" "argocd_agent" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name      = "argocd-agent"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name

    labels = merge(
      var.labels_common,
      { "component" = "agent" }
    )
    annotations = var.annotations_common
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app       = "argocd-agent"
        component = "agent"
      }
    }

    template {
      metadata {
        labels = merge(
          var.labels_common,
          {
            app       = "argocd-agent"
            component = "agent"
          }
        )
        annotations = var.annotations_common
      }

      spec {
        service_account_name = kubernetes_service_account.argocd_agent.metadata[0].name

        container {
          name              = "agent"
          image             = "ghcr.io/argoproj-labs/argocd-agent:v2.13.3"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "metrics"
            container_port = 8080
            protocol       = "TCP"
          }

          env {
            name  = "AGENT_NAME"
            value = var.workload_clusters[0].agent_name
          }

          env {
            name  = "ARGOCD_SERVER_ADDRESS"
            value = var.workload_clusters[0].principal_address
          }

          env {
            name  = "ARGOCD_SERVER_PORT"
            value = tostring(var.workload_clusters[0].principal_port)
          }

          env {
            name  = "ARGOCD_AGENT_TLS_ENABLED"
            value = tostring(var.workload_clusters[0].tls_enabled)
          }

          env {
            name  = "ARGOCD_AGENT_MODE"
            value = var.agent_mode
          }

          dynamic "env" {
            for_each = var.workload_clusters[0].tls_enabled ? [1] : []
            content {
              name  = "ARGOCD_AGENT_TLS_CERT_FILE"
              value = "/etc/agent/tls/tls.crt"
            }
          }

          dynamic "env" {
            for_each = var.workload_clusters[0].tls_enabled ? [1] : []
            content {
              name  = "ARGOCD_AGENT_TLS_KEY_FILE"
              value = "/etc/agent/tls/tls.key"
            }
          }

          dynamic "env" {
            for_each = var.workload_clusters[0].tls_enabled ? [1] : []
            content {
              name  = "ARGOCD_AGENT_TLS_CA_FILE"
              value = "/etc/agent/ca/ca.crt"
            }
          }

          volume_mount {
            name       = "agent-tls"
            mount_path = "/etc/agent/tls"
            read_only  = true
          }

          volume_mount {
            name       = "agent-ca"
            mount_path = "/etc/agent/ca"
            read_only  = true
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/agent/config"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = "metrics"
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = "metrics"
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            failure_threshold     = 3
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "agent-tls"
          secret {
            secret_name = "argocd-agent-client-tls" # Created by cert-manager
          }
        }

        volume {
          name = "agent-ca"
          secret {
            secret_name = "argocd-ca-cert" # Created by cert-manager
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.argocd_agent_config.metadata[0].name
          }
        }

        security_context {
          fs_group = 1000
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.argocd_workload,
    # kubernetes_secret.argocd_agent_client_tls, # Managed by cert-manager
    kubernetes_config_map.argocd_agent_config,
    kubernetes_service_account.argocd_agent,
    kubernetes_cluster_role_binding.argocd_agent
  ]
}
