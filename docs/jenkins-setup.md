# Jenkins Setup

Complete reference for configuring the Jenkins job and webhook.

---

## Credentials

All secrets are injected via Jenkins credential store — nothing is hardcoded.

### Required credentials

| Credential ID | Type | Where to get it |
|---------------|------|-----------------|
| `hibob-api-token` | Secret text | HiBob → Settings → Integrations → API → Create token |
| `freshservice-api-key` | Secret text | FreshService → Profile icon → API Key |
| `freshservice-base-url` | Secret text | Your FreshService domain, e.g. `https://yourcompany.freshservice.com` |

Create each at: **Manage Jenkins → Credentials → System → Global credentials → Add credential**

> **Tip:** Use descriptive descriptions on each credential so the next person knows what they're for.

---

## Job Configuration

### Create the job

1. **Jenkins dashboard** → **New Item**
2. Name: `HiBob-Custom-Field-Sync`
3. Type: **Pipeline** (not Multibranch)
4. **OK**

### Pipeline section

| Field | Value |
|-------|-------|
| Definition | Pipeline script from SCM |
| SCM | Git |
| Repository URL | `https://github.com/RohiRIK/HiBob-Custom-Field-Sync.git` |
| Credentials | *(add a GitHub credential if the repo is private)* |
| Branch Specifier | `*/main` |
| Script Path | `HibobCustomFieldSync.groovy` |

**Save** the job.

---

## Generic Webhook Trigger

### Install the plugin

**Manage Jenkins → Plugins → Available plugins** → search `Generic Webhook Trigger` → Install.

### Webhook URL

```
https://<jenkins-host>/generic-webhook-trigger/invoke?token=hibob-custom-field-sync-webhook
```

The token `hibob-custom-field-sync-webhook` is hardcoded in `HibobCustomFieldSync.groovy`. Keep it consistent.

### FreshService Workflow Automator setup

1. In FreshService: **Admin → Workflow Automator → New Workflow**
2. Trigger: **Ticket created** (or whichever event generates the CSV ticket)
3. Action: **Trigger Webhook**
4. Method: `POST`
5. URL: *(Jenkins webhook URL above)*
6. Content type: `application/json`
7. Body:
   ```json
   {"ticket_id": "{{ticket.id}}"}
   ```
8. Save and activate the workflow

### How it works

FreshService POSTs `{"ticket_id": "12345"}` to Jenkins. The Generic Webhook Trigger plugin extracts `$.ticket_id` and injects it as the `TICKET_ID` build parameter. The pipeline then downloads the CSV attachment from that ticket.

---

## Pipeline Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TICKET_ID` | *(from webhook)* | FreshService ticket ID — set manually for ad-hoc runs |
| `DRY_RUN` | `true` | Log planned changes without writing to HiBob |
| `TEST_USER_EMAIL` | *(empty)* | Process only this one email — safe for spot-checking |
| `CUSTOM_CATEGORY_ID` | `category_placeholder` | HiBob custom field category ID |
| `CUSTOM_FIELD_ID` | `field_placeholder` | HiBob custom field ID within the category |
| `RATE_LIMIT_BATCH` | `79` | Number of writes before pausing |
| `RATE_LIMIT_SLEEP_SECS` | `120` | Pause duration (seconds) between batches |

> Update `CUSTOM_CATEGORY_ID` and `CUSTOM_FIELD_ID` to your real HiBob field IDs before going live. Find them in HiBob → Settings → People → Custom Fields.

---

## Exit Code Contract

| Exit code | Jenkins result | Meaning |
|-----------|---------------|---------|
| `0` | SUCCESS | All rows processed |
| `1` | FAILURE | Fatal error (missing credential, download failed, etc.) |
| `2` | UNSTABLE | At least one row failed to update in HiBob |

---

## Agent Requirements

The Jenkins agent running this pipeline needs:

- **PowerShell Core 7.4+** — `pwsh` must be in `$PATH`
- **Internet access** to `api.hibob.com` and your FreshService domain
- **No additional modules required** — the pipeline uses only `Invoke-RestMethod` and `Invoke-WebRequest` (built-in)

### Verify `pwsh` on the agent

```bash
pwsh --version
# Expected: PowerShell 7.4.x
```

---

## Security Notes

- HR data (CSV) is deleted from the workspace after every build via `post { always { rm -f "$CSV_PATH" } }`
- `specs/` and `plans/` are gitignored — never committed to the repo
- All secrets are injected via Jenkins credential store — no secrets in code or logs
- The webhook token should be rotated if the Jenkins URL is ever public
