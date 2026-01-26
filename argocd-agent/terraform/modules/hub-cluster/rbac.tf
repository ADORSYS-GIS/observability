# =============================================================================
# RBAC FOR AGENT NAMESPACES
# =============================================================================
# Creates Role and RoleBinding for argocd-server ServiceAccount to manage
# Applications in agent namespaces (required for UI-based app creation)
# =============================================================================

resource "kubernetes_role" "argocd_server_app_manager" {
  for_each = var.workload_clusters
  provider = kubernetes

  metadata {
    name      = "argocd-server-app-manager"
    namespace = each.key
  }

  rule {
    api_groups = ["argoproj.io"]
    resources  = ["applications", "applicationsets", "appprojects"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  depends_on = [kubernetes_namespace.spoke_agent_managed_namespace]
}

resource "kubernetes_role_binding" "argocd_server_app_manager" {
  for_each = var.workload_clusters
  provider = kubernetes

  metadata {
    name      = "argocd-server-app-manager"
    namespace = each.key
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "argocd-server-app-manager"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "argocd-server"
    namespace = var.hub_namespace
  }

  depends_on = [kubernetes_role.argocd_server_app_manager]
}
