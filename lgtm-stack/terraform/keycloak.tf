# ============================================================
# Keycloak Terraform Configuration — Grafana SSO
# ============================================================
# This file automates the full Keycloak-side setup inside the
# existing realm on <keycloak-domain> (shared with Auth/SSO).
#
# What it creates:
#   1. OpenID Connect client: grafana-oauth
#   2. Grafana role groups: grafana-admins, grafana-editors, grafana-viewers
#   3. Realm roles: admin, editor, viewer (mapped to groups)
#   4. Protocol mappers: realm roles + groups into JWT
#   5. A dedicated Grafana admin user (the one set via var.grafana_keycloak_user)
#   6. [MULTI-TENANCY] Tenant groups: one "<tenant>-team" per entry in var.tenants
#
# Role vs Team — they are completely independent:
#   - Role (grafana-admins/editors/viewers) = WHAT the user can DO in Grafana
#     (create dashboards, change settings, view-only, etc.)
#   - Team (<tenant>-team) = WHAT DATA the user can SEE
#     (only the Loki/Mimir/Tempo data for their tenant)
#
#   A user can be a "grafana-editor" AND belong to "webank-team".
#   That means: can create dashboards, but only with webank data.
#
# Access control:
#   - Only users in a grafana-* group can access Grafana
#   - Users NOT in any group are BLOCKED (strict mode)
#   - Group membership determines Grafana role (Admin/Editor/Viewer)
#   - Team membership determines which tenant data they see
# ============================================================

# ---- OPENID Connect Client -----------------------------------

# ---- OpenID Connect Client -----------------------------------

resource "keycloak_openid_client" "grafana" {
  realm_id  = var.keycloak_realm
  client_id = "grafana-oauth"
  name      = "Grafana LGTM Monitoring"
  enabled   = true

  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = true

  root_url  = "https://grafana.${var.monitoring_domain}"
  base_url  = "https://grafana.${var.monitoring_domain}"
  admin_url = "https://grafana.${var.monitoring_domain}"

  valid_redirect_uris = [
    "https://grafana.${var.monitoring_domain}/login/generic_oauth",
    # Required for KC 18+ post-logout redirect to function correctly.
    # Must perfectly match the post_logout_redirect_uri parameter sent by Grafana.
    "https://grafana.${var.monitoring_domain}/login"
  ]

  web_origins = [
    "https://grafana.${var.monitoring_domain}"
  ]
}

# ---- Keycloak Groups -----------------------------------------
# Groups provide clean access control in a shared realm.
# Users of NetBird won't have Grafana access unless explicitly
# added to one of these groups.
#
#   grafana-admins  → Grafana Admin  (full control)
#   grafana-editors → Grafana Editor (create/edit dashboards)
#   grafana-viewers → Grafana Viewer (read-only)

resource "keycloak_group" "grafana_admins" {
  realm_id = var.keycloak_realm
  name     = "grafana-admins"
}

resource "keycloak_group" "grafana_editors" {
  realm_id = var.keycloak_realm
  name     = "grafana-editors"
}

resource "keycloak_group" "grafana_viewers" {
  realm_id = var.keycloak_realm
  name     = "grafana-viewers"
}

# ---- Realm Roles ---------------------------------------------

resource "keycloak_role" "grafana_admin" {
  realm_id    = var.keycloak_realm
  name        = "grafana-admin"
  description = "Grafana Admin — full access to dashboards and settings"
}

resource "keycloak_role" "grafana_editor" {
  realm_id    = var.keycloak_realm
  name        = "grafana-editor"
  description = "Grafana Editor — can create and edit dashboards"
}

resource "keycloak_role" "grafana_viewer" {
  realm_id    = var.keycloak_realm
  name        = "grafana-viewer"
  description = "Grafana Viewer — read-only access to dashboards"
}

# ---- Group → Role Mappings -----------------------------------
# Everyone in grafana-admins automatically gets the grafana-admin role.

resource "keycloak_group_roles" "grafana_admin_roles" {
  realm_id = var.keycloak_realm
  group_id = keycloak_group.grafana_admins.id
  role_ids = [keycloak_role.grafana_admin.id]
}

resource "keycloak_group_roles" "grafana_editor_roles" {
  realm_id = var.keycloak_realm
  group_id = keycloak_group.grafana_editors.id
  role_ids = [keycloak_role.grafana_editor.id]
}

resource "keycloak_group_roles" "grafana_viewer_roles" {
  realm_id = var.keycloak_realm
  group_id = keycloak_group.grafana_viewers.id
  role_ids = [keycloak_role.grafana_viewer.id]
}

# ---- Protocol Mappers ----------------------------------------

# Mapper 1: Realm Roles → "roles" claim in JWT
# Grafana uses this for role_attribute_path (Admin/Editor/Viewer mapping)
resource "keycloak_openid_user_realm_role_protocol_mapper" "grafana_roles" {
  realm_id  = var.keycloak_realm
  client_id = keycloak_openid_client.grafana.id
  name      = "grafana-roles-mapper"

  claim_name      = "roles"
  multivalued     = true
  add_to_id_token = true
  add_to_userinfo = true
}

# Mapper 2: Group Membership → "groups" claim in JWT
# Grafana uses this for allowed_groups (strict access control)
resource "keycloak_openid_group_membership_protocol_mapper" "grafana_groups" {
  realm_id  = var.keycloak_realm
  client_id = keycloak_openid_client.grafana.id
  name      = "grafana-groups-mapper"

  claim_name      = "groups"
  full_path       = false
  add_to_id_token = true
  add_to_userinfo = true
}

# ---- Dedicated Grafana Admin User ----------------------------
# A separate user from the NetBird admin user, to avoid
# confusion and credential sharing between services.

resource "keycloak_user" "grafana_admin" {
  realm_id = var.keycloak_realm
  username = var.grafana_keycloak_user
  enabled  = true

  first_name = "Grafana"
  last_name  = "Admin"
  email      = var.grafana_keycloak_email

  initial_password {
    value     = var.grafana_keycloak_password
    temporary = false
  }

  lifecycle {
    ignore_changes = [
      username
    ]
  }
}

# Add the dedicated user to the grafana-admins and webank-team groups
# This gives the user full Grafana Admin rights (can manage users, settings, etc.)
# while still being a member of webank-team for organizational purposes.
# Note: Grafana Admins bypass datasource and folder permissions, so they can see
# all tenants' data. If you want to restrict them to only webank data, use
# grafana-editors instead.
resource "keycloak_user_groups" "grafana_admin_membership" {
  realm_id = var.keycloak_realm
  user_id  = keycloak_user.grafana_admin.id

  group_ids = [
    keycloak_group.grafana_admins.id,
    keycloak_group.tenant_teams["webank"].id
  ]
}
