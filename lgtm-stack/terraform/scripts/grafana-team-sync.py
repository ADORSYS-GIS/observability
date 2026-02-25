import os
import sys
import time
import requests
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# --- Configuration from Environment Variables ---

# Keycloak settings
KEYCLOAK_URL = os.getenv("KEYCLOAK_URL")
if not KEYCLOAK_URL:
    logging.error("KEYCLOAK_URL is required.")
    sys.exit(1)
if KEYCLOAK_URL.endswith('/'):
    KEYCLOAK_URL = KEYCLOAK_URL[:-1]

KEYCLOAK_REALM = os.getenv("KEYCLOAK_REALM")
KEYCLOAK_CLIENT_ID = os.getenv("KEYCLOAK_CLIENT_ID", "admin-cli")
KEYCLOAK_USERNAME = os.getenv("KEYCLOAK_USERNAME")
KEYCLOAK_PASSWORD = os.getenv("KEYCLOAK_PASSWORD")

if not all([KEYCLOAK_REALM, KEYCLOAK_USERNAME, KEYCLOAK_PASSWORD]):
    logging.error("KEYCLOAK_REALM, KEYCLOAK_USERNAME, and KEYCLOAK_PASSWORD are required.")
    sys.exit(1)

# Grafana settings
GRAFANA_URL = os.getenv("GRAFANA_URL", "http://monitoring-grafana.observability.svc.cluster.local:80")
if GRAFANA_URL.endswith('/'):
    GRAFANA_URL = GRAFANA_URL[:-1]
    
GRAFANA_ADMIN_USER = "admin"
GRAFANA_ADMIN_PASSWORD = os.getenv("GRAFANA_ADMIN_PASSWORD")

if not GRAFANA_ADMIN_PASSWORD:
    logging.error("GRAFANA_ADMIN_PASSWORD is required.")
    sys.exit(1)

# Tenants configuration (Comma-separated list, e.g., "webank,azamra")
TENANTS_STR = os.getenv("TENANTS", "webank")
TENANTS = [t.strip() for t in TENANTS_STR.split(",") if t.strip()]

logging.info(f"Loaded configuration: Realm: {KEYCLOAK_REALM}, Tenants: {TENANTS}")


# --- Helper Functions ---

def get_keycloak_admin_token() -> str:
    """Authenticates with Keycloak and returns the admin access token."""
    url = f"{KEYCLOAK_URL}/realms/master/protocol/openid-connect/token"
    payload = {
        'client_id': KEYCLOAK_CLIENT_ID,
        'username': KEYCLOAK_USERNAME,
        'password': KEYCLOAK_PASSWORD,
        'grant_type': 'password'
    }
    
    # Try the realm specific token endpoint if master fails, but standard admin-cli uses master
    try:
        response = requests.post(url, data=payload)
        response.raise_for_status()
        return response.json()['access_token']
    except requests.exceptions.RequestException as e:
        logging.error(f"Failed to get Keycloak token from master realm: {e}")
        # Fallback to the specific realm
        url = f"{KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/token"
        try:
             response = requests.post(url, data=payload)
             response.raise_for_status()
             return response.json()['access_token']
        except requests.exceptions.RequestException as e2:
             logging.error(f"Failed to get Keycloak token from {KEYCLOAK_REALM} realm: {e2}")
             sys.exit(1)

def get_keycloak_group_id(token: str, group_name: str) -> str:
    """Given a group name (e.g., 'webank-team'), returns its Keycloak ID."""
    url = f"{KEYCLOAK_URL}/admin/realms/{KEYCLOAK_REALM}/groups"
    headers = {"Authorization": f"Bearer {token}"}
    params = {"search": group_name, "exact": "true"}
    
    response = requests.get(url, headers=headers, params=params)
    response.raise_for_status()
    groups = response.json()
    
    for group in groups:
        if group['name'] == group_name:
            return group['id']
            
    return None

def get_keycloak_group_members(token: str, group_id: str) -> list:
    """Returns a list of email addresses for all members of the given Keycloak group ID."""
    url = f"{KEYCLOAK_URL}/admin/realms/{KEYCLOAK_REALM}/groups/{group_id}/members"
    headers = {"Authorization": f"Bearer {token}"}
    
    # max = -1 gets all members
    params = {"max": -1} 
    
    response = requests.get(url, headers=headers, params=params)
    response.raise_for_status()
    members = response.json()
    
    emails = []
    for member in members:
        if 'email' in member:
            emails.append(member['email'])
            
    return emails

def get_grafana_team_id(team_name: str) -> int:
    """Given a team name (e.g., 'webank-team'), returns its Grafana ID."""
    url = f"{GRAFANA_URL}/api/teams/search"
    auth = (GRAFANA_ADMIN_USER, GRAFANA_ADMIN_PASSWORD)
    params = {"name": team_name}
    
    response = requests.get(url, auth=auth, params=params)
    response.raise_for_status()
    results = response.json().get('teams', [])
    
    for team in results:
        if team['name'] == team_name:
            return team['id']
            
    return None

def get_grafana_user_id_by_email(email: str) -> int:
    """Looks up a Grafana user ID by their email address."""
    url = f"{GRAFANA_URL}/api/users/lookup"
    auth = (GRAFANA_ADMIN_USER, GRAFANA_ADMIN_PASSWORD)
    params = {"loginOrEmail": email}
    
    try:
        response = requests.get(url, auth=auth, params=params)
        if response.status_code == 404:
            return None # User hasn't logged into Grafana yet
            
        response.raise_for_status()
        return response.json()['id']
    except requests.exceptions.RequestException:
        return None

def get_grafana_team_members(team_id: int) -> list:
    """Returns a list of current user IDs in the given Grafana team."""
    url = f"{GRAFANA_URL}/api/teams/{team_id}/members"
    auth = (GRAFANA_ADMIN_USER, GRAFANA_ADMIN_PASSWORD)
    
    response = requests.get(url, auth=auth)
    response.raise_for_status()
    members = response.json()
    
    return [member['userId'] for member in members]

def add_user_to_grafana_team(team_id: int, user_id: int):
    """Adds a user to a Grafana team."""
    url = f"{GRAFANA_URL}/api/teams/{team_id}/members"
    auth = (GRAFANA_ADMIN_USER, GRAFANA_ADMIN_PASSWORD)
    payload = {"userId": user_id}
    
    response = requests.post(url, auth=auth, json=payload)
    response.raise_for_status()

def remove_user_from_grafana_team(team_id: int, user_id: int):
    """Removes a user from a Grafana team."""
    url = f"{GRAFANA_URL}/api/teams/{team_id}/members/{user_id}"
    auth = (GRAFANA_ADMIN_USER, GRAFANA_ADMIN_PASSWORD)
    
    response = requests.delete(url, auth=auth)
    response.raise_for_status()

# --- Main Sync Logic ---

def sync_tenant(tenant: str, kc_token: str):
    team_name = f"{tenant}-team"
    logging.info(f"--- Syncing {team_name} ---")
    
    # 1. Get Keycloak Group Members
    kc_group_id = get_keycloak_group_id(kc_token, team_name)
    if not kc_group_id:
        logging.warning(f"Keycloak group '{team_name}' not found. Skipping.")
        return
        
    kc_emails = get_keycloak_group_members(kc_token, kc_group_id)
    logging.info(f"Keycloak members for '{team_name}': {kc_emails}")
    
    # 2. Get Grafana Team ID
    grafana_team_id = get_grafana_team_id(team_name)
    if not grafana_team_id:
        logging.warning(f"Grafana team '{team_name}' not found. Skipping. (Is Terraform apply done?)")
        return
        
    # 3. Get Current Grafana Team Members
    grafana_current_user_ids = get_grafana_team_members(grafana_team_id)
    
    # 4. Determine Desired State
    desired_grafana_user_ids = []
    
    # We must explicitly query Grafana to find the ID of the global admin
    # to ensure we NEVER delete them from ANY team.
    global_admin_id = get_grafana_user_id_by_email("admin@localhost") # Typical local admin email
    if not global_admin_id:
         # Fallback search locally
         global_admin_id = get_grafana_user_id_by_email(GRAFANA_ADMIN_USER)
    
    for email in kc_emails:
        user_id = get_grafana_user_id_by_email(email)
        if user_id:
            desired_grafana_user_ids.append(user_id)
        else:
            logging.info(f"User {email} is in Keycloak '{team_name}' group but has never logged into Grafana. Skipping until their first login.")

    # 5. Apply Changes (Additions)
    for requested_user_id in desired_grafana_user_ids:
        if requested_user_id not in grafana_current_user_ids:
            logging.info(f"Adding UserId {requested_user_id} to Grafana Team '{team_name}'")
            try:
                add_user_to_grafana_team(grafana_team_id, requested_user_id)
            except Exception as e:
                logging.error(f"Failed to add UserId {requested_user_id}: {e}")

    # 6. Apply Changes (Removals) - Strict Sync
    for current_user_id in grafana_current_user_ids:
        # Prevent removing local admins from the Grafana UI
        if current_user_id == global_admin_id or current_user_id == 1:
             logging.info(f"Skipping Team Removal for Local Admin User (UserId {current_user_id})")
             continue
             
        if current_user_id not in desired_grafana_user_ids:
            logging.info(f"Removing UserId {current_user_id} from Grafana Team '{team_name}' (No longer in Keycloak Group)")
            try:
                remove_user_from_grafana_team(grafana_team_id, current_user_id)
            except Exception as e:
                logging.error(f"Failed to remove UserId {current_user_id}: {e}")
                
    logging.info(f"Finished syncing {team_name}.")

def main():
    logging.info("Starting Keycloak-to-Grafana Team Sync Job...")
    kc_token = get_keycloak_admin_token()
    
    for tenant in TENANTS:
        try:
             sync_tenant(tenant, kc_token)
        except Exception as e:
             logging.error(f"Error syncing tenant '{tenant}': {e}")
             
    logging.info("Sync Job Completed Successfully.")

if __name__ == "__main__":
    main()
