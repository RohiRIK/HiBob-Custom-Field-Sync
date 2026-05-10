pipeline {
    agent any

    parameters {
        string(
            name        : 'TICKET_ID',
            defaultValue: '',
            description : 'Injected automatically by the FreshService webhook — leave empty for webhook-triggered runs. Fill in manually only for ad-hoc testing (e.g. re-run a specific ticket without waiting for a webhook).'
        )
        booleanParam(
            name        : 'DRY_RUN',
            defaultValue: true,
            description : 'When checked, logs all planned changes without writing to HiBob.'
        )
        string(
            name        : 'TEST_USER_EMAIL',
            defaultValue: '',
            description : 'Process only this email address. Leave empty to process all rows.'
        )
        string(
            name        : 'CUSTOM_CATEGORY_ID',
            defaultValue: 'category_placeholder',
            description : 'HiBob custom field category ID (e.g. category_12345).'
        )
        string(
            name        : 'CUSTOM_FIELD_ID',
            defaultValue: 'field_placeholder',
            description : 'HiBob custom field ID within the category (e.g. field_67890).'
        )
        string(
            name        : 'RATE_LIMIT_BATCH',
            defaultValue: '79',
            description : 'Number of writes before pausing to respect HiBob rate limits.'
        )
        string(
            name        : 'RATE_LIMIT_SLEEP_SECS',
            defaultValue: '120',
            description : 'Seconds to sleep between rate-limit batches.'
        )
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    environment {
        HIBOB_TOKEN            = credentials('hibob-api-token')
        FRESHSERVICE_API_KEY   = credentials('freshservice-api-key')
        FRESHSERVICE_BASE_URL  = credentials('freshservice-base-url')

        TICKET_ID              = "${params.TICKET_ID}"
        IS_DRY_RUN             = "${params.DRY_RUN}"
        TEST_USER_EMAIL        = "${params.TEST_USER_EMAIL}"
        CUSTOM_CATEGORY_ID     = "${params.CUSTOM_CATEGORY_ID}"
        CUSTOM_FIELD_ID        = "${params.CUSTOM_FIELD_ID}"
        RATE_LIMIT_BATCH       = "${params.RATE_LIMIT_BATCH}"
        RATE_LIMIT_SLEEP_SECS  = "${params.RATE_LIMIT_SLEEP_SECS}"

        CSV_PATH               = "${WORKSPACE}/job-roles.csv"

        DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = '1'
    }

    stages {
        stage('Validate Environment') {
            steps {
                script {
                    sh '''
                        # --- OS check ---
                        OS=$(uname -s)
                        if [ "$OS" != "Linux" ]; then
                            echo "ERROR: This pipeline requires Linux. Detected OS: $OS"
                            exit 1
                        fi
                        echo "OS: $OS"

                        # --- PowerShell check ---
                        if ! command -v pwsh > /dev/null 2>&1; then
                            echo "ERROR: PowerShell Core (pwsh) is not installed on this agent."
                            exit 1
                        fi

                        PWSH_VERSION=$(pwsh --version)
                        echo "$PWSH_VERSION"

                        VERSION_NUM=$(echo "$PWSH_VERSION" | sed 's/[^0-9.]//g')
                        MAJOR=$(echo "$VERSION_NUM" | cut -d. -f1)
                        MINOR=$(echo "$VERSION_NUM" | cut -d. -f2)
                        if [ "${MAJOR:-0}" -lt 7 ] || { [ "${MAJOR:-0}" -eq 7 ] && [ "${MINOR:-0}" -lt 4 ]; }; then
                            echo "WARNING: PowerShell ${MAJOR}.${MINOR} detected. Recommended: 7.4 or later."
                        fi

                        # --- Required env vars (non-secret) ---
                        ERRORS=0
                        for VAR in TICKET_ID CUSTOM_CATEGORY_ID CUSTOM_FIELD_ID CSV_PATH; do
                            VAL=$(eval "echo \$$VAR")
                            if [ -z "$VAL" ]; then
                                echo "ERROR: Environment variable $VAR is not set"
                                ERRORS=$((ERRORS + 1))
                            else
                                echo "$VAR is set"
                            fi
                        done

                        # Secret vars: confirm they exist (length > 0)
                        for VAR in HIBOB_TOKEN FRESHSERVICE_API_KEY FRESHSERVICE_BASE_URL; do
                            VAL=$(eval "echo \$$VAR")
                            if [ -z "$VAL" ]; then
                                echo "ERROR: Credential $VAR is empty — check Jenkins credential store"
                                ERRORS=$((ERRORS + 1))
                            else
                                echo "$VAR is configured"
                            fi
                        done

                        if [ "$ERRORS" -gt 0 ]; then
                            echo "Validation failed with $ERRORS error(s)"
                            exit 1
                        fi

                        echo "Environment validation passed"
                    '''
                }
            }
        }

        stage('Execute Sync') {
            steps {
                script {
                    def rc = sh(script: 'pwsh -File src/powershell/Invoke-Sync.ps1', returnStatus: true)

                    if (rc == 0) {
                        currentBuild.description = "Sync complete — ticket ${params.TICKET_ID}"
                    } else if (rc == 2) {
                        currentBuild.result      = 'UNSTABLE'
                        currentBuild.description = "Partial failure — ticket ${params.TICKET_ID}"
                    } else {
                        currentBuild.description = "Sync failed (exit ${rc}) — ticket ${params.TICKET_ID}"
                        error("Sync failed with exit code ${rc}")
                    }
                }
            }
        }
    }

    post {
        always {
            sh 'rm -f "$CSV_PATH"'
            echo "Build complete: ${currentBuild.result ?: 'SUCCESS'}"
        }
    }
}
