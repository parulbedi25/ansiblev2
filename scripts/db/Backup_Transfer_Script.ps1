param(
    [string]$PgUser = "postgres",
    [int]$PgPort = 5432,
    [string]$PgPassword = "Welcom3!",

    [string]$CouchUser = "admin",
    [string]$CouchPassword = "Welcom3!",
    [string]$CouchHost = "localhost",
    [int]$CouchPort = 5984,

    [string]$SCPUser = "copper",
    [string]$SCPHost = "10.10.3.158",
    [string]$SCPPassword = "Bebo@2028",
    [string]$RemoteBackupRoot = "E:/DB/backup",
    [string]$HostKey = "",
    [string]$BuildNumber = ""
)

# ==============================
# 📁 Root + Timestamp Structure
# ==============================

$RootDir = "D:\QASIP\Backup"
if ($BuildNumber) {
    # Primary format to avoid timestamp collision in CI runs.
    $Timestamp = "$(Get-Date -Format 'dd-MM-yyyy-HH')-build$BuildNumber"
} else {
    # Backward-compatible fallback for manual/scripted non-CI runs.
    $Timestamp = Get-Date -Format "dd-MM-yyyy-HHmmss"
}
Write-Host "BACKUP_TIMESTAMP=$Timestamp"

$BaseBackupPath = Join-Path $RootDir $Timestamp

$PgBackupDir = "$BaseBackupPath\postgres"
$CouchBackupDir = "$BaseBackupPath\couchdb"
$KnowledgeBaseBackupDir = "$BaseBackupPath\knowledge_base"
$LogDir = "$BaseBackupPath\logs"

# Create directories
foreach ($dir in @($PgBackupDir, $CouchBackupDir, $KnowledgeBaseBackupDir, $LogDir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

# ==============================
# 🐘 PostgreSQL Backup
# ==============================

Write-Host "`n=== PostgreSQL Backup ==="

$PgBackupFile = "$PgBackupDir\fulldb.sql"

$env:PGPASSWORD = $PgPassword
$env:PGCLIENTENCODING = "UTF8"

pg_dumpall -U $PgUser -p $PgPort -f $PgBackupFile

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: PostgreSQL backup failed"
    exit 1
}

Remove-Item Env:PGPASSWORD
Remove-Item Env:PGCLIENTENCODING

Write-Host "PostgreSQL backup completed."

# ==============================
# 🛋️ CouchDB Backup
# ==============================

Write-Host "`n=== CouchDB Backup ==="

try {
    $pair = "$CouchUser`:$CouchPassword"
    $encodedCreds = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
    $headers = @{ Authorization = "Basic $encodedCreds" }

    $allDbsUrl = "http://$CouchHost`:$CouchPort/_all_dbs"
    $dbs = Invoke-RestMethod -Uri $allDbsUrl -Headers $headers -Method Get

    $userDbs = $dbs | Where-Object { $_ -notmatch "^_" }

    foreach ($db in $userDbs) {
        Write-Host "Backing up database: $db"

        $backupUrl = "http://$CouchHost`:$CouchPort/$db/_all_docs?include_docs=true"
        $outputFile = Join-Path $CouchBackupDir "$($db)_backup.json"

        Invoke-WebRequest -Uri $backupUrl -Headers $headers -OutFile $outputFile
    }

    Write-Host "CouchDB backup completed."

} catch {
    Write-Host "ERROR: CouchDB backup failed"
    exit 1
}

# ==============================
# 📦 Knowledge Base Copy
# ==============================

Write-Host "`n=== Knowledge Base Copy ==="

$SourceKBPath = "D:\QASIP\Apps\python-ai-service\test_script_generator"
$KBTargetPath = "$KnowledgeBaseBackupDir\test_script_generator"

if (Test-Path $SourceKBPath) {

    robocopy $SourceKBPath $KBTargetPath /E /Z /R:3 /W:5 /NFL /NDL /NP /XD "$SourceKBPath\ai_aenv"

    if ($LASTEXITCODE -le 3) {
        Write-Host "Knowledge Base copied successfully."
    } else {
        Write-Host "ERROR: Knowledge Base copy failed"
        exit 1
    }

} else {
    Write-Host "ERROR: Source path not found: $SourceKBPath"
    exit 1
}

# ==============================
# 📦 SCP Transfer (Only Latest Snapshot)
# ==============================

Write-Host "`n=== SCP Transfer ==="

if (-not $HostKey) {
    Write-Host "ERROR: HostKey parameter is required for secure SCP transfer."
    exit 1
}

plink -pw $SCPPassword -batch -hostkey "$HostKey" $SCPUser@$SCPHost exit

$RemotePath = $RemoteBackupRoot
$RemotePathWin = $RemotePath -replace '/', '\'
$RemoteCmd = "cmd /c if not exist `"$RemotePathWin`" mkdir `"$RemotePathWin`""

Write-Host "Using remote backup path: $RemotePath"

plink -pw $SCPPassword -batch -hostkey "$HostKey" $SCPUser@$SCPHost $RemoteCmd
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to create remote backup directory at '$RemotePath'"
    exit 1
}

pscp -pw $SCPPassword -batch -hostkey "$HostKey" -r "$BaseBackupPath" "${SCPUser}@${SCPHost}:$RemotePath"

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: SCP transfer failed"
    exit 1
}

Write-Host "Transfer completed."

# # ==============================
# # 🧹 Retention Policy (Keep Last 7 Backups)
# # ==============================

# Get-ChildItem $RootDir |
# Where-Object { $_.PSIsContainer } |
# Sort-Object Name -Descending |
# Select-Object -Skip 7 |
# Remove-Item -Recurse -Force

# ==============================
# ✅ DONE
# ==============================

Write-Host "`nBackup completed successfully: $BaseBackupPath"
