param(
    [string]$PgUser = "postgres",
    [int]$PgPort = 5432,
    [string]$PgPassword = "Welcom3!",
    [string]$PgBinDir = "D:\\QASIP\\Apps\\postgres\\bin",

    [string]$CouchUser = "admin",
    [string]$CouchPassword = "Welcom3!",
    [string]$CouchHost = "localhost",
    [int]$CouchPort = 5984,

    [string]$RestoreRoot = "D:\\QASIP\\Backup",
    [string]$RestoreTimestamp = "",
    [string]$KnowledgeBaseTarget = "D:\\QASIP\\Apps\\python-ai-service\\test_script_generator"
)

Write-Host "`n================ RESTORE START ================"

if (-not (Test-Path $RestoreRoot)) {
    Write-Host "ERROR: Restore root not found: $RestoreRoot"
    exit 1
}

if ($RestoreTimestamp) {
    $SnapshotDir = Join-Path $RestoreRoot $RestoreTimestamp
    if (-not (Test-Path $SnapshotDir)) {
        Write-Host "ERROR: Requested restore snapshot not found: $SnapshotDir"
        exit 1
    }
} else {
    $LatestSnapshot = Get-ChildItem -Path $RestoreRoot -Directory |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if (-not $LatestSnapshot) {
        Write-Host "ERROR: No backup snapshots found under: $RestoreRoot"
        exit 1
    }

    $SnapshotDir = $LatestSnapshot.FullName
}

Write-Host "Using restore snapshot: $SnapshotDir"

$PsqlExe = Join-Path $PgBinDir "psql.exe"
if (-not (Test-Path $PsqlExe)) {
    $cmd = Get-Command psql.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $PsqlExe = $cmd.Source
    }
}

if (-not (Test-Path $PsqlExe)) {
    Write-Host "ERROR: psql.exe not found. Checked PgBinDir: $PgBinDir and PATH."
    exit 1
}

Write-Host "Using psql executable: $PsqlExe"

# ==============================
# PostgreSQL Restore
# ==============================

Write-Host "`n=== PostgreSQL Restore ==="

$PgBackupFile = Join-Path $SnapshotDir "postgres\\fulldb.sql"
if (-not (Test-Path $PgBackupFile)) {
    Write-Host "ERROR: PostgreSQL backup file not found: $PgBackupFile"
    exit 1
}

$env:PGPASSWORD = $PgPassword
& "$PsqlExe" -U $PgUser -p $PgPort -f $PgBackupFile
if ($LASTEXITCODE -ne 0) {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    Write-Host "ERROR: PostgreSQL restore failed"
    exit 1
}
Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
Write-Host "PostgreSQL restore completed."

# ==============================
# CouchDB Restore
# ==============================

Write-Host "`n=== CouchDB Restore ==="

$CouchBackupDir = Join-Path $SnapshotDir "couchdb"
if (-not (Test-Path $CouchBackupDir)) {
    Write-Host "ERROR: CouchDB backup directory not found: $CouchBackupDir"
    exit 1
}

$CouchFiles = Get-ChildItem -Path $CouchBackupDir -Filter "*_backup.json" -File
if (-not $CouchFiles) {
    Write-Host "ERROR: No CouchDB backup files found in: $CouchBackupDir"
    exit 1
}

$pair = "$CouchUser`:$CouchPassword"
$encodedCreds = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
$headers = @{ Authorization = "Basic $encodedCreds" }

foreach ($file in $CouchFiles) {
    $db = $file.BaseName -replace "_backup$", ""
    Write-Host "Restoring CouchDB database: $db"
    $dbEscaped = [uri]::EscapeDataString($db)
    $dbUri = "http://$CouchHost`:$CouchPort/$dbEscaped"

    try {
        $content = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
        $docs = @()
        if ($content.rows) {
            $docs = @($content.rows | ForEach-Object { $_.doc } | Where-Object { $_ })
        }

        # Delete DB if exists (ignore 404)
        try {
            Invoke-WebRequest -Uri $dbUri -Headers $headers -Method Delete -UseBasicParsing -ErrorAction Stop | Out-Null
        } catch {
            $statusCode = $null
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            if ($statusCode -ne 404) {
                throw
            }
        }

        # Ensure deletion is reflected before recreate (avoids race)
        for ($i = 0; $i -lt 30; $i++) {
            try {
                Invoke-WebRequest -Uri $dbUri -Headers $headers -Method Get -UseBasicParsing -ErrorAction Stop | Out-Null
                Start-Sleep -Seconds 1
            } catch {
                $statusCode = $null
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
                if ($statusCode -eq 404) {
                    break
                }
                Start-Sleep -Seconds 1
            }
        }

        # Create DB (treat 412 as already created)
        $created = $false
        for ($i = 0; $i -lt 15; $i++) {
            try {
                Invoke-WebRequest -Uri $dbUri -Headers $headers -Method Put -UseBasicParsing -ErrorAction Stop | Out-Null
                $created = $true
                break
            } catch {
                $statusCode = $null
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
                if ($statusCode -eq 412) {
                    $created = $true
                    break
                }
                Start-Sleep -Seconds 1
            }
        }
        if (-not $created) {
            throw "Failed to create CouchDB database '$db'"
        }

        # Verify DB exists in _all_dbs before posting docs
        $dbReady = $false
        for ($i = 0; $i -lt 30; $i++) {
            try {
                $allDbs = Invoke-RestMethod -Uri "http://$CouchHost`:$CouchPort/_all_dbs" -Headers $headers -Method Get -ErrorAction Stop
                if ($allDbs -contains $db) {
                    $dbReady = $true
                    break
                }
            } catch {
                # keep retrying on transient errors
            }
            Start-Sleep -Seconds 1
        }
        if (-not $dbReady) {
            throw "Database '$db' is not available after create."
        }

        if ($docs.Count -gt 0) {
            $bulkBody = @{ docs = $docs; new_edits = $false } | ConvertTo-Json -Depth 100
            $bulkBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bulkBody)
            Invoke-WebRequest -Uri "http://$CouchHost`:$CouchPort/$dbEscaped/_bulk_docs" -Headers $headers -Method Post -UseBasicParsing -ContentType "application/json; charset=utf-8" -Body $bulkBodyBytes -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-Host "ERROR: CouchDB restore failed for database '$db'"
        Write-Host $_
        exit 1
    }
}

Write-Host "CouchDB restore completed."

# ==============================
# Knowledge Base Restore
# ==============================

Write-Host "`n=== Knowledge Base Restore ==="

$KnowledgeBaseSource = Join-Path $SnapshotDir "knowledge_base\\test_script_generator"
if (-not (Test-Path $KnowledgeBaseSource)) {
    Write-Host "ERROR: Knowledge Base backup directory not found: $KnowledgeBaseSource"
    exit 1
}

if (-not (Test-Path $KnowledgeBaseTarget)) {
    New-Item -ItemType Directory -Path $KnowledgeBaseTarget -Force | Out-Null
}

$KnowledgeBaseLog = Join-Path $SnapshotDir "logs\\knowledge_base_restore.log"
$KnowledgeBaseLogDir = Split-Path -Path $KnowledgeBaseLog -Parent
if (-not (Test-Path $KnowledgeBaseLogDir)) {
    New-Item -ItemType Directory -Path $KnowledgeBaseLogDir -Force | Out-Null
}
robocopy $KnowledgeBaseSource $KnowledgeBaseTarget /E /Z /R:2 /W:3 /NFL /NDL /XO /NP /LOG:$KnowledgeBaseLog
$RoboExitCode = $LASTEXITCODE
if ($RoboExitCode -gt 3) {
    Write-Host "ERROR: Knowledge Base restore failed. Robocopy exit code: $RoboExitCode"
    Write-Host "See log: $KnowledgeBaseLog"
    exit 1
}

Write-Host "Knowledge Base restore completed. Robocopy exit code: $RoboExitCode"
Write-Host "Knowledge Base target: $KnowledgeBaseTarget"

Write-Host "`n=========== RESTORE COMPLETED ==========="
