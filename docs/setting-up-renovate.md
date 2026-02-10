# Setting Up Renovate Bot

A step-by-step guide to installing, configuring, and testing [Renovate Bot](https://docs.renovatebot.com/) for automated dependency updates in this repository.

## Prerequisites

- Admin or maintainer access to the GitHub repository
- Familiarity with JSON configuration files

---

## Step 1: Install the Renovate GitHub App

1. Go to [github.com/apps/renovate](https://github.com/apps/renovate)
2. Click **Install**
3. Choose the either GitHub organization or your personal GitHub account
4. Select either:
   - **All repositories** — Renovate manages every repo in the org
   - **Only select repositories** — Choose `observability` specifically
5. Click **Install & Authorize**

> [!NOTE]
> After installation, Renovate will automatically open an **Onboarding PR** in the repository within a few minutes.

---

## Step 2: Review the Onboarding PR

Renovate's first action is to open a PR titled **"Configure Renovate"**. This PR:

- Adds a `renovate.json` configuration file to the repo root
- Contains a **Dependency Dashboard** showing all detected dependencies
- Does **not** modify any existing code

**What to check:**

- Verify the detected dependencies list (Terraform providers, GitHub Actions, Docker images, Helm charts)
- Review the proposed `renovate.json` default configuration
- Merge the PR to activate Renovate

---

## Step 3: Configure Renovate

After merging the onboarding PR, you can customize `renovate.json` in the repository root. Like for example this configuration below:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended"
  ],
  "labels": ["dependencies"],
  "schedule": ["before 9am on monday"],
  "packageRules": [
    {
      "description": "Group Terraform provider updates",
      "matchManagers": ["terraform"],
      "groupName": "terraform providers",
      "automerge": false
    },
    {
      "description": "Group GitHub Actions updates",
      "matchManagers": ["github-actions"],
      "groupName": "github-actions",
      "automerge": true,
      "automergeType": "pr",
      "matchUpdateTypes": ["minor", "patch"]
    },
    {
      "description": "Group Docker image updates",
      "matchDatasources": ["docker"],
      "groupName": "docker images",
      "automerge": false
    },
    {
      "description": "Group Helm chart updates",
      "matchDatasources": ["helm"],
      "groupName": "helm charts",
      "automerge": false
    },
    {
      "description": "Automerge minor and patch updates",
      "matchUpdateTypes": ["minor", "patch"],
      "automerge": true,
      "automergeType": "pr"
    }
  ]
}
```

### Key Configuration Options

| Option | Description |
|--------|-------------|
| `extends` | Inherits from Renovate's recommended defaults |
| `schedule` | When Renovate creates/updates PRs (e.g., Monday mornings) |
| `packageRules` | Rules for specific dependency types |
| `automerge` | Automatically merge low-risk updates (minor/patch) |
| `groupName` | Groups related updates into a single PR |
| `labels` | Labels applied to Renovate PRs |

<!-- # > [!TIP]
# > Start with `automerge` disabled for all rules, then gradually enable it for low-risk update types (patch, minor) once you're confident in your CI pipeline. -->

---

## Step 4: Test Renovate

### Check the Dependency Dashboard

After merging the onboarding PR, Renovate creates a **Dependency Dashboard** issue in the repository. This issue:

- Lists all detected dependencies and their current versions
- Shows pending updates and their status
- Allows you to manually trigger update PRs by checking checkboxes

### Trigger a Test Run

To verify Renovate is working:

1. Open the **Dependency Dashboard** issue
2. Check the box next to any pending update to trigger it
3. Renovate will create a PR with the update within minutes
4. Review the PR — it should contain:
   - Updated version numbers in the relevant files
   - Release notes and changelog for the updated dependency
   - CI pipeline results

### Verify Detected Managers

Renovate should detect these dependency managers in this repository:

| Manager | Files | Example Dependencies |
|---------|-------|---------------------|
| Terraform | `*.tf` files | `hashicorp/kubernetes`, `hashicorp/helm` providers |
| GitHub Actions | `.github/workflows/*.yaml` | `actions/checkout`, `hashicorp/setup-terraform` |
| Docker | `Dockerfile`, Compose files | Base images |
| Helm | Chart references in Terraform | Grafana, Loki, Tempo chart versions |

---

## Step 5: Manage Renovate PRs

### PR Workflow

1. **Review** — Renovate PRs include release notes and changelogs
2. **CI check** — Your existing GitHub Actions workflows run automatically
3. **Merge or close** — Merge if CI passes, close if the update is not needed
4. **Renovate rebases** — Open PRs are automatically rebased when the base branch changes

### Handling Major Updates

Major version updates may contain breaking changes. For these:

- Renovate creates separate PRs for major updates (not grouped)
- Review the changelog carefully for breaking changes
- Test locally or in a staging environment before merging

---

<!-- ## Renovate vs Dependabot

This repository currently uses Dependabot (`.github/dependabot.yml`). Here's how they compare:

| Feature | Renovate | Dependabot |
|---------|----------|------------|
| Package managers | 90+ (including Helm, Terraform) | ~15 |
| Grouping updates | ✅ Group related updates in one PR | ✅ (limited) |
| Automerge | ✅ Built-in | ❌ Requires external automation |
| Custom scheduling | ✅ Flexible cron-like schedules | ✅ Basic intervals |
| Dependency Dashboard | ✅ Interactive issue dashboard | ❌ |
| Configuration | JSON with presets & inheritance | YAML |
| Hosting | GitHub App or self-hosted | GitHub-native |

> [!IMPORTANT]
> If you adopt Renovate, consider removing or disabling Dependabot to avoid duplicate update PRs for the same dependencies. You can do this by deleting `.github/dependabot.yml` or setting `open-pull-requests-limit: 0`.

--- -->

## Troubleshooting

### Renovate is not opening PRs

- Check the **Dependency Dashboard** issue for error messages
- Verify the GitHub App is still installed: **Settings → Integrations → Applications**
- Check the `schedule` in `renovate.json` — Renovate only runs during scheduled windows

### Too many PRs at once

Add rate limiting to `renovate.json`:

```json
{
  "prConcurrentLimit": 5,
  "prHourlyLimit": 2
}
```

### Renovate is not detecting a dependency

- Ensure the file format is supported ([supported managers list](https://docs.renovatebot.com/modules/manager/))
- Check if the file is excluded by `.gitignore` or Renovate's `ignorePaths` setting

---

## References

- [Renovate Official Documentation](https://docs.renovatebot.com/)
- [Renovate GitHub App](https://github.com/apps/renovate)
- [Configuration Options](https://docs.renovatebot.com/configuration-options/)
- [Supported Managers](https://docs.renovatebot.com/modules/manager/)
- [Renovate Presets](https://docs.renovatebot.com/presets-default/)
