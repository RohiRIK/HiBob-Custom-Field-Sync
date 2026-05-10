# Troubleshooting

Common errors and how to fix them.

---

## Build fails immediately — `FAILURE`

### `Missing required environment variable: TICKET_ID`

**Cause:** The build was triggered manually without setting `TICKET_ID`, or the webhook did not inject it.

**Fix:**
- Manual run: fill in `TICKET_ID` in **Build with Parameters**
- Webhook run: confirm the FreshService Workflow Automator body is exactly `{"ticket_id": "{{ticket.id}}"}` (no extra whitespace, no extra fields)
- Confirm the Generic Webhook Trigger plugin is installed and the token matches `hibob-custom-field-sync-webhook`

---

### `Missing required environment variable: HIBOB_TOKEN`

**Cause:** The Jenkins credential `hibob-api-token` is missing or the credential ID is misspelled.

**Fix:** Go to **Manage Jenkins → Credentials** and verify `hibob-api-token` exists. Check the `environment {}` block in `HibobCustomFieldSync.groovy` — the credential ID must match exactly.

---

### `No CSV attachment found on ticket <id>`

**Cause:** The FreshService ticket has no `.csv` file attached, or the attachment is named with a different extension.

**Fix:**
- Open the ticket in FreshService and confirm a `.csv` file is attached
- The pipeline looks for the first attachment whose `name` ends in `.csv` (case-insensitive)
- If the file is named `.CSV` (uppercase), it will still be matched (`-like '*.csv'` is case-insensitive on Linux)

---

## Sync runs but nothing changes — `Applied=0`

### `DRY_RUN` is still `true`

**Cause:** `DRY_RUN` defaults to `true` — this is intentional.

**Fix:** Uncheck `DRY_RUN` in **Build with Parameters** (or the checkbox in the pipeline job UI).

---

### All rows show `NoChange`

**Cause:** HiBob already has the correct values — no updates needed.

**Fix:** This is correct behaviour. Verify by comparing the CSV values against HiBob's current custom field values.

---

### `NotFound=N` — employees in CSV not matched in HiBob

**Cause:** Email addresses in the CSV don't match HiBob email addresses (case, domain typo, former employees).

**Fix:**
- Emails are normalised to lowercase before comparison — check for domain mismatches (e.g. `@company.com` vs `@company.co.uk`)
- Run with `TEST_USER_EMAIL=the.problematic@email.com` to isolate one user and inspect the log

---

## Build result is `UNSTABLE` — `Failed=N`

**Cause:** One or more rows failed to update in HiBob. Individual row errors are logged at `ERROR` level.

**Fix:**
1. Check the console log for `[ERROR] [Sync] Failed to update <email>: <message>`
2. Common causes:
   - HiBob API rate limit exceeded — lower `RATE_LIMIT_BATCH` or increase `RATE_LIMIT_SLEEP_SECS`
   - Invalid field value rejected by HiBob — check whether the value matches an allowed list
   - Transient HiBob API error — re-run the build; `Invoke-WithRetry` retries 3 times but gives up eventually

---

## HiBob API errors

### `400 Bad Request` on `POST /v1/people/search`

**Cause:** The custom field selector format is not accepted by this HiBob tenant.

**The pipeline handles this automatically:** it retries with dot-style notation (`custom.categoryId.fieldId`) if slash-style (`custom.categoryId/fieldId`) returns 400.

**If it still fails:** double-check `CUSTOM_CATEGORY_ID` and `CUSTOM_FIELD_ID` — find the correct IDs in HiBob → Settings → People → Custom Fields → inspect the field URL or API response.

---

### `401 Unauthorized` on any HiBob call

**Cause:** `hibob-api-token` credential is wrong or expired.

**Fix:** Regenerate the token in HiBob → Settings → Integrations → API, then update the Jenkins credential.

---

## FreshService API errors

### `401 Unauthorized` on `GET /api/v2/tickets/...`

**Cause:** `freshservice-api-key` credential is wrong or the user account it belongs to has been deactivated.

**Fix:** Regenerate the API key in FreshService → Profile → API Key, then update the Jenkins credential.

---

### `404 Not Found` on `GET /api/v2/tickets/<id>`

**Cause:** The ticket ID doesn't exist, was deleted, or the FreshService account doesn't have permission to view it.

**Fix:** Confirm the ticket exists and the API key belongs to an agent with access to that ticket.

---

## PowerShell errors

### `pwsh: command not found`

**Cause:** PowerShell Core is not installed on the Jenkins agent.

**Fix:** The Stage 1 validation check reports this explicitly. Install PowerShell 7.4+ on the agent:
```bash
# Ubuntu/Debian
wget -q "https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb"
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update && sudo apt-get install -y powershell
```

---

### `Import-Module: ... was not loaded because no valid module file was found`

**Cause:** The Jenkins workspace checkout failed or `src/powershell/HibobCustomFieldSync.psm1` is missing.

**Fix:**
- Confirm the SCM checkout is working (check the `Checkout` step in the build log)
- Confirm the branch is `main` and `Script Path` is `HibobCustomFieldSync.groovy`

---

## Running tests locally

```bash
# All tests
pwsh -Command "Invoke-Pester ./tests/ -Output Detailed"

# Single test by name pattern
pwsh -Command "Invoke-Pester ./tests/ -FullNameFilter '*dot-style*'"
```

All 17 tests should pass on any machine with PowerShell 7.4+ and Pester 5.x installed:

```bash
pwsh -Command "Install-Module Pester -Force -Scope CurrentUser"
```
