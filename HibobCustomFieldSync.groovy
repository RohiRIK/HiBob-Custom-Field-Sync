// ─────────────────────────────────────────────────────────────────────────────
// SMOKE-TEST BRANCH — no real credentials, no real API calls
// Runs Invoke-SmokeTest.ps1 with fake data to verify the agent setup and logs
// Merge this branch's changes to main when you're happy with the setup
// ─────────────────────────────────────────────────────────────────────────────

pipeline {
    agent any

    parameters {
        string(
            name        : 'TICKET_ID',
            defaultValue: 'SMOKE-001',
            description : '[SMOKE] Fake ticket ID — no real FreshService call is made on this branch.'
        )
        booleanParam(
            name        : 'DRY_RUN',
            defaultValue: true,
            description : '[SMOKE] Always true on this branch — no writes to HiBob.'
        )
    }

    options {
        timeout(time: 10, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    environment {
        TICKET_ID  = "${params.TICKET_ID}"
        IS_DRY_RUN = 'true'
        CSV_PATH   = "${WORKSPACE}/job-roles.csv"
        DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = '1'
    }

    stages {
        stage('Validate Environment') {
            steps {
                script {
                    sh '''
                        echo "=== SMOKE TEST — Validate Environment ==="

                        OS=$(uname -s)
                        echo "OS: $OS"
                        if [ "$OS" != "Linux" ]; then
                            echo "ERROR: Expected Linux, got $OS"
                            exit 1
                        fi

                        if ! command -v pwsh > /dev/null 2>&1; then
                            echo "ERROR: pwsh not found — install PowerShell Core 7.4+ on this agent"
                            exit 1
                        fi

                        PWSH_VERSION=$(pwsh --version)
                        echo "PowerShell: $PWSH_VERSION"

                        echo "Workspace: $WORKSPACE"
                        echo "Ticket ID (fake): $TICKET_ID"
                        echo "Dry run: $IS_DRY_RUN"
                        echo "Validation passed"
                    '''
                }
            }
        }

        stage('Smoke Test — Module + Fake Data') {
            steps {
                script {
                    def rc = sh(
                        script: 'pwsh -File src/powershell/Invoke-SmokeTest.ps1',
                        returnStatus: true
                    )
                    if (rc != 0) {
                        error("Smoke test failed with exit code ${rc}")
                    }
                    currentBuild.description = "Smoke test passed — agent OK"
                }
            }
        }
    }

    post {
        always {
            sh 'rm -f "$CSV_PATH"'
            echo "Smoke test complete: ${currentBuild.result ?: 'SUCCESS'}"
        }
        success {
            echo "All good — agent has pwsh, module loads, field sync logic runs correctly."
            echo "Next: switch Jenkins job to branch 'main' for the real pipeline."
        }
        failure {
            echo "Something failed — check the stage logs above."
            echo "Common causes: pwsh not installed, module syntax error, missing workspace."
        }
    }
}
