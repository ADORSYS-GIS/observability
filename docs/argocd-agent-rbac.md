# ArgoCD Agent - RBAC & SSO

Role-Based Access Control and Keycloak Single Sign-On integration for ArgoCD Hub-and-Spoke architecture.

---

## Keycloak Integration

### Prerequisites

1. Keycloak instance running and accessible from Hub cluster
2. Admin credentials for client/user creation
3. ArgoCD UI accessible via HTTPS with hostname

### Configuration

Enable in `terraform.tfvars`:

```hcl
enable_keycloak = true

# Keycloak server
keycloak_url      = "https://keycloak.example.com"
keycloak_realm    = "argocd"
keycloak_user     = "admin"
keycloak_password = var.keycloak_password  # Use TF_VAR_keycloak_password

# ArgoCD
argocd_url         = "https://argocd.example.com"
keycloak_client_id = "argocd"

# Authentication method
keycloak_enable_pkce = false  # true enables CLI --sso login
```

**Security**: Never commit `keycloak_password`. Use environment variable:

```bash
export TF_VAR_keycloak_password="your-admin-password"
terraform apply
```

### What Terraform Creates

When `enable_keycloak = true`:

1. Keycloak Realm: `argocd`
2. Keycloak Client: `argocd` with redirect URIs
3. Default Groups: `ArgoCDAdmins`, `ArgoCDDevelopers`, `ArgoCDViewers`
4. ArgoCD OIDC configuration
5. RBAC policies

---

## Default RBAC Groups

| Group | Permissions | Use Cases |
|-------|-------------|-----------|
| **ArgoCDAdmins** | Full admin access<br>Create/delete apps, projects, repos<br>Modify cluster settings<br>Manage RBAC | Platform admins<br>DevOps leads<br>Incident responders |
| **ArgoCDDevelopers** | Create/update/sync apps<br>View status and logs<br>Access repos<br>**Cannot** delete projects or modify cluster | App developers<br>Team members<br>CI/CD pipelines |
| **ArgoCDViewers** | Read-only access<br>View apps, projects, repos<br>**Cannot** sync or modify | Security auditors<br>Management<br>Monitoring systems |

**RBAC Policy**:
```csv
# Admins
g, ArgoCDAdmins, role:admin

# Developers
p, role:developer, applications, *, */*, allow
p, role:developer, repositories, get, *, allow
p, role:developer, clusters, get, *, allow
p, role:developer, projects, get, *, allow
p, role:developer, logs, get, *, allow
p, role:developer, exec, create, */*, deny
g, ArgoCDDevelopers, role:developer

# Viewers
p, role:viewer, applications, get, */*, allow
p, role:viewer, repositories, get, *, allow
p, role:viewer, clusters, get, *, allow
p, role:viewer, projects, get, *, allow
g, ArgoCDViewers, role:viewer
```

---

## Adding Users

### Via Keycloak UI

1. Navigate to `https://keycloak.example.com/admin`
2. Select realm: `argocd`
3. **Users** → **Add User**
4. Fill details (username, email, name)
5. **Save**
6. **Credentials** tab → **Set Password** → **Uncheck "Temporary"** (critical for OIDC)
7. **Groups** tab → **Join Group** → Select `ArgoCDDevelopers`

---

## Custom RBAC Examples

### Team-Specific Namespace Access

**Requirement**: Team Alpha only accesses `team-alpha` namespace.

Edit `argocd-rbac-cm` ConfigMap:

```yaml
data:
  policy.csv: |
    # Default policies
    g, ArgoCDAdmins, role:admin
    g, ArgoCDDevelopers, role:developer
    g, ArgoCDViewers, role:viewer
    
    # Custom: Team Alpha
    p, role:team-alpha, applications, *, team-alpha/*, allow
    p, role:team-alpha, applications, get, */*, allow
    p, role:team-alpha, repositories, get, *, allow
    g, TeamAlpha, role:team-alpha
```

### Multi-Tenant Agent Namespaces

**Architecture**:
```
Hub Cluster:
├── agent-team-alpha/   # Team Alpha's applications
├── agent-team-beta/    # Team Beta's applications
└── agent-team-gamma/   # Team Gamma's applications
```

**RBAC Policy**:
```csv
# Team Alpha: Full access to their namespace only
p, role:team-alpha-admin, applications, *, agent-team-alpha/*, allow
p, role:team-alpha-admin, projects, get, *, allow
g, TeamAlphaAdmins, role:team-alpha-admin

# Team Beta: Full access to their namespace only
p, role:team-beta-admin, applications, *, agent-team-beta/*, allow
p, role:team-beta-admin, projects, get, *, allow
g, TeamBetaAdmins, role:team-beta-admin
```

---

## CLI SSO Login

### PKCE Authentication (Recommended)

**Configuration**:
```hcl
keycloak_enable_pkce = true
```

**Benefits**: No client secret needed, more secure for CLI

**Login**:
```bash
argocd login argocd.example.com --sso
# Browser opens for Keycloak authentication
```

### Client Credentials Authentication

**Configuration**:
```hcl
keycloak_enable_pkce = false  # Default
```

**Login**:
```bash
argocd login argocd.example.com \
  --username jane.doe \
  --password YOUR_PASSWORD
```

---

## Critical Keycloak Configuration Issues

These are **production issues** discovered during deployment that are not documented upstream:

### Issue 1: Direct Access Grants Required

**Problem**: Even with PKCE enabled, users cannot log in via username/password forms.

**Root Cause**: Keycloak clients have "Direct Access Grants" disabled by default, but ArgoCD requires this for password-based authentication.

**Solution**: Enable "Direct Access Grants" in Keycloak client:

```bash
# Via Keycloak UI:
Clients → argocd → Settings → "Direct Access Grants Enabled" → ON → Save

# Via Terraform (automatically configured):
resource "keycloak_openid_client" "argocd" {
  direct_access_grants_enabled = true  # REQUIRED for password login
}
```

**When Needed**:
- Using `argocd login` with `--username` and `--password`
- Service account authentication
- API automation with username/password
- SSO with username/password forms

---

### Issue 2: Temporary Password Breaks OIDC Flow

**Problem**: Users created with temporary passwords cannot complete OIDC login - they get redirected to password change page, breaking the OAuth flow.

**Root Cause**: Keycloak intercepts OIDC flow to force password change, but ArgoCD doesn't handle this redirect.

**Solution**: Set `temporary = false` when creating users:

```hcl
resource "keycloak_user" "example" {
  realm_id = keycloak_realm.argocd.id
  username = "jane.doe"
  
  initial_password {
    value     = "InitialPassword123!"
    temporary = false  # CRITICAL: Must be false for OIDC to work
  }
}
```

**Via Keycloak UI**:
1. Create user
2. Set password
3. **UNCHECK** "Temporary" checkbox
4. Save

**Workaround** if already created with temporary password:
1. User must log into Keycloak directly: `https://keycloak.example.com`
2. Change password there
3. Then log into ArgoCD via SSO

---

### Issue 3: SSL Passthrough vs TLS Termination

**Problem**: ArgoCD UI shows "Too many redirects" or SSL errors when behind Ingress with TLS termination.

**Root Cause**: ArgoCD server runs in HTTPS mode but Ingress is terminating TLS, creating double TLS layer.

**Solution**: Run ArgoCD in **insecure mode** when behind TLS-terminating Ingress:

```yaml
# ArgoCD server deployment (automatically configured by Terraform)
args:
  - /usr/local/bin/argocd-server
  - --insecure  # REQUIRED when Ingress terminates TLS
```

**Ingress Configuration**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-passthrough: "false"  # TLS termination at ingress
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"  # Backend is HTTP
spec:
  tls:
  - hosts:
    - argocd.example.com
    secretName: argocd-server-tls
  rules:
  - host: argocd.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80  # HTTP backend
```

**When to Use SSL Passthrough** (Not Recommended):
- Set `nginx.ingress.kubernetes.io/ssl-passthrough: "true"`
- ArgoCD server runs in HTTPS mode (remove `--insecure`)
- Ingress forwards encrypted traffic directly to ArgoCD
- Requires cert-manager to create certs in ArgoCD namespace

---

### Issue 4: OIDC Cookie Domain Mismatch

**Problem**: After SSO login, user gets logged out immediately or sees "Invalid session" errors.

**Root Cause**: ArgoCD doesn't know it's behind a proxy/Ingress and generates cookies for wrong domain.

**Solution**: Configure ArgoCD to use correct external URL:

```yaml
# argocd-cmd-params-cm ConfigMap (automatically configured by Terraform)
data:
  server.rootpath: ""
  server.insecure: "true"  # When behind TLS-terminating ingress
  server.basehref: "/"
  
# argocd-cm ConfigMap
data:
  url: "https://argocd.example.com"  # REQUIRED: External URL
  oidc.config: |
    name: Keycloak
    issuer: https://keycloak.example.com/realms/argocd
    clientID: argocd
    clientSecret: $oidc.keycloak.clientSecret
    requestedScopes: ["openid", "profile", "email", "groups"]
```

**Verification**:
```bash
# Check cookies after login
# Should have domain=argocd.example.com, not localhost or internal service name
```

---

### Issue 5: Realm and Group Case Sensitivity

**Problem**: Users can log in but don't get correct permissions.

**Root Cause**: Group names in Keycloak don't match ArgoCD RBAC policy (case-sensitive).

**Solution**: Ensure exact case match:

**Keycloak Groups** (case-sensitive):
- `ArgoCDAdmins` (capital A, C, D)
- `ArgoCDDevelopers`
- `ArgoCDViewers`

**ArgoCD RBAC Policy** (must match exactly):
```csv
g, ArgoCDAdmins, role:admin
g, ArgoCDDevelopers, role:developer
g, ArgoCDViewers, role:viewer
```

**Group Claim Configuration**:
```yaml
oidc.config: |
  requestedScopes: ["openid", "profile", "email", "groups"]
```

**Verification**:
```bash
# Check user's JWT token includes groups
argocd account get --account jane.doe
# Should show groups: ArgoCDDevelopers
```

---

## Production Deployment Checklist

Before enabling Keycloak SSO:

- [ ] Keycloak accessible via HTTPS with valid certificate
- [ ] ArgoCD accessible via HTTPS with valid certificate
- [ ] Keycloak client has "Direct Access Grants Enabled" = ON
- [ ] Created users have `temporary = false` for passwords
- [ ] ArgoCD running with `--insecure` flag (if Ingress terminates TLS)
- [ ] `argocd-cm` has correct `url` field set
- [ ] Ingress backend protocol set to HTTP
- [ ] Group names match exactly (case-sensitive)
- [ ] Test SSO login with at least one admin user
- [ ] Verify permissions work correctly
- [ ] Document recovery procedure (default admin account)

---

## Default Admin User

### Initial Access

```bash
# Get initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

**Username**: `admin`

### Disable Default Admin (Production)

After SSO is working:

```bash
# Disable admin account
kubectl patch configmap argocd-cm -n argocd --type merge -p '
{
  "data": {
    "accounts.admin.enabled": "false"
  }
}
'
```

---

## Security Best Practices

1. **Use SSO in Production**: Configure Keycloak with MFA, short-lived tokens, regular access reviews
2. **Principle of Least Privilege**: Most users → Viewers/Developers, Few → Admins
3. **Audit Logging**: Enable RBAC logging in `argocd-cm`:
   ```yaml
   server.rbac.log.enforce.enable: "true"
   ```
4. **Rotate Credentials**:
   - Keycloak admin password: Quarterly
   - OIDC client secret: Annually
   - Service account tokens: Short-lived (24h-7d)

---

## Troubleshooting

### "Failed to verify token"

**Diagnosis**:
```bash
kubectl get configmap argocd-cm -n argocd -o yaml | grep oidc
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server | grep -i oidc
```

**Common Causes**:
1. Redirect URI mismatch - ensure `argocd_url` matches exactly (including https://)
2. Client secret wrong - check secret in `argocd-secret`
3. Clock skew - sync clocks on all systems

**Fix**:
```bash
terraform apply -replace=module.hub_cluster[0].keycloak_openid_client.argocd
```

---

### "User has no access to applications"

**Diagnosis**:
```bash
# Check user's groups in Keycloak UI: Users → <username> → Groups
kubectl get configmap argocd-rbac-cm -n argocd -o yaml
argocd account can-i sync applications '*'
```

**Fix**:
1. Ensure user is in correct Keycloak group
2. Verify group mapping in `argocd-rbac-cm`
3. Check group names match exactly (case-sensitive)

---

### "SSO login doesn't work in CLI"

**Fix**: Enable PKCE:

```hcl
keycloak_enable_pkce = true
```

```bash
terraform apply
```

---

### "Default admin password doesn't work"

**Reset admin password**:

```bash
NEW_PASSWORD="YourNewPassword123"
BCRYPT_HASH=$(htpasswd -nbBC 10 admin "$NEW_PASSWORD" | awk -F: '{print $2}')

kubectl patch secret argocd-secret -n argocd \
  --type='json' \
  -p="[{'op': 'replace', 'path': '/data/admin.password', 'value': '$(echo -n "$BCRYPT_HASH" | base64)'}]"

kubectl patch secret argocd-secret -n argocd \
  --type='json' \
  -p="[{'op': 'remove', 'path': '/data/admin.passwordMtime'}]"
```

---

## RBAC Policy Reference

### Policy Format

```csv
p, subject, resource, action, object, effect
g, subject, inherited_subject
```

### Common Resources

- `applications` - ArgoCD Applications
- `repositories` - Git/Helm repositories
- `clusters` - Kubernetes clusters
- `projects` - AppProjects
- `logs` - Pod logs
- `exec` - Pod exec access

### Common Actions

- `get` - View resource
- `create` - Create new resource
- `update` - Modify existing resource
- `delete` - Remove resource
- `sync` - Sync Application
- `*` - All actions

### Example Policies

```csv
# Allow developers to sync any application
p, role:developer, applications, sync, */*, allow

# Deny exec access
p, role:developer, exec, create, */*, deny

# Team-specific access
p, role:team-alpha, applications, *, team-alpha/*, allow

# Assign group to role
g, ArgoCDDevelopers, role:developer
```

---

**Related Guides**:
- [Deployment](argocd-agent-terraform-deployment.md) - Initial setup
- [Configuration](argocd-agent-configuration.md) - All Terraform variables
- [Operations](argocd-agent-operations.md) - Day-2 operations
- [Troubleshooting](argocd-agent-troubleshooting.md) - Issue resolution
- [ArgoCD RBAC Docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
