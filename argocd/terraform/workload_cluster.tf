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

# Read CA cert from Control Plane
data "kubernetes_secret" "argocd_ca_cert_source" {
  provider = kubernetes.control_plane
  metadata {
    name      = "argocd-ca-cert"
    namespace = var.argocd_namespace
  }
  depends_on = [time_sleep.wait_for_certs]
}

# Read Agent TLS cert from Control Plane
data "kubernetes_secret" "argocd_agent_tls_source" {
  provider = kubernetes.control_plane
  metadata {
    name      = "argocd-agent-client-tls"
    namespace = var.argocd_namespace
  }
  depends_on = [time_sleep.wait_for_certs]
}

# Create CA cert in Workload Cluster
resource "kubernetes_secret" "argocd_ca_cert_workload" {
  provider = kubernetes.workload_cluster_1
  metadata {
    name      = "argocd-ca-cert"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name
  }
  data = data.kubernetes_secret.argocd_ca_cert_source.data
  type = data.kubernetes_secret.argocd_ca_cert_source.type
}

# Create Agent TLS cert in Workload Cluster
resource "kubernetes_secret" "argocd_agent_tls_workload" {
  provider = kubernetes.workload_cluster_1
  metadata {
    name      = "argocd-agent-client-tls"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name
  }
  data = data.kubernetes_secret.argocd_agent_tls_source.data
  type = data.kubernetes_secret.argocd_agent_tls_source.type
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
          image             = "ghcr.io/argoproj-labs/argocd-agent:${var.argocd_agent_version}"
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
            read_only_root_filesystem  = false
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
    kubernetes_secret.argocd_agent_tls_workload,
    kubernetes_secret.argocd_ca_cert_workload,
    kubernetes_config_map.argocd_agent_config,
    kubernetes_service_account.argocd_agent,
    kubernetes_cluster_role_binding.argocd_agent
  ]
}
# Application Controller for Managed Mode (Local Reconciliation)

resource "kubernetes_service_account" "argocd_application_controller" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name      = "argocd-application-controller"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name

    labels = merge(
      var.labels_common,
      { "component" = "application-controller" }
    )
    annotations = var.annotations_common
  }

  depends_on = [kubernetes_namespace.argocd_workload]
}

resource "kubernetes_cluster_role" "argocd_application_controller" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name = "argocd-application-controller"

    labels = merge(
      var.labels_common,
      { "component" = "application-controller" }
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

  # Application status
  rule {
    api_groups = ["argoproj.io"]
    resources = [
      "applications/status",
      "applications/finalizers"
    ]
    verbs = ["get", "patch", "update"]
  }

  # API Extensions
  rule {
    api_groups = ["apiextensions.k8s.io"]
    resources = [
      "customresourcedefinitions"
    ]
    verbs = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "argocd_application_controller" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name = "argocd-application-controller"

    labels = merge(
      var.labels_common,
      { "component" = "application-controller" }
    )
    annotations = var.annotations_common
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.argocd_application_controller.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.argocd_application_controller.metadata[0].name
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name
  }

  depends_on = [kubernetes_cluster_role.argocd_application_controller]
}

resource "kubernetes_deployment" "argocd_application_controller" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name      = "argocd-application-controller"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name

    labels = merge(
      var.labels_common,
      { "component" = "application-controller" }
    )
    annotations = var.annotations_common
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app       = "argocd-application-controller"
        component = "application-controller"
      }
    }

    template {
      metadata {
        labels = merge(
          var.labels_common,
          {
            app       = "argocd-application-controller"
            component = "application-controller"
          }
        )
        annotations = var.annotations_common
      }

      spec {
        service_account_name = kubernetes_service_account.argocd_application_controller.metadata[0].name

        container {
          name              = "application-controller"
          image             = "quay.io/argoproj/argocd:${var.argocd_version}"
          image_pull_policy = "IfNotPresent"

          command = ["argocd-application-controller"]

          args = [
            "--status-processors=20",
            "--operation-processors=10",
            "--app-resync=180",
            "--self-heal-timeout-seconds=5",
            "--repo-server=argocd-repo-server:8081",
            "--redis=argocd-redis:6379"
          ]

          port {
            name           = "metrics"
            container_port = 8082
            protocol       = "TCP"
          }

          env {
            name  = "ARGOCD_RECONCILIATION_TIMEOUT"
            value = "180s"
          }

          env {
            name  = "ARGOCD_APPLICATION_CONTROLLER_REPO_SERVER"
            value = "argocd-repo-server:8081"
          }

          env {
            name  = "ARGOCD_APPLICATION_CONTROLLER_REPO_SERVER_TIMEOUT_SECONDS"
            value = "60"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
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
              path = "/healthz"
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

        security_context {
          fs_group = 1000
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.argocd_workload,
    kubernetes_service_account.argocd_application_controller,
    kubernetes_cluster_role_binding.argocd_application_controller
  ]
}
# Autonomous Components for Workload Cluster (Repo-Server & Redis)

# Redis Deployment
resource "kubernetes_deployment" "argocd_redis_workload" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name      = "argocd-redis"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name

    labels = merge(
      var.labels_common,
      { "component" = "redis" }
    )
    annotations = var.annotations_common
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app       = "argocd-redis"
        component = "redis"
      }
    }

    template {
      metadata {
        labels = merge(
          var.labels_common,
          {
            app       = "argocd-redis"
            component = "redis"
          }
        )
        annotations = var.annotations_common
      }

      spec {
        container {
          name              = "redis"
          image             = "redis:7.0-alpine"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "redis"
            container_port = 6379
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            tcp_socket {
              port = "redis"
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 3
          }

          readiness_probe {
            tcp_socket {
              port = "redis"
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            failure_threshold     = 3
          }

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 999
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        security_context {
          fs_group = 999
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.argocd_workload]
}

resource "kubernetes_service" "argocd_redis_workload" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name      = "argocd-redis"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name

    labels = merge(
      var.labels_common,
      { "component" = "redis" }
    )
    annotations = var.annotations_common
  }

  spec {
    type = "ClusterIP"

    port {
      name        = "redis"
      port        = 6379
      target_port = "redis"
      protocol    = "TCP"
    }

    selector = {
      app       = "argocd-redis"
      component = "redis"
    }
  }

  depends_on = [kubernetes_deployment.argocd_redis_workload]
}

# Repo-Server Deployment
resource "kubernetes_service_account" "argocd_repo_server_workload" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name      = "argocd-repo-server"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name

    labels = merge(
      var.labels_common,
      { "component" = "repo-server" }
    )
    annotations = var.annotations_common
  }

  depends_on = [kubernetes_namespace.argocd_workload]
}

resource "kubernetes_deployment" "argocd_repo_server_workload" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name      = "argocd-repo-server"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name

    labels = merge(
      var.labels_common,
      { "component" = "repo-server" }
    )
    annotations = var.annotations_common
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app       = "argocd-repo-server"
        component = "repo-server"
      }
    }

    template {
      metadata {
        labels = merge(
          var.labels_common,
          {
            app       = "argocd-repo-server"
            component = "repo-server"
          }
        )
        annotations = var.annotations_common
      }

      spec {
        service_account_name = kubernetes_service_account.argocd_repo_server_workload.metadata[0].name

        container {
          name              = "repo-server"
          image             = "quay.io/argoproj/argocd:${var.argocd_version}"
          image_pull_policy = "IfNotPresent"

          command = ["argocd-repo-server"]

          args = [
            "--redis=argocd-redis:6379",
            "--loglevel=info",
            "--logformat=text"
          ]

          port {
            name           = "server"
            container_port = 8081
            protocol       = "TCP"
          }

          port {
            name           = "metrics"
            container_port = 8084
            protocol       = "TCP"
          }

          env {
            name  = "ARGOCD_RECONCILIATION_TIMEOUT"
            value = "180s"
          }

          env {
            name  = "ARGOCD_REPO_SERVER_LOGFORMAT"
            value = "text"
          }

          env {
            name  = "ARGOCD_REPO_SERVER_LOGLEVEL"
            value = "info"
          }

          env {
            name  = "ARGOCD_REPO_SERVER_PARALLELISM_LIMIT"
            value = "0"
          }

          volume_mount {
            name       = "plugins"
            mount_path = "/home/argocd/cmp-server/plugins"
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            tcp_socket {
              port = "server"
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 3
          }

          readiness_probe {
            tcp_socket {
              port = "server"
            }
            initial_delay_seconds = 5
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
          name = "plugins"
          empty_dir {}
        }

        volume {
          name = "tmp"
          empty_dir {}
        }

        security_context {
          fs_group = 1000
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.argocd_workload,
    kubernetes_service_account.argocd_repo_server_workload,
    kubernetes_deployment.argocd_redis_workload
  ]
}

resource "kubernetes_service" "argocd_repo_server_workload" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name      = "argocd-repo-server"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name

    labels = merge(
      var.labels_common,
      { "component" = "repo-server" }
    )
    annotations = var.annotations_common
  }

  spec {
    type = "ClusterIP"

    port {
      name        = "server"
      port        = 8081
      target_port = "server"
      protocol    = "TCP"
    }

    port {
      name        = "metrics"
      port        = 8084
      target_port = "metrics"
      protocol    = "TCP"
    }

    selector = {
      app       = "argocd-repo-server"
      component = "repo-server"
    }
  }

  depends_on = [kubernetes_deployment.argocd_repo_server_workload]
}
