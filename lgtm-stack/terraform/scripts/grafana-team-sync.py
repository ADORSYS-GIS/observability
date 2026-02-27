"""
grafana-team-sync.py — Dynamic Keycloak → Grafana Multi-Tenant Sync

This script is the single source of truth for tenant lifecycle management.
It runs as a Kubernetes CronJob every 5 minutes.

What it does each run:
  1. Discover all `*-team` groups in Keycloak (no hardcoded tenant list)
  2. For each discovered tenant:
       a. Ensure the Grafana Team exists (create if not)
       b. Ensure the 4 tenant datasources exist (Loki, Mimir, Tempo, Prometheus)
          Each datasource has BasicAuth so non-members get 401 on query
       c. Ensure the tenant dashboard folder exists
       d. Ensure the folder permission is set to team-only
       e. Ensure the tenant password is stored in K8s Secret (stable across runs)
  3. Update the Loki gateway htpasswd K8s Secret with current tenant passwords
  4. Sync users: Keycloak group members → Grafana team members (add/remove)

Adding a new tenant: create a `<name>-team` group in Keycloak. Done.
"""

import os
import sys
import json
import secrets
import string
import logging
import requests

# ─────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)
log = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Configuration from environment variables
# ─────────────────────────────────────────────

def _require(name: str) -> str:
    v = os.getenv(name)
    if not v:
        log.error(f"Required env var {name} is missing.")
        sys.exit(1)
    return v

# Keycloak
KEYCLOAK_URL      = os.getenv("KEYCLOAK_URL", "").rstrip("/")
KEYCLOAK_REALM    = os.getenv("KEYCLOAK_REALM", "")
KEYCLOAK_CLIENT_ID = os.getenv("KEYCLOAK_CLIENT_ID", "admin-cli")
KEYCLOAK_USERNAME = os.getenv("KEYCLOAK_USERNAME", "")
KEYCLOAK_PASSWORD = os.getenv("KEYCLOAK_PASSWORD", "")

if not all([KEYCLOAK_URL, KEYCLOAK_REALM, KEYCLOAK_USERNAME, KEYCLOAK_PASSWORD]):
    log.error("KEYCLOAK_URL, KEYCLOAK_REALM, KEYCLOAK_USERNAME, KEYCLOAK_PASSWORD are all required.")
    sys.exit(1)

# Grafana
GRAFANA_URL           = os.getenv("GRAFANA_URL", "http://monitoring-grafana.observability.svc.cluster.local:80").rstrip("/")
GRAFANA_ADMIN_USER    = "admin"
GRAFANA_ADMIN_PASSWORD = _require("GRAFANA_ADMIN_PASSWORD")

# Backend service URLs (in-cluster defaults)
LOKI_GATEWAY_URL  = os.getenv("LOKI_GATEWAY_URL",  "http://monitoring-loki-gateway.observability.svc.cluster.local:80")
MIMIR_URL         = os.getenv("MIMIR_URL",         "http://monitoring-mimir-nginx.observability.svc.cluster.local:80/prometheus")
TEMPO_URL         = os.getenv("TEMPO_URL",         "http://monitoring-tempo-query-frontend.observability.svc.cluster.local:3200")
PROMETHEUS_URL    = os.getenv("PROMETHEUS_URL",    "http://monitoring-prometheus-server.observability.svc.cluster.local:80")

# Kubernetes
K8S_NAMESPACE              = os.getenv("K8S_NAMESPACE", "observability")
HTPASSWD_SECRET_NAME       = "loki-tenant-htpasswd"
TENANT_PASSWORDS_SECRET    = "grafana-tenant-passwords"

# Group discovery
TENANT_GROUP_SUFFIX = os.getenv("TENANT_GROUP_SUFFIX", "-team")

log.info(f"Configuration: Keycloak realm={KEYCLOAK_REALM}, suffix='{TENANT_GROUP_SUFFIX}'")

# ─────────────────────────────────────────────
# Kubernetes client (in-cluster)
# ─────────────────────────────────────────────

def _get_k8s_client():
    try:
        from kubernetes import client, config
        config.load_incluster_config()
        return client.CoreV1Api()
    except Exception as e:
        log.warning(f"Could not load Kubernetes client: {e}. Secret management will be skipped.")
        return None


def k8s_get_secret_data(v1, secret_name: str) -> dict:
    """Return the decoded data dict of a K8s Secret, or {} if not found."""
    import base64
    try:
        secret = v1.read_namespaced_secret(name=secret_name, namespace=K8S_NAMESPACE)
        data = secret.data or {}
        return {k: base64.b64decode(v).decode() for k, v in data.items()}
    except Exception:
        return {}


def k8s_patch_secret(v1, secret_name: str, new_data: dict):
    """
    Patch (update) an existing K8s Secret's data. Creates it if it does not exist.
    new_data values are plain strings; they will be base64-encoded automatically by K8s.
    """
    from kubernetes import client as k8s_client
    body = k8s_client.V1Secret(
        metadata=k8s_client.V1ObjectMeta(name=secret_name, namespace=K8S_NAMESPACE),
        string_data=new_data,
    )
    try:
        v1.patch_namespaced_secret(name=secret_name, namespace=K8S_NAMESPACE, body=body)
        log.info(f"Patched K8s Secret '{secret_name}'")
    except Exception:
        try:
            v1.create_namespaced_secret(namespace=K8S_NAMESPACE, body=body)
            log.info(f"Created K8s Secret '{secret_name}'")
        except Exception as e:
            log.error(f"Failed to create/patch K8s Secret '{secret_name}': {e}")

# ─────────────────────────────────────────────
# Password helpers
# ─────────────────────────────────────────────

def generate_password(length: int = 32) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def make_htpasswd_entry(username: str, password: str) -> str:
    """Return a bcrypt htpasswd line for the given username/password."""
    try:
        from passlib.hash import bcrypt
        hashed = bcrypt.using(rounds=12).hash(password)
    except ImportError:
        import crypt
        hashed = crypt.crypt(password, crypt.mksalt(crypt.METHOD_SHA512))
    return f"{username}:{hashed}"


def get_or_create_tenant_passwords(v1, tenants: list) -> dict[str, str]:
    """
    Returns a stable {tenant: password} map.
    Loads existing passwords from the K8s Secret and generates new ones for
    any tenants that don't have one yet. Persists back to the Secret.
    """
    if v1 is None:
        # Fallback: generate ephemeral passwords (won't sync to Loki gateway)
        log.warning("No K8s client — generating ephemeral passwords. Gateway htpasswd will NOT be updated.")
        return {t: generate_password() for t in tenants}

    existing = k8s_get_secret_data(v1, TENANT_PASSWORDS_SECRET)
    updated = False
    for tenant in tenants:
        if tenant not in existing:
            existing[tenant] = generate_password()
            log.info(f"Generated new password for tenant '{tenant}'")
            updated = True

    if updated:
        k8s_patch_secret(v1, TENANT_PASSWORDS_SECRET, existing)

    return {t: existing[t] for t in tenants if t in existing}


def update_loki_htpasswd(v1, tenant_passwords: dict):
    """Write the .htpasswd file content to the loki-tenant-htpasswd K8s Secret."""
    if v1 is None:
        log.warning("No K8s client — skipping htpasswd Secret update.")
        return

    lines = []
    for tenant, password in tenant_passwords.items():
        lines.append(make_htpasswd_entry(tenant, password))

    htpasswd_content = "\n".join(lines)
    k8s_patch_secret(v1, HTPASSWD_SECRET_NAME, {".htpasswd": htpasswd_content})
    log.info(f"Updated Loki htpasswd Secret with {len(tenant_passwords)} tenant(s)")

# ─────────────────────────────────────────────
# Keycloak helpers
# ─────────────────────────────────────────────

def get_keycloak_admin_token() -> str:
    """Authenticate with Keycloak and return an admin access token."""
    # Keycloak admin-cli authenticate via master realm first, then fallback
    for realm in ["master", KEYCLOAK_REALM]:
        url = f"{KEYCLOAK_URL}/realms/{realm}/protocol/openid-connect/token"
        try:
            resp = requests.post(url, data={
                "client_id":  KEYCLOAK_CLIENT_ID,
                "username":   KEYCLOAK_USERNAME,
                "password":   KEYCLOAK_PASSWORD,
                "grant_type": "password",
            }, timeout=15)
            resp.raise_for_status()
            log.info(f"Authenticated with Keycloak via /{realm} realm")
            return resp.json()["access_token"]
        except requests.RequestException as e:
            log.warning(f"Keycloak auth via /{realm} realm failed: {e}")

    log.error("All Keycloak authentication attempts failed.")
    sys.exit(1)


def discover_tenant_groups(token: str) -> list[str]:
    """
    Return a list of tenant names discovered from Keycloak groups.
    Groups named `<name>-team` → tenant name `<name>`.
    """
    url = f"{KEYCLOAK_URL}/admin/realms/{KEYCLOAK_REALM}/groups"
    headers = {"Authorization": f"Bearer {token}"}
    # Fetch up to 500 groups; increase max if you have more
    resp = requests.get(url, headers=headers, params={"max": 500}, timeout=15)
    resp.raise_for_status()

    tenants = []
    for group in resp.json():
        name = group.get("name", "")
        if name.endswith(TENANT_GROUP_SUFFIX) and name != TENANT_GROUP_SUFFIX:
            tenant = name[: -len(TENANT_GROUP_SUFFIX)]
            tenants.append(tenant)
            log.info(f"Discovered tenant group: {name} → tenant '{tenant}'")

    if not tenants:
        log.warning(f"No groups with suffix '{TENANT_GROUP_SUFFIX}' found in Keycloak realm '{KEYCLOAK_REALM}'.")
    return tenants


def get_keycloak_group_id(token: str, group_name: str) -> str | None:
    url = f"{KEYCLOAK_URL}/admin/realms/{KEYCLOAK_REALM}/groups"
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(url, headers=headers, params={"search": group_name, "exact": "true"}, timeout=15)
    resp.raise_for_status()
    for group in resp.json():
        if group["name"] == group_name:
            return group["id"]
    return None


def get_keycloak_group_members(token: str, group_id: str) -> list[str]:
    """Return list of email addresses in the given group."""
    url = f"{KEYCLOAK_URL}/admin/realms/{KEYCLOAK_REALM}/groups/{group_id}/members"
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(url, headers=headers, params={"max": -1}, timeout=15)
    resp.raise_for_status()
    return [m["email"] for m in resp.json() if "email" in m]

# ─────────────────────────────────────────────
# Grafana helpers
# ─────────────────────────────────────────────

GRAFANA_AUTH = None  # set after config validation


def _grafana_auth():
    return (GRAFANA_ADMIN_USER, GRAFANA_ADMIN_PASSWORD)


def grafana_get(path: str, params: dict = None):
    resp = requests.get(f"{GRAFANA_URL}{path}", auth=_grafana_auth(), params=params, timeout=15)
    resp.raise_for_status()
    return resp.json()


def grafana_post(path: str, payload: dict):
    resp = requests.post(f"{GRAFANA_URL}{path}", auth=_grafana_auth(), json=payload, timeout=15)
    return resp


def grafana_put(path: str, payload: dict):
    resp = requests.put(f"{GRAFANA_URL}{path}", auth=_grafana_auth(), json=payload, timeout=15)
    return resp


# ── Teams ──────────────────────────────────────────────────────────────────────

def ensure_grafana_team(tenant: str) -> int:
    """Return the Grafana team ID for `<tenant>-team`, creating it if needed."""
    team_name = f"{tenant}{TENANT_GROUP_SUFFIX}"
    results = grafana_get("/api/teams/search", {"name": team_name}).get("teams", [])
    for team in results:
        if team["name"] == team_name:
            log.info(f"Team '{team_name}' already exists (id={team['id']})")
            return team["id"]

    resp = grafana_post("/api/teams", {"name": team_name})
    if resp.status_code in (200, 409):
        # 409 = already exists (race condition)
        results = grafana_get("/api/teams/search", {"name": team_name}).get("teams", [])
        for team in results:
            if team["name"] == team_name:
                return team["id"]
    resp.raise_for_status()
    team_id = resp.json()["teamId"]
    log.info(f"Created Grafana Team '{team_name}' (id={team_id})")
    return team_id


# ── Datasources ────────────────────────────────────────────────────────────────

def _datasource_exists(name: str) -> bool:
    try:
        grafana_get(f"/api/datasources/name/{requests.utils.quote(name)}")
        return True
    except requests.HTTPError as e:
        if e.response.status_code == 404:
            return False
        raise


def _create_datasource(payload: dict):
    resp = grafana_post("/api/datasources", payload)
    if resp.status_code == 409:
        log.info(f"Datasource '{payload['name']}' already exists (409)")
        return
    if not resp.ok:
        log.error(f"Failed to create datasource '{payload['name']}': {resp.status_code} {resp.text}")
        return
    log.info(f"Created datasource '{payload['name']}'")


def ensure_grafana_datasources(tenant: str, password: str):
    """Create all 4 tenant datasources if they don't exist."""
    title = tenant.title()

    # Shared basicAuth config
    def ds_base(name: str, ds_type: str, url: str, json_data: dict) -> dict:
        return {
            "name":           name,
            "type":           ds_type,
            "url":            url,
            "access":         "proxy",
            "basicAuth":      True,
            "basicAuthUser":  tenant,
            "secureJsonData": {
                "basicAuthPassword": password,
                "httpHeaderValue1":  tenant,   # X-Scope-OrgID value (stored securely)
            },
            "jsonData": {
                **json_data,
                "httpHeaderName1": "X-Scope-OrgID",
            },
        }

    datasources = [
        ds_base(f"{title}-Loki",       "loki",       LOKI_GATEWAY_URL, {"maxLines": 1000}),
        ds_base(f"{title}-Mimir",      "prometheus", MIMIR_URL,        {"httpMethod": "POST", "timeInterval": "15s"}),
        ds_base(f"{title}-Prometheus", "prometheus", PROMETHEUS_URL,   {"httpMethod": "POST", "timeInterval": "15s"}),
        ds_base(f"{title}-Tempo",      "tempo",      TEMPO_URL,        {"httpMethod": "GET"}),
    ]

    for ds in datasources:
        if not _datasource_exists(ds["name"]):
            _create_datasource(ds)
        else:
            log.info(f"Datasource '{ds['name']}' already exists")


# ── Folders ────────────────────────────────────────────────────────────────────

def ensure_grafana_folder(tenant: str) -> str:
    """Return folder UID for `<Tenant> Dashboards`, creating if needed."""
    folder_title = f"{tenant.title()} Dashboards"
    folder_uid   = f"{tenant}-dashboards"

    folders = grafana_get("/api/folders")
    for folder in folders:
        if folder.get("uid") == folder_uid or folder.get("title") == folder_title:
            log.info(f"Folder '{folder_title}' already exists (uid={folder['uid']})")
            return folder["uid"]

    resp = grafana_post("/api/folders", {"uid": folder_uid, "title": folder_title})
    if resp.status_code == 409:
        log.info(f"Folder '{folder_title}' already exists (409)")
        return folder_uid
    resp.raise_for_status()
    log.info(f"Created folder '{folder_title}' (uid={folder_uid})")
    return folder_uid


def ensure_folder_permission(folder_uid: str, team_id: int):
    """Set folder permissions so only the tenant team can see/edit it."""
    path = f"/api/folders/{folder_uid}/permissions"
    payload = {
        "items": [
            {
                "teamId":     team_id,
                "permission": 2,  # 1=View 2=Edit 4=Admin
            }
        ]
    }
    resp = grafana_post(path, payload)
    if not resp.ok:
        # Some Grafana versions use PUT
        resp = grafana_put(path, payload)
    if resp.ok:
        log.info(f"Set folder permission for team_id={team_id} on folder '{folder_uid}'")
    else:
        log.warning(f"Could not set folder permission: {resp.status_code} {resp.text}")


# ── Users ──────────────────────────────────────────────────────────────────────

def get_grafana_user_id_by_email(email: str) -> int | None:
    try:
        data = grafana_get("/api/users/lookup", {"loginOrEmail": email})
        return data["id"]
    except requests.HTTPError as e:
        if e.response.status_code == 404:
            return None
        raise
    except Exception:
        return None


def get_grafana_team_members(team_id: int) -> list[int]:
    members = grafana_get(f"/api/teams/{team_id}/members")
    return [m["userId"] for m in members]


def add_user_to_grafana_team(team_id: int, user_id: int):
    resp = grafana_post(f"/api/teams/{team_id}/members", {"userId": user_id})
    if resp.status_code == 409:
        return  # already a member
    resp.raise_for_status()


def remove_user_from_grafana_team(team_id: int, user_id: int):
    resp = requests.delete(
        f"{GRAFANA_URL}/api/teams/{team_id}/members/{user_id}",
        auth=_grafana_auth(), timeout=15,
    )
    resp.raise_for_status()


def get_grafana_admin_user_id() -> int | None:
    """Get the local admin user ID so we never accidentally remove it from a team."""
    for lookup in ["admin@localhost", GRAFANA_ADMIN_USER]:
        uid = get_grafana_user_id_by_email(lookup)
        if uid:
            return uid
    return None


# ─────────────────────────────────────────────
# Main sync logic
# ─────────────────────────────────────────────

def provision_tenant(tenant: str, password: str):
    """Idempotently create/ensure all Grafana resources for a tenant."""
    log.info(f"=== Provisioning resources for tenant '{tenant}' ===")
    team_id    = ensure_grafana_team(tenant)
    ensure_grafana_datasources(tenant, password)
    folder_uid = ensure_grafana_folder(tenant)
    ensure_folder_permission(folder_uid, team_id)
    return team_id


def sync_tenant_users(tenant: str, team_id: int, kc_token: str):
    """Sync Keycloak group members into the Grafana team."""
    team_name = f"{tenant}{TENANT_GROUP_SUFFIX}"
    log.info(f"--- Syncing users for '{team_name}' ---")

    # Get Keycloak group members
    kc_group_id = get_keycloak_group_id(kc_token, team_name)
    if not kc_group_id:
        log.warning(f"Keycloak group '{team_name}' not found — skipping user sync.")
        return

    kc_emails = get_keycloak_group_members(kc_token, kc_group_id)
    log.info(f"Keycloak group '{team_name}' has {len(kc_emails)} member(s): {kc_emails}")

    # Build desired Grafana user IDs (only users who have already logged in once)
    admin_id = get_grafana_admin_user_id()
    desired_ids = []
    for email in kc_emails:
        uid = get_grafana_user_id_by_email(email)
        if uid:
            desired_ids.append(uid)
        else:
            log.info(f"User {email} has not logged into Grafana yet — will be added on first login.")

    current_ids = get_grafana_team_members(team_id)

    # Add missing members
    for uid in desired_ids:
        if uid not in current_ids:
            log.info(f"Adding user {uid} to team '{team_name}'")
            try:
                add_user_to_grafana_team(team_id, uid)
            except Exception as e:
                log.error(f"Failed to add user {uid}: {e}")

    # Remove stale members (never remove local admin)
    for uid in current_ids:
        if uid == admin_id or uid == 1:
            continue
        if uid not in desired_ids:
            log.info(f"Removing user {uid} from team '{team_name}' (no longer in Keycloak group)")
            try:
                remove_user_from_grafana_team(team_id, uid)
            except Exception as e:
                log.error(f"Failed to remove user {uid}: {e}")

    log.info(f"User sync complete for '{team_name}'")


def main():
    log.info("=" * 60)
    log.info("Starting Dynamic Keycloak → Grafana Sync Job")
    log.info("=" * 60)

    # Authenticate with Keycloak
    kc_token = get_keycloak_admin_token()

    # Step 1: Discover all tenant groups from Keycloak
    tenants = discover_tenant_groups(kc_token)
    if not tenants:
        log.info("No tenant groups discovered. Nothing to do.")
        return

    log.info(f"Discovered {len(tenants)} tenant(s): {tenants}")

    # Step 2: Get or create stable per-tenant passwords (from K8s Secret)
    v1 = _get_k8s_client()
    tenant_passwords = get_or_create_tenant_passwords(v1, tenants)

    # Step 3: Provision Grafana resources + sync users for each tenant
    team_ids = {}
    for tenant in tenants:
        try:
            password = tenant_passwords.get(tenant)
            if not password:
                log.error(f"No password available for tenant '{tenant}' — skipping.")
                continue
            team_id = provision_tenant(tenant, password)
            team_ids[tenant] = team_id
        except Exception as e:
            log.error(f"Failed to provision resources for tenant '{tenant}': {e}", exc_info=True)

    for tenant, team_id in team_ids.items():
        try:
            sync_tenant_users(tenant, team_id, kc_token)
        except Exception as e:
            log.error(f"Failed to sync users for tenant '{tenant}': {e}", exc_info=True)

    # Step 4: Update Loki gateway htpasswd (only for successfully provisioned tenants)
    active_passwords = {t: tenant_passwords[t] for t in team_ids if t in tenant_passwords}
    update_loki_htpasswd(v1, active_passwords)

    log.info("=" * 60)
    log.info("Sync Job Completed Successfully")
    log.info("=" * 60)


if __name__ == "__main__":
    main()
