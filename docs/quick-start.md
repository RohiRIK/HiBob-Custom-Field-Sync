# Quick Start

Get the pipeline running in under 10 minutes.

## Prerequisites

| Requirement | Version |
|-------------|---------|
| Jenkins | 2.387+ |
| PowerShell Core (`pwsh`) | 7.4+ on the Jenkins agent |
| Generic Webhook Trigger plugin | 1.88+ |

---

## Step 1 — Clone the repo

```bash
git clone https://github.com/RohiRIK/HiBob-Custom-Field-Sync.git
```

Or point Jenkins directly at the remote (see [Jenkins Setup](jenkins-setup.md)).

---

## Step 2 — Add credentials to Jenkins

Go to **Manage Jenkins → Credentials → System → Global credentials → Add credential**.

Create these three **Secret text** credentials:

| ID | Value |
|----|-------|
| `hibob-api-token` | HiBob service token (from HiBob Settings → API) |
| `freshservice-api-key` | FreshService API key (from Profile → API Key) |
| `freshservice-base-url` | e.g. `https://yourcompany.freshservice.com` |

---

## Step 3 — Create the Jenkins job

1. **New Item** → name it `HiBob-Custom-Field-Sync` → **Pipeline**
2. **Pipeline** section → Definition: `Pipeline script from SCM`
3. SCM: `Git` → Repository URL: your fork/clone
4. Branch: `*/main`
5. Script Path: `HibobCustomFieldSync.groovy`
6. **Save**

---

## Step 4 — Run a dry-run test

1. Open the job → **Build with Parameters**
2. Set `TICKET_ID` to a real FreshService ticket that has a CSV attachment
3. Leave `DRY_RUN` checked (default `true`)
4. Click **Build**

Check the console output — you should see `Planned=N Applied=0` (no writes, just diffs logged).

---

## Step 5 — Go live

When the dry-run output looks correct:

1. Run again with `DRY_RUN` **unchecked**
2. Verify the build result: `SUCCESS` (all updated) or `UNSTABLE` (partial failure)
3. Check HiBob to confirm the custom field values

---

## CSV Format

The attached CSV must have exactly these headers:

```
Email,Job role name (Job/Job role)
alice@example.com,Senior Engineer
bob@example.com,Product Manager
```

Rows with an empty value column are silently skipped.

---

## Next steps

- [Jenkins Setup](jenkins-setup.md) — webhook wiring, credential details, job options
- [Troubleshooting](troubleshooting.md) — common errors and fixes
