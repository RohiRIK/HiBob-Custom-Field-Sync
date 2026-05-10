$ErrorActionPreference = 'Stop'

# CSV column header — exact string match required
$Script:CsvValueHeader = 'Job role name (Job/Job role)'

#region Logging

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][string]$Message
    )
    $ts = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Write-Host "[$ts] [$Level] [$Context] $Message"
}

#endregion

#region Retry

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$OperationName,
        [int]$MaxAttempts = 3
    )
    $attempt = 0
    while ($true) {
        try {
            return & $Action
        } catch {
            # 4xx = client error, not transient — rethrow immediately without retry
            if ($_ -match '4\d\d') { throw }

            $attempt++
            if ($attempt -ge $MaxAttempts) {
                Write-Log 'ERROR' 'Retry' "$OperationName failed after $MaxAttempts attempts: $_"
                throw
            }
            $delay = [math]::Pow(2, $attempt)
            Write-Log 'WARN' 'Retry' "$OperationName attempt $attempt failed — retrying in ${delay}s: $_"
            Start-Sleep -Seconds $delay
        }
    }
}

#endregion

#region FreshService

function Get-FreshServiceAttachment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$ApiKey,
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$OutPath
    )

    $authBytes  = [Text.Encoding]::ASCII.GetBytes("${ApiKey}:X")
    $authHeader = [Convert]::ToBase64String($authBytes)
    $headers    = @{ Authorization = "Basic $authHeader" }

    Write-Log 'INFO' 'FreshService' "Fetching ticket $TicketId"
    $ticket = Invoke-WithRetry -OperationName "GET ticket $TicketId" -Action {
        Invoke-RestMethod -Uri "$BaseUrl/api/v2/tickets/$TicketId" -Headers $headers -Method Get
    }

    $attachment = $ticket.ticket.attachments | Where-Object { $_.name -like '*.csv' } | Select-Object -First 1
    if (-not $attachment) {
        throw "No CSV attachment found on ticket $TicketId"
    }

    Write-Log 'INFO' 'FreshService' "Downloading attachment id=$($attachment.id) name=$($attachment.name)"
    $null = Invoke-WithRetry -OperationName "GET attachment $($attachment.id)" -Action {
        Invoke-WebRequest -Uri "$BaseUrl/api/v2/attachments/$($attachment.id)" -Headers $headers -OutFile $OutPath
    }

    Write-Log 'INFO' 'FreshService' "Saved to $OutPath"
    return $OutPath
}

#endregion

#region HiBob

function Get-HiBobPeople {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$CategoryId,
        [Parameter(Mandatory)][string]$FieldId
    )

    $headers = @{
        Authorization  = "Basic $Token"
        'Content-Type' = 'application/json'
    }

    $slashBody = @{
        fields = @('/root/id', '/root/email', "custom.${CategoryId}/${FieldId}")
    } | ConvertTo-Json -Compress

    Write-Log 'INFO' 'HiBob' "Fetching employees (slash-style field selector)"
    try {
        $resp = Invoke-WithRetry -OperationName 'POST people/search (slash)' -Action {
            Invoke-RestMethod -Uri 'https://api.hibob.com/v1/people/search' -Method Post -Headers $headers -Body $slashBody
        }
        return $resp.employees
    } catch {
        if ($_ -match '400') {
            Write-Log 'WARN' 'HiBob' "Slash-style returned 400 — retrying with dot-style selector"
            $dotBody = @{
                fields = @('/root/id', '/root/email', "custom.${CategoryId}.${FieldId}")
            } | ConvertTo-Json -Compress

            $resp = Invoke-WithRetry -OperationName 'POST people/search (dot)' -Action {
                Invoke-RestMethod -Uri 'https://api.hibob.com/v1/people/search' -Method Post -Headers $headers -Body $dotBody
            }
            return $resp.employees
        }
        throw
    }
}

function Set-HiBobCustomField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$EmployeeId,
        [Parameter(Mandatory)][string]$CategoryId,
        [Parameter(Mandatory)][string]$FieldId,
        [Parameter(Mandatory)][string]$Value
    )

    $headers = @{
        Authorization  = "Basic $Token"
        'Content-Type' = 'application/json'
    }

    $body = @{ custom = @{ $CategoryId = @{ $FieldId = $Value } } } | ConvertTo-Json -Depth 6 -Compress

    Invoke-WithRetry -OperationName "PUT people/$EmployeeId" -Action {
        Invoke-RestMethod -Uri "https://api.hibob.com/v1/people/$EmployeeId" -Method Put -Headers $headers -Body $body
    }
}

#endregion

#region CSV

function Import-SyncCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $rows = Import-Csv -Path $Path

    if ($rows.Count -eq 0) {
        Write-Log 'WARN' 'CSV' "File is empty: $Path"
        return , @()
    }

    $sample = $rows[0].PSObject.Properties.Name
    if ('Email' -notin $sample) {
        throw "CSV missing required column 'Email' — found: $($sample -join ', ')"
    }
    if ($Script:CsvValueHeader -notin $sample) {
        throw "CSV missing required column '$Script:CsvValueHeader' — found: $($sample -join ', ')"
    }

    $skipped = 0
    $result  = [System.Collections.Generic.List[hashtable]]::new()

    $csvHeader = $Script:CsvValueHeader
    foreach ($row in $rows) {
        $val = $row.$csvHeader.Trim()
        if ([string]::IsNullOrEmpty($val)) {
            $skipped++
            continue
        }
        $result.Add(@{
            Email = $row.Email.Trim().ToLower()
            Value = $val
        })
    }

    if ($skipped -gt 0) {
        Write-Log 'INFO' 'CSV' "Skipped $skipped rows with empty value"
    }

    Write-Log 'INFO' 'CSV' "Loaded $($result.Count) rows from $Path"
    return , $result.ToArray()
}

#endregion

#region Sync

function Invoke-FieldSync {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$CsvRows,
        [Parameter(Mandatory)][array]$Employees,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$CategoryId,
        [Parameter(Mandatory)][string]$FieldId,
        [bool]$DryRun            = $true,
        [string]$TestUserEmail   = '',
        [int]$RateLimitBatch     = 79,
        [int]$RateLimitSleepSecs = 120
    )

    # Build lookup: email (lowercase) → employee object
    $lookup = @{}
    foreach ($emp in $Employees) {
        if ($emp.email) {
            $lookup[$emp.email.ToLower()] = $emp
        }
    }

    # Optionally filter to a single test user
    $workRows = $CsvRows
    if (-not [string]::IsNullOrEmpty($TestUserEmail)) {
        $workRows = $CsvRows | Where-Object { $_.Email -eq $TestUserEmail.ToLower() }
        if ($workRows.Count -eq 0) {
            throw "TEST_USER_EMAIL '$TestUserEmail' not found in CSV"
        }
        $testEmp = $lookup[$TestUserEmail.ToLower()]
        if (-not $testEmp) {
            throw "TEST_USER_EMAIL '$TestUserEmail' not found in HiBob employees"
        }
    }

    $Planned  = 0
    $Applied  = 0
    $Failed   = 0
    $NoChange = 0
    $NotFound = 0

    foreach ($row in $workRows) {
        $email = $row.Email
        $emp   = $lookup[$email]

        if (-not $emp) {
            $NotFound++
            Write-Log 'WARN' 'Sync' "Employee not found in HiBob: $email"
            continue
        }

        $current = $null
        if ($emp.custom -and $emp.custom.$CategoryId) {
            $current = $emp.custom.$CategoryId.$FieldId
        }
        $current = if ($current) { $current.Trim() } else { '' }
        $desired = $row.Value.Trim()

        if ($current -eq $desired) {
            $NoChange++
            continue
        }

        $Planned++
        Write-Log 'INFO' 'Sync' "[$email] $current → $desired$(if ($DryRun) { ' (dry-run)' })"

        if ($DryRun) { continue }

        try {
            Set-HiBobCustomField -Token $Token -EmployeeId $emp.id -CategoryId $CategoryId -FieldId $FieldId -Value $desired
            $Applied++

            if ($RateLimitBatch -gt 0 -and ($Applied % $RateLimitBatch) -eq 0) {
                Write-Log 'INFO' 'Sync' "Rate-limit pause: $RateLimitSleepSecs seconds after $Applied writes"
                Start-Sleep -Seconds $RateLimitSleepSecs
            }
        } catch {
            $Failed++
            Write-Log 'ERROR' 'Sync' "Failed to update ${email}: $_"
        }
    }

    $result = [pscustomobject]@{
        Planned  = $Planned
        Applied  = $Applied
        Failed   = $Failed
        NoChange = $NoChange
        NotFound = $NotFound
    }

    Write-Log 'INFO' 'Sync' "Summary — Planned=$Planned Applied=$Applied Failed=$Failed NoChange=$NoChange NotFound=$NotFound"
    return $result
}

#endregion

Export-ModuleMember -Function Get-FreshServiceAttachment, Get-HiBobPeople, Set-HiBobCustomField, Import-SyncCsv, Invoke-FieldSync, Write-Log
