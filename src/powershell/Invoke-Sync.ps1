$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here 'HibobCustomFieldSync.psm1') -Force

#region Env validation

$requiredVars = @(
    'TICKET_ID',
    'HIBOB_TOKEN',
    'FRESHSERVICE_API_KEY',
    'FRESHSERVICE_BASE_URL',
    'CUSTOM_CATEGORY_ID',
    'CUSTOM_FIELD_ID',
    'CSV_PATH'
)

foreach ($var in $requiredVars) {
    if ([string]::IsNullOrEmpty([System.Environment]::GetEnvironmentVariable($var))) {
        Write-Log 'ERROR' 'Main' "Missing required environment variable: $var"
        exit 1
    }
}

#endregion

#region Parse optional params

$DryRun = $env:IS_DRY_RUN -ne 'false'   # default true — must explicitly set to 'false' to write

$TestUserEmail = $env:TEST_USER_EMAIL    # empty means process all rows

$rateLimitBatch = 79
$parsedBatch    = 0
if ([int]::TryParse($env:RATE_LIMIT_BATCH, [ref]$parsedBatch) -and $parsedBatch -gt 0) {
    $rateLimitBatch = $parsedBatch
}

$rateLimitSleepSecs = 120
$parsedSleep        = 0
if ([int]::TryParse($env:RATE_LIMIT_SLEEP_SECS, [ref]$parsedSleep) -and $parsedSleep -ge 0) {
    $rateLimitSleepSecs = $parsedSleep
}

Write-Log 'INFO' 'Main' "DryRun=$DryRun TestUser='$TestUserEmail' RateLimitBatch=$rateLimitBatch RateLimitSleepSecs=$rateLimitSleepSecs"

#endregion

#region Run

try {
    Write-Log 'INFO' 'Main' "Step 1: Downloading CSV from FreshService ticket $env:TICKET_ID"
    Get-FreshServiceAttachment `
        -BaseUrl $env:FRESHSERVICE_BASE_URL `
        -ApiKey  $env:FRESHSERVICE_API_KEY `
        -TicketId $env:TICKET_ID `
        -OutPath  $env:CSV_PATH | Out-Null

    Write-Log 'INFO' 'Main' "Step 2: Parsing CSV"
    $rows = Import-SyncCsv -Path $env:CSV_PATH

    Write-Log 'INFO' 'Main' "Step 3: Fetching HiBob employees"
    $employees = Get-HiBobPeople `
        -Token      $env:HIBOB_TOKEN `
        -CategoryId $env:CUSTOM_CATEGORY_ID `
        -FieldId    $env:CUSTOM_FIELD_ID

    Write-Log 'INFO' 'Main' "Step 4: Running field sync (DryRun=$DryRun)"
    $result = Invoke-FieldSync `
        -CsvRows             $rows `
        -Employees           $employees `
        -Token               $env:HIBOB_TOKEN `
        -CategoryId          $env:CUSTOM_CATEGORY_ID `
        -FieldId             $env:CUSTOM_FIELD_ID `
        -DryRun              $DryRun `
        -TestUserEmail       $TestUserEmail `
        -RateLimitBatch      $rateLimitBatch `
        -RateLimitSleepSecs  $rateLimitSleepSecs

} catch {
    Write-Log 'ERROR' 'Main' "Fatal error: $_"
    exit 1
}

#endregion

#region Summary

Write-Host ''
Write-Host '═══════════════════════════════════════════'
Write-Host '  HiBob Custom Field Sync — Results'
Write-Host '═══════════════════════════════════════════'
Write-Host "  Planned   : $($result.Planned)"
Write-Host "  Applied   : $($result.Applied)"
Write-Host "  No-change : $($result.NoChange)"
Write-Host "  Not found : $($result.NotFound)"
Write-Host "  Failed    : $($result.Failed)"
Write-Host '═══════════════════════════════════════════'

#endregion

if ($result.Failed -gt 0) {
    exit 2
}
exit 0
