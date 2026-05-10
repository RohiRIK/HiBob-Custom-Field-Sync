# HiBob Custom Field Sync

Automated Jenkins pipeline that syncs a HiBob custom field from a CSV attached to a FreshService ticket.

## Flow

```
FreshService Workflow Automator
  └─ POST {"ticket_id": "<id>"}
       └─► Jenkins (Generic Webhook Trigger)
              ├─ GET /api/v2/tickets/{id}     → find CSV attachment id
              ├─ GET /api/v2/attachments/{id} → download CSV
              ├─ POST /v1/people/search       → fetch HiBob employees
              ├─ diff CSV vs HiBob
              └─ PUT /v1/people/{id}          → patch custom field (per changed row)
```

## Jenkins Setup

### 1. Credentials

Create these three credentials in **Manage Jenkins → Credentials**:

| Credential ID             | Type   | Value |
|---------------------------|--------|-------|
| `hibob-api-token`         | Secret text | HiBob service token (Basic auth, no password needed) |
| `freshservice-api-key`    | Secret text | FreshService API key |
| `freshservice-base-url`   | Secret text | e.g. `https://yourcompany.freshservice.com` |

### 2. Jenkins Job

- **Type:** Pipeline
- **Definition:** Pipeline script from SCM
- **SCM:** Git — point to this repo
- **Branch:** `*/main`
- **Script Path:** `HibobCustomFieldSync.groovy`

### 3. Generic Webhook Trigger Plugin

Install the **Generic Webhook Trigger** plugin, then configure the FreshService Workflow Automator to POST:

```json
{"ticket_id": "{{ticket.id}}"}
```

to:

```
https://<jenkins>/generic-webhook-trigger/invoke?token=hibob-custom-field-sync-webhook
```

The pipeline extracts `$.ticket_id` → `TICKET_ID` automatically.

## Pipeline Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TICKET_ID` | _(webhook)_ | FreshService ticket ID — injected by webhook, set manually for ad-hoc runs |
| `DRY_RUN` | `true` | Log changes without writing to HiBob |
| `TEST_USER_EMAIL` | _(empty)_ | Limit sync to one email address |
| `CUSTOM_CATEGORY_ID` | `category_placeholder` | HiBob custom field category ID |
| `CUSTOM_FIELD_ID` | `field_placeholder` | HiBob custom field ID within the category |
| `RATE_LIMIT_BATCH` | `79` | Writes before pausing |
| `RATE_LIMIT_SLEEP_SECS` | `120` | Pause duration (seconds) |

## Exit Code Contract

| Code | Meaning | Jenkins Result |
|------|---------|----------------|
| `0` | All rows processed successfully | SUCCESS |
| `1` | Fatal error (missing env var, download failure, etc.) | FAILURE |
| `2` | Partial: at least one row failed to update | UNSTABLE |

## CSV Format

The CSV must have these exact column headers:

```
Email,Job role name (Job/Job role)
alice@example.com,Senior Engineer
bob@example.com,Product Manager
```

Rows with an empty value column are silently skipped.

## Local Testing

```bash
# Run full Pester suite
pwsh -Command "Invoke-Pester ./tests/"

# Verbose output
pwsh -Command "Invoke-Pester ./tests/ -Output Detailed"

# Single test file
pwsh -Command "Invoke-Pester ./tests/HibobCustomFieldSync.Tests.ps1"
```

## Manual / Ad-hoc Run

```bash
export TICKET_ID="99001"
export HIBOB_TOKEN="your-hibob-token"
export FRESHSERVICE_API_KEY="your-fs-api-key"
export FRESHSERVICE_BASE_URL="https://yourcompany.freshservice.com"
export CUSTOM_CATEGORY_ID="category_12345"
export CUSTOM_FIELD_ID="field_67890"
export CSV_PATH="/tmp/job-roles.csv"
export IS_DRY_RUN="true"

pwsh -File src/powershell/Invoke-Sync.ps1
```

## Security Notes

- HR data (CSV) is deleted from the workspace after every build via `post { always { rm -f "$CSV_PATH" } }`
- `specs/` and `plans/` are gitignored — never committed
- All secrets injected via Jenkins credential store — no hardcoded values
