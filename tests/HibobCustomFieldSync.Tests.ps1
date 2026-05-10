BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../src/powershell/HibobCustomFieldSync.psm1'
    Import-Module $modulePath -Force
}

# ─────────────────────────────────────────────
#  Write-Log
# ─────────────────────────────────────────────
Describe 'Write-Log' {
    It 'writes formatted output with all three levels' {
        { Write-Log -Level 'INFO'  -Context 'Test' -Message 'hello info'  } | Should -Not -Throw
        { Write-Log -Level 'WARN'  -Context 'Test' -Message 'hello warn'  } | Should -Not -Throw
        { Write-Log -Level 'ERROR' -Context 'Test' -Message 'hello error' } | Should -Not -Throw
    }

    It 'throws on invalid level' {
        { Write-Log -Level 'DEBUG' -Context 'Test' -Message 'bad level' } | Should -Throw
    }
}

# ─────────────────────────────────────────────
#  Get-FreshServiceAttachment
# ─────────────────────────────────────────────
Describe 'Get-FreshServiceAttachment' {
    BeforeAll {
        $fixtureTicket = Get-Content (Join-Path $PSScriptRoot 'fixtures/freshservice-ticket.json') | ConvertFrom-Json
    }

    It 'downloads CSV via two-call pattern and returns OutPath' {
        Mock Invoke-RestMethod -ModuleName HibobCustomFieldSync -ParameterFilter {
            $Uri -like '*/tickets/*'
        } -MockWith { $fixtureTicket }

        Mock Invoke-WebRequest -ModuleName HibobCustomFieldSync -ParameterFilter {
            $Uri -like '*/attachments/*'
        } -MockWith { $null }

        $result = Get-FreshServiceAttachment `
            -BaseUrl 'https://company.freshservice.com' `
            -ApiKey  'test-key' `
            -TicketId '99001' `
            -OutPath  (Join-Path $TestDrive 'out.csv')

        $result | Should -Match 'out\.csv'
        Should -Invoke Invoke-RestMethod -Exactly 1 -ModuleName HibobCustomFieldSync
        Should -Invoke Invoke-WebRequest -Exactly 1 -ModuleName HibobCustomFieldSync
    }

    It 'throws when ticket has no CSV attachment' {
        Mock Invoke-RestMethod -ModuleName HibobCustomFieldSync -ParameterFilter {
            $Uri -like '*/tickets/*'
        } -MockWith {
            [pscustomobject]@{
                ticket = [pscustomobject]@{
                    id          = 99002
                    attachments = @(
                        [pscustomobject]@{ id = 1; name = 'notes.txt'; content_type = 'text/plain' }
                    )
                }
            }
        }

        {
            Get-FreshServiceAttachment `
                -BaseUrl 'https://company.freshservice.com' `
                -ApiKey  'test-key' `
                -TicketId '99002' `
                -OutPath  (Join-Path $TestDrive 'out.csv')
        } | Should -Throw '*No CSV attachment*'
    }

    It 'retries on API 500 then rethrows after max attempts' {
        Mock Invoke-RestMethod -ModuleName HibobCustomFieldSync -ParameterFilter {
            $Uri -like '*/tickets/*'
        } -MockWith { throw '500 Internal Server Error' }

        Mock Start-Sleep -ModuleName HibobCustomFieldSync -MockWith { $null }

        {
            Get-FreshServiceAttachment `
                -BaseUrl 'https://company.freshservice.com' `
                -ApiKey  'test-key' `
                -TicketId '99003' `
                -OutPath  (Join-Path $TestDrive 'out.csv')
        } | Should -Throw

        Should -Invoke Invoke-RestMethod -Exactly 3 -ModuleName HibobCustomFieldSync
    }
}

# ─────────────────────────────────────────────
#  Import-SyncCsv
# ─────────────────────────────────────────────
Describe 'Import-SyncCsv' {
    It 'parses a valid CSV and normalises email to lowercase' {
        $csvContent = "Email,Job role name (Job/Job role)`nALICE@EXAMPLE.COM,Senior Engineer`nbob@example.com,Product Manager"
        $path = Join-Path $TestDrive 'valid.csv'
        Set-Content -Path $path -Value $csvContent

        $rows = Import-SyncCsv -Path $path
        $rows.Count | Should -Be 2
        $rows[0].Email | Should -Be 'alice@example.com'
        $rows[0].Value | Should -Be 'Senior Engineer'
    }

    It 'throws when Email column is missing' {
        $csvContent = "EmployeeEmail,Job role name (Job/Job role)`nfoo@example.com,Engineer"
        $path = Join-Path $TestDrive 'no-email.csv'
        Set-Content -Path $path -Value $csvContent

        { Import-SyncCsv -Path $path } | Should -Throw "*missing required column 'Email'*"
    }

    It 'throws when value column is missing' {
        $csvContent = "Email,WrongColumn`nfoo@example.com,Engineer"
        $path = Join-Path $TestDrive 'no-value.csv'
        Set-Content -Path $path -Value $csvContent

        { Import-SyncCsv -Path $path } | Should -Throw "*missing required column*"
    }

    It 'skips rows with empty value and logs the count' {
        $csvContent = "Email,Job role name (Job/Job role)`nalice@example.com,Engineer`nbob@example.com,"
        $path = Join-Path $TestDrive 'empty-value.csv'
        Set-Content -Path $path -Value $csvContent

        $rows = Import-SyncCsv -Path $path
        $rows.Count | Should -Be 1
        $rows[0].Email | Should -Be 'alice@example.com'
    }
}

# ─────────────────────────────────────────────
#  Get-HiBobPeople
# ─────────────────────────────────────────────
Describe 'Get-HiBobPeople' {
    BeforeAll {
        $fixtureEmployees = Get-Content (Join-Path $PSScriptRoot 'fixtures/employees-5.json') | ConvertFrom-Json
    }

    It 'returns employees on success with slash-style' {
        Mock Invoke-RestMethod -ModuleName HibobCustomFieldSync -MockWith { $fixtureEmployees }

        $result = Get-HiBobPeople -Token 'abc123' -CategoryId 'category_placeholder' -FieldId 'field_placeholder'
        $result.Count | Should -Be 4
        Should -Invoke Invoke-RestMethod -Exactly 1 -ModuleName HibobCustomFieldSync
    }

    It 'retries with dot-style selector on 400 and returns employees' {
        # Slash-style body contains '/' between category and field; dot-style uses '.'
        Mock Invoke-RestMethod -ModuleName HibobCustomFieldSync -ParameterFilter {
            $Body -like '*category_placeholder/field_placeholder*'
        } -MockWith { throw '400 Bad Request' }

        Mock Invoke-RestMethod -ModuleName HibobCustomFieldSync -ParameterFilter {
            $Body -like '*category_placeholder.field_placeholder*'
        } -MockWith { $fixtureEmployees }

        $result = Get-HiBobPeople -Token 'abc123' -CategoryId 'category_placeholder' -FieldId 'field_placeholder'
        $result.Count | Should -Be 4
        Should -Invoke Invoke-RestMethod -Exactly 2 -ModuleName HibobCustomFieldSync
    }
}

# ─────────────────────────────────────────────
#  Invoke-FieldSync
# ─────────────────────────────────────────────
Describe 'Invoke-FieldSync' {
    BeforeAll {
        $employees = (Get-Content (Join-Path $PSScriptRoot 'fixtures/employees-5.json') | ConvertFrom-Json).employees

        # CSV: 2 changes + 1 no-change + 1 not-found (frank is absent from employees)
        $csvRows = @(
            @{ Email = 'alice@example.com'; Value = 'New Role A' }
            @{ Email = 'bob@example.com';   Value = 'New Role B' }
            @{ Email = 'carol@example.com'; Value = 'Unchanged Role' }
            @{ Email = 'frank@example.com'; Value = 'Any Role' }
        )

        $commonParams = @{
            CsvRows    = $csvRows
            Employees  = $employees
            Token      = 'test-token'
            CategoryId = 'category_placeholder'
            FieldId    = 'field_placeholder'
        }
    }

    It 'dry-run: Applied=0 and Set-HiBobCustomField is not invoked' {
        Mock Set-HiBobCustomField -ModuleName HibobCustomFieldSync -MockWith { $null }

        $result = Invoke-FieldSync @commonParams -DryRun $true

        $result.Applied  | Should -Be 0
        $result.Planned  | Should -Be 2
        $result.NoChange | Should -Be 1
        $result.NotFound | Should -Be 1
        Should -Invoke Set-HiBobCustomField -Exactly 0 -ModuleName HibobCustomFieldSync
    }

    It 'live run: Applied=2 and Set-HiBobCustomField called twice' {
        Mock Set-HiBobCustomField -ModuleName HibobCustomFieldSync -MockWith { $null }

        $result = Invoke-FieldSync @commonParams -DryRun $false

        $result.Applied | Should -Be 2
        $result.Failed  | Should -Be 0
        Should -Invoke Set-HiBobCustomField -Exactly 2 -ModuleName HibobCustomFieldSync
    }

    It 'rate-limit: Start-Sleep called exactly once when Applied hits batch boundary' {
        Mock Set-HiBobCustomField -ModuleName HibobCustomFieldSync -MockWith { $null }
        Mock Start-Sleep -ModuleName HibobCustomFieldSync -MockWith { $null }

        # batch=1 means sleep after every write; we have 2 writes → sleep called twice
        # Use batch=2 → exactly 1 sleep call when Applied reaches 2
        Invoke-FieldSync @commonParams -DryRun $false -RateLimitBatch 2 -RateLimitSleepSecs 0

        Should -Invoke Start-Sleep -Exactly 1 -ModuleName HibobCustomFieldSync
    }

    It 'partial failure: Failed counter incremented, result returned (not thrown)' {
        Mock Set-HiBobCustomField -ModuleName HibobCustomFieldSync -MockWith { throw 'API error' }

        $result = Invoke-FieldSync @commonParams -DryRun $false

        $result.Failed  | Should -Be 2
        $result.Applied | Should -Be 0
    }

    It 'TestUserEmail filter: only matching row processed' {
        Mock Set-HiBobCustomField -ModuleName HibobCustomFieldSync -MockWith { $null }

        $result = Invoke-FieldSync @commonParams -DryRun $false -TestUserEmail 'alice@example.com'

        $result.Planned  | Should -Be 1
        $result.Applied  | Should -Be 1
        Should -Invoke Set-HiBobCustomField -Exactly 1 -ModuleName HibobCustomFieldSync
    }

    It 'TestUserEmail filter: throws if email not in HiBob' {
        {
            Invoke-FieldSync @commonParams -DryRun $true -TestUserEmail 'frank@example.com'
        } | Should -Throw "*not found in HiBob*"
    }
}
