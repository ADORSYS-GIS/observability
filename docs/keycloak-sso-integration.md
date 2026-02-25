# Keycloak SSO Integration for LGTM Stack

## 1. Architectural Overview
The LGTM stack (Loki, Grafana, Tempo, Mimir) has been configured to use **Keycloak** as the strict single source of truth for authentication and authorization. 

Local basic authentication (username/password) has been completely disabled in Grafana. All users attempting to access `https://grafana.<domain>` are automatically redirected to the Keycloak login page (via OIDC RP-Initiated login).

Access is strictly governed by **Keycloak Groups**. If a user in the Keycloak realm is not a member of an authorized `grafana-*` group, they are fundamentally blocked from accessing the LGTM stack.

## 2. Infrastructure as Code (Terraform)
The entire Keycloak integration is automated via Terraform in `terraform/keycloak.tf` using the `mrparkers/keycloak` provider.

### The OIDC Client (`grafana-oauth`)
A Confidential OpenID Connect client is created specifically for Grafana.
- **Redirect URIs:** Meticulously configured to allow the standard `/login/generic_oauth` callback, as well as explicitly authorizing the `/login` path to satisfy Keycloak 18+ strict post-logout redirect security policies.

### Group & Role Provisioning
Terraform automates the creation of three dedicated groups inside the target Keycloak realm:
1. `grafana-admins`
2. `grafana-editors`
3. `grafana-viewers`

Simultaneously, Terraform creates three Realm Roles (`grafana-admin`, `grafana-editor`, `grafana-viewer`) and explicitly maps them to their respective groups. *Any user added to a group automatically inherits the underlying role.*

### Protocol Mappers (JWT Injection)
To pass authorization data to Grafana, Terraform attaches two Protocol Mappers to the client:
1. **Roles Mapper:** Injects the user's realm roles into the JWT token under the `roles` claim.
2. **Groups Mapper:** Injects the user's group memberships into the JWT under the `groups` claim.

### Dedicated Admin User
To prevent credential sharing and maintain clean security boundaries, a dedicated Grafana admin user is generated in Keycloak and automatically joined to the `grafana-admins` group.

## 3. Grafana Authentication Configuration
Grafana's configuration (`terraform/values/grafana-values.yaml`) is hardened to enforce the Keycloak SSO policies.

### Strict Role Mapping
Grafana evaluates the `roles` array inside the incoming JWT using JMESPath logic:
```yaml
role_attribute_path: "contains(roles[*], 'grafana-admin') && 'Admin' || contains(roles[*], 'grafana-editor') && 'Editor' || contains(roles[*], 'grafana-viewer') && 'Viewer'"
```
Because `role_attribute_strict: true` is enabled, any user who manages to log in but possesses none of these roles is immediately rejected by Grafana.

### Group-Based Access Control (GBAC)
Grafana evaluates the `groups` array against the `allowed_groups` list (`grafana-admins grafana-editors grafana-viewers`). This guarantees that only authorized teams can initiate a session.

### Security Configurations
- **Client Secret:** The OAuth client secret is never stored in plaintext within the `grafana.ini`. It is securely passed as an environment variable (`GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET`) to satisfy Helm validation rules.
- **Admin Recovery (`oauth_allow_insecure_email_lookup`):** This critical setting ensures the Keycloak `admin` account can successfully map to the built-in Grafana `admin` account via email, bypassing the default security block that otherwise results in a "User Sync Failed" error.

## 4. User Management Workflow (IMPORTANT)

> [!WARNING]
> **Users CANNOT be invited or managed from within the Grafana UI.**

Because Keycloak is the strict source of truth, any roles assigned manually within Grafana will be instantly overwritten and downgraded the next time the user logs in.

**To grant a user access to Grafana:**
1. A System Administrator must log into the Keycloak Admin Console.
2. Navigate to the target Realm (e.g., `<realm>`).
3. Create the user or locate an existing user.
4. Navigate to the user's **Groups** tab.
5. Join the user to either `grafana-admins`, `grafana-editors`, or `grafana-viewers`.

Upon their next login, Grafana will automatically sync the user and grant them the appropriate permissions.

## 5. Required CI/CD Secrets
For this configuration to deploy successfully via GitHub Actions, the following secrets must be present in the repository:

1. `KEYCLOAK_URL` (e.g., `https://<keycloak-domain>/<realm>.com`)
2. `KEYCLOAK_REALM` (e.g., `<realm>`)
3. `KEYCLOAK_ADMIN_USER` 
4. `KEYCLOAK_ADMIN_PASSWORD` 
5. `GRAFANA_KEYCLOAK_USER` (The dedicated Grafana admin username)
6. `GRAFANA_KEYCLOAK_EMAIL`
7. `GRAFANA_KEYCLOAK_PASSWORD`
