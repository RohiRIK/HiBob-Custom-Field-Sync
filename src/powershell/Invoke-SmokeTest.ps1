$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here 'HibobCustomFieldSync.psm1') -Force

Write-Log 'INFO' 'Smoke' '========================================='
Write-Log 'INFO' 'Smoke' '  HiBob Custom Field Sync — SMOKE TEST  '
Write-Log 'INFO' 'Smoke' '  (no real API calls — fake data only)  '
Write-Log 'INFO' 'Smoke' '========================================='

# ── Fake CSV rows (what Import-SyncCsv would return) ─────────────────────────
$fakeCsvRows = @(
    @{ Email = 'alice@example.com'; Value = 'Senior Engineer' }
    @{ Email = 'bob@example.com';   Value = 'Product Manager' }
    @{ Email = 'carol@example.com'; Value = 'Team Lead' }
    @{ Email = 'ghost@example.com'; Value = 'Analyst' }   # will be NotFound
)

Write-Log 'INFO' 'Smoke' "Step 1: FreshService download — SKIPPED (smoke mode)"
Write-Log 'INFO' 'Smoke' "Would call: GET /api/v2/tickets/SMOKE-001 → find CSV attachment"
Write-Log 'INFO' 'Smoke' "Would call: GET /api/v2/attachments/<id> → download job-roles.csv"
Write-Log 'INFO' 'Smoke' "Loaded $($fakeCsvRows.Count) fake CSV rows"

# ── Fake HiBob employees (what Get-HiBobPeople would return) ─────────────────
$fakeEmployees = @(
    [pscustomobject]@{
        id     = 'emp-001'
        email  = 'alice@example.com'
        custom = [pscustomobject]@{
            category_placeholder = [pscustomobject]@{
                field_placeholder = 'Old Role'   # will be updated
            }
        }
    }
    [pscustomobject]@{
        id     = 'emp-002'
        email  = 'bob@example.com'
        custom = [pscustomobject]@{
            category_placeholder = [pscustomobject]@{
                field_placeholder = 'Product Manager'   # already correct → NoChange
            }
        }
    }
    [pscustomobject]@{
        id     = 'emp-003'
        email  = 'carol@example.com'
        custom = [pscustomobject]@{
            category_placeholder = [pscustomobject]@{
                field_placeholder = 'Junior'   # will be updated
            }
        }
    }
    # ghost@example.com NOT in employees → NotFound
)

Write-Log 'INFO' 'Smoke' "Step 2: HiBob people fetch — SKIPPED (smoke mode)"
Write-Log 'INFO' 'Smoke' "Would call: POST /v1/people/search with field selector"
Write-Log 'INFO' 'Smoke' "Loaded $($fakeEmployees.Count) fake employees"

# ── Run Invoke-FieldSync in DryRun mode (real function, fake data) ────────────
Write-Log 'INFO' 'Smoke' "Step 3: Running Invoke-FieldSync — DryRun=true (no HiBob writes)"

$result = Invoke-FieldSync `
    -CsvRows             $fakeCsvRows `
    -Employees           $fakeEmployees `
    -Token               'SMOKE_TOKEN' `
    -CategoryId          'category_placeholder' `
    -FieldId             'field_placeholder' `
    -DryRun              $true `
    -TestUserEmail       '' `
    -RateLimitBatch      79 `
    -RateLimitSleepSecs  0

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '═══════════════════════════════════════════'
Write-Host '  Smoke Test Results'
Write-Host '═══════════════════════════════════════════'
Write-Host "  Planned   : $($result.Planned)   (would update in live run)"
Write-Host "  Applied   : $($result.Applied)   (0 because DryRun=true)"
Write-Host "  No-change : $($result.NoChange)"
Write-Host "  Not found : $($result.NotFound)  (in CSV but missing from HiBob)"
Write-Host "  Failed    : $($result.Failed)"
Write-Host '═══════════════════════════════════════════'
Write-Host ''
Write-Log 'INFO' 'Smoke' "Smoke test complete — all module functions loaded and executed"
Write-Log 'INFO' 'Smoke' "If you see this, PowerShell + module are working correctly"

exit 0
