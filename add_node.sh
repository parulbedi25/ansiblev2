#!/bin/bash
set -euo pipefail
# ----------------------------------
# Parse KEY=VALUE CLI arguments
# ----------------------------------
for arg in "$@"; do
 case $arg in
   os=*) AGENT_OS="${arg#*=}" ;;
   jenkins_host=*) JENKINS_URL="${arg#*=}" ;;
   jenkins_user=*) JENKINS_USER="${arg#*=}" ;;
   jenkins_token=*) JENKINS_TOKEN="${arg#*=}" ;;
   node_name=*) NODE_NAME="${arg#*=}" ;;
   executors=*) AGENT_JENKINS_EXECUTERS="${arg#*=}" ;;
   label=*) AGENT_LABEL="${arg#*=}" ;;
   java_path=*) JAVA_PATH="${arg#*=}" ;;
   remote_fs=*) REMOTE_FS="${arg#*=}" ;;
   remote_host=*|agent_ip=*) REMOTE_HOST="${arg#*=}" ;;
   remote_user=*|agent_user=*) REMOTE_USER="${arg#*=}" ;;
   remote_pass=*|agent_password=*) REMOTE_PASS="${arg#*=}" ;;
   cred_id=*) CRED_ID="${arg#*=}" ;;
   *) echo "❌ Unknown parameter: $arg"; exit 1 ;;
 esac
done
# ----------------------------------
# Defaults
# ----------------------------------
AGENT_OS="${AGENT_OS:-windows}"
AGENT_OS=$(echo "${AGENT_OS}" | tr '[:upper:]' '[:lower:]')
AGENT_JENKINS_EXECUTERS="${AGENT_JENKINS_EXECUTERS:-2}"
AGENT_LABEL="${AGENT_LABEL:-$AGENT_OS}"
MAX_RETRIES=20
SLEEP_INTERVAL=15
if [ "${AGENT_OS}" != "windows" ] && [ "${AGENT_OS}" != "linux" ]; then
  echo "Unsupported os: ${AGENT_OS}. Use 'windows' or 'linux'."
  exit 1
fi
# ----------------------------------
# Validation
# ----------------------------------
required_vars=(JENKINS_URL JENKINS_USER JENKINS_TOKEN NODE_NAME REMOTE_HOST REMOTE_USER REMOTE_PASS)
for var in "${required_vars[@]}"; do
 [[ -z "${!var:-}" ]] && { echo "❌ Missing required parameter: ${var,,}"; exit 1; }
done
if [ "${AGENT_OS}" = "linux" ]; then
  DEFAULT_JAVA_PATH="/usr/lib/jvm/java-17-openjdk-amd64/bin/java"
  if [ "${REMOTE_USER}" = "root" ]; then
    DEFAULT_REMOTE_FS="/root/jenkins"
  else
    DEFAULT_REMOTE_FS="/home/${REMOTE_USER}/jenkins"
  fi
else
  DEFAULT_JAVA_PATH="C:\\Java\\jdk17\\bin\\java.exe"
  DEFAULT_REMOTE_FS="C:\\Jenkins"
fi

JAVA_PATH="${JAVA_PATH:-$DEFAULT_JAVA_PATH}"
REMOTE_FS="${REMOTE_FS:-$DEFAULT_REMOTE_FS}"
CRED_ID="${CRED_ID:-$NODE_NAME}"
AUTH="$JENKINS_USER:$JENKINS_TOKEN"
echo "🔹 Jenkins URL  : $JENKINS_URL"
echo "🔹 Node Name    : $NODE_NAME"
echo "🔹 Remote Host  : $REMOTE_HOST"
echo "🔹 Label        : $AGENT_LABEL"
echo "🔹 Java Path    : $JAVA_PATH"
echo "🔹 Remote FS    : $REMOTE_FS"
# ----------------------------------
# Helper: Run commands on remote host via Ansible
# ----------------------------------
run_remote_windows() {
  local ps_command="$1"
  local vars_file
  vars_file=$(mktemp /tmp/ansible_vars_XXXXXX.json)
  python3 -c "
import json, sys
print(json.dumps({
    'ansible_user': sys.argv[1],
    'ansible_password': sys.argv[2],
    'ansible_connection': 'winrm',
    'ansible_winrm_transport': 'basic',
    'ansible_winrm_server_cert_validation': 'ignore',
    'ansible_port': 5985,
    'ansible_winrm_scheme': 'http'
}))
" "$REMOTE_USER" "$REMOTE_PASS" > "$vars_file"
  ansible -i "${REMOTE_HOST}," \
    -m win_shell \
    -a "${ps_command}" \
    -e "@${vars_file}" \
    all
  local rc=$?
  rm -f "$vars_file"
  return $rc
}

run_remote_linux() {
  local shell_command="$1"
  local vars_file
  vars_file=$(mktemp /tmp/ansible_vars_XXXXXX.json)
  python3 -c "
import json, sys
print(json.dumps({
    'ansible_user': sys.argv[1],
    'ansible_password': sys.argv[2],
    'ansible_connection': 'ssh',
    'ansible_ssh_common_args': '-o StrictHostKeyChecking=no',
    'ansible_become_pass': sys.argv[2],
    'ansible_become_method': 'sudo',
    'ansible_python_interpreter': '/usr/bin/python3'
}))
" "$REMOTE_USER" "$REMOTE_PASS" > "$vars_file"
  ansible -i "${REMOTE_HOST}," \
    -m shell \
    -a "${shell_command}" \
    -e "@${vars_file}" \
    -b \
    all
  local rc=$?
  rm -f "$vars_file"
  return $rc
}

run_remote() {
  if [ "${AGENT_OS}" = "linux" ]; then
    run_remote_linux "$1"
  else
    run_remote_windows "$1"
  fi
}
# ----------------------------------
# Ensure remote directory and Java exist on target
# ----------------------------------
if [ "${AGENT_OS}" = "linux" ]; then
  echo "Preparing remote Linux machine..."
  run_remote "
    set -e
    mkdir -p '${REMOTE_FS}'
    mkdir -p '${REMOTE_FS}/remoting'
    if [ '${REMOTE_USER}' != 'root' ]; then
      chown -R '${REMOTE_USER}':'${REMOTE_USER}' '${REMOTE_FS}'
    fi
    if [ ! -x '${JAVA_PATH}' ]; then
      if ! command -v java >/dev/null 2>&1; then
        echo 'Java not found at ${JAVA_PATH}'; exit 1
      fi
    fi
    echo 'Remote directory and Java verified'
  "
else
  echo "Preparing remote Windows machine..."
  run_remote "
    if (!(Test-Path '${REMOTE_FS}')) { New-Item -ItemType Directory -Path '${REMOTE_FS}' -Force }
    if (!(Test-Path '${JAVA_PATH}')) { Write-Error 'Java not found at ${JAVA_PATH}'; exit 1 }
    Write-Output 'Remote directory and Java verified'
  "
fi
# ----------------------------------
# Fetch CSRF Crumb
# ----------------------------------
echo "1️⃣ Fetching CSRF crumb..."
CRUMB=$(curl -fsS -u "$AUTH" \
 "$JENKINS_URL/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")
echo "✅ Crumb fetched"
# ----------------------------------
# ----------------------------------
# Create Credentials (Idempotent)
# ----------------------------------
echo "Ensuring Jenkins credential exists for node access..."
ENCODED_CRED_ID=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$CRED_ID")
TMP_CRED_FILE=$(mktemp /tmp/jenkins_cred_check_XXXXXX.json)
CRED_STATUS=$(curl -sS -u "$AUTH" \
  -o "$TMP_CRED_FILE" \
  -w "%{http_code}" \
  "$JENKINS_URL/credentials/store/system/domain/_/credential/$ENCODED_CRED_ID/api/json")

if [[ "$CRED_STATUS" == "200" ]] && grep -q "\"id\"[[:space:]]*:[[:space:]]*\"$CRED_ID\"" "$TMP_CRED_FILE"; then
  echo "Credential '$CRED_ID' already exists. Skipping."
else
  CRED_PAYLOAD=$(cat <<EOF
{
  "": "0",
  "credentials": {
    "scope": "GLOBAL",
    "id": "$CRED_ID",
    "username": "$REMOTE_USER",
    "password": "$REMOTE_PASS",
    "description": "Auto-created credentials for node $NODE_NAME",
    "\$class": "com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl"
  }
}
EOF
)

  curl -fsS -X POST \
    "$JENKINS_URL/credentials/store/system/domain/_/createCredentials" \
    --user "$AUTH" \
    -H "$CRUMB" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "json=$CRED_PAYLOAD"

  echo "Credentials created: $CRED_ID"
fi
rm -f "$TMP_CRED_FILE"
# Create / Recreate Jenkins JNLP Node
# ----------------------------------
echo "2️⃣ Creating Jenkins JNLP agent node..."
if curl -fsS -u "$AUTH" "$JENKINS_URL/computer/$NODE_NAME/api/json" >/dev/null 2>&1; then
 echo "ℹ️ Node '$NODE_NAME' already exists. Deleting..."
 curl -fsS -X POST "$JENKINS_URL/computer/$NODE_NAME/doDelete" \
   --user "$AUTH" -H "$CRUMB"
 sleep 3
fi
curl -fsS -X POST \
 "$JENKINS_URL/computer/doCreateItem" \
 --user "$AUTH" \
 -H "$CRUMB" \
 -H "Content-Type: application/x-www-form-urlencoded" \
 --data-urlencode "name=$NODE_NAME" \
 --data-urlencode "type=hudson.slaves.DumbSlave" \
 --data-urlencode "json={
   \"name\": \"$NODE_NAME\",
   \"nodeDescription\": \"Auto-created JNLP Agent\",
   \"numExecutors\": \"$AGENT_JENKINS_EXECUTERS\",
   \"remoteFS\": \"$REMOTE_FS\",
   \"labelString\": \"$AGENT_LABEL\",
   \"mode\": \"EXCLUSIVE\",
   \"launcher\": {
     \"stapler-class\": \"hudson.slaves.JNLPLauncher\"
   },
   \"retentionStrategy\": {
     \"stapler-class\": \"hudson.slaves.RetentionStrategy\$Always\"
   }
 }"
echo "✅ Node created"
# ----------------------------------
# Download agent.jar on remote machine
# ----------------------------------
echo "3) Stopping old agent and downloading agent.jar on remote machine..."
if [ "${AGENT_OS}" = "linux" ]; then
  run_remote "
    set -e
    if systemctl list-unit-files | grep -q 'jenkins-agent-${NODE_NAME}.service'; then
      systemctl stop jenkins-agent-${NODE_NAME}.service || true
      systemctl disable jenkins-agent-${NODE_NAME}.service || true
      rm -f /etc/systemd/system/jenkins-agent-${NODE_NAME}.service
      systemctl daemon-reload || true
    fi
    # Avoid matching this shell command: only kill java processes running agent.jar
    if [ '${REMOTE_USER}' != 'root' ]; then
      pkill -u '${REMOTE_USER}' -f '[j]ava.*agent\.jar' || true
    else
      pkill -f '[j]ava.*agent\.jar' || true
    fi
    curl -fsS -o '${REMOTE_FS}/agent.jar' '${JENKINS_URL}jnlpJars/agent.jar'
    if [ ! -f '${REMOTE_FS}/agent.jar' ]; then
      echo 'Failed to download agent.jar'; exit 1
    fi
    if [ '${REMOTE_USER}' != 'root' ]; then
      chown '${REMOTE_USER}':'${REMOTE_USER}' '${REMOTE_FS}/agent.jar'
    fi
  "
else
  run_remote "
    # Stop any existing scheduled task holding agent.jar
    \$taskName = 'JenkinsAgent-${NODE_NAME}'
    \$task = Get-ScheduledTask -TaskName \$taskName -ErrorAction SilentlyContinue
    if (\$task) {
      Stop-ScheduledTask -TaskName \$taskName -ErrorAction SilentlyContinue
      Unregister-ScheduledTask -TaskName \$taskName -Confirm:\$false -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 2
    }
    # Kill any remaining java processes using agent.jar
    Get-WmiObject Win32_Process -Filter {CommandLine LIKE '%agent.jar%'} | ForEach-Object { \$_.Terminate() } 2>\$null
    Start-Sleep -Seconds 2
    \$agentUrl = '${JENKINS_URL}jnlpJars/agent.jar'
    \$dest = '${REMOTE_FS}\\agent.jar'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri \$agentUrl -OutFile \$dest -UseBasicParsing
    if (Test-Path \$dest) { Write-Output 'agent.jar downloaded successfully' } else { Write-Error 'Failed to download agent.jar'; exit 1 }
  "
fi
# ----------------------------------
# Fetch JNLP Secret
# ----------------------------------
echo "4️⃣ Fetching JNLP secret..."
SECRET=$(curl -fsS -u "$AUTH" \
 --data-urlencode "script=println(jenkins.model.Jenkins.getInstance().getComputer('${NODE_NAME}').getJnlpMac())" \
 "$JENKINS_URL/scriptText")
SECRET=$(echo "$SECRET" | tr -d '[:space:]')
[[ -z "$SECRET" ]] && { echo "❌ Failed to retrieve JNLP secret"; exit 1; }
echo "✅ Secret fetched: ${SECRET:0:12}..."
# ----------------------------------
# Start JNLP Agent on remote machine
# ----------------------------------
echo "5) Starting Jenkins JNLP agent on remote machine..."
if [ "${AGENT_OS}" = "linux" ]; then
  run_remote "
    set -e
    mkdir -p '${REMOTE_FS}/remoting'
    if [ '${REMOTE_USER}' != 'root' ]; then
      chown -R '${REMOTE_USER}':'${REMOTE_USER}' '${REMOTE_FS}'
    fi
    SERVICE_FILE=/etc/systemd/system/jenkins-agent-${NODE_NAME}.service
    cat > \"\${SERVICE_FILE}\" <<EOF
[Unit]
Description=Jenkins Agent ${NODE_NAME}
After=network.target

[Service]
User=${REMOTE_USER}
WorkingDirectory=${REMOTE_FS}
ExecStart=${JAVA_PATH} -jar ${REMOTE_FS}/agent.jar -url ${JENKINS_URL} -name ${NODE_NAME} -secret ${SECRET} -webSocket -workDir ${REMOTE_FS}/remoting
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now jenkins-agent-${NODE_NAME}.service
    systemctl is-active --quiet jenkins-agent-${NODE_NAME}.service
  "
else
  REMOTE_FS_WIN=$(echo "$REMOTE_FS" | sed 's|/|\\|g')
  run_remote "
    \$remotingDir = '${REMOTE_FS_WIN}\\remoting'
    if (!(Test-Path \$remotingDir)) { New-Item -ItemType Directory -Path \$remotingDir -Force }
    \$taskName = 'JenkinsAgent-${NODE_NAME}'
    # Remove existing scheduled task if present
    Unregister-ScheduledTask -TaskName \$taskName -Confirm:\$false -ErrorAction SilentlyContinue
    # Create a scheduled task that runs independently of WinRM session
    \$action = New-ScheduledTaskAction -Execute '${JAVA_PATH}' -Argument '-jar \"${REMOTE_FS_WIN}\\agent.jar\" -url ${JENKINS_URL} -name ${NODE_NAME} -secret ${SECRET} -webSocket -workDir \"${REMOTE_FS_WIN}\\remoting\"' -WorkingDirectory '${REMOTE_FS_WIN}'
    \$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 365)
    Register-ScheduledTask -TaskName \$taskName -Action \$action -Settings \$settings -User 'SYSTEM' -RunLevel Highest -Force
    # Start it immediately
    Start-ScheduledTask -TaskName \$taskName
    Start-Sleep -Seconds 5
    \$task = Get-ScheduledTask -TaskName \$taskName
    Write-Output \"Task state: \$(\$task.State)\"
    if (\$task.State -eq 'Running') {
      Write-Output 'Jenkins JNLP agent started as scheduled task'
    } else {
      Write-Error 'Failed to start Jenkins agent task. Check java path and agent.jar on remote machine.'
      exit 1
    }
  "
fi
# ----------------------------------
# Wait for agent to come online
# ----------------------------------
echo "6️⃣ Waiting for agent to come online..."
for i in $(seq 1 $MAX_RETRIES); do
  STATUS=$(curl -fsS -u "$AUTH" "$JENKINS_URL/computer/$NODE_NAME/api/json" 2>/dev/null | grep -o '"offline" *: *false' || true)
  if [[ -n "$STATUS" ]]; then
    echo "✅ Agent '$NODE_NAME' is online!"
    exit 0
  fi
  echo "   Attempt $i/$MAX_RETRIES - agent not online yet, waiting ${SLEEP_INTERVAL}s..."
  sleep "$SLEEP_INTERVAL"
done
echo "⚠️ Agent did not come online within $((MAX_RETRIES * SLEEP_INTERVAL)) seconds. Fetching diagnostics from remote machine..."
if [ "${AGENT_OS}" = "linux" ]; then
  run_remote "
    echo '--- Service Status ---'
    systemctl status jenkins-agent-${NODE_NAME}.service --no-pager || true
    echo '--- Last 30 Journal Lines ---'
    journalctl -u jenkins-agent-${NODE_NAME}.service --no-pager -n 30 || true
    echo '--- Java Version at configured path ---'
    ${JAVA_PATH} -version 2>&1 || echo 'Java not found at ${JAVA_PATH}'
    echo '--- Network check to Jenkins ---'
    curl -fsS --max-time 5 '${JENKINS_URL}' -o /dev/null && echo 'Jenkins reachable' || echo 'Jenkins NOT reachable from remote machine'
  " || true
fi
exit 1
