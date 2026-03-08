#!/usr/bin/env bash
# provision.sh
# Copies all config, workspace, and script files to the target VPS,
# then runs bootstrap-child.sh inside a tmux session on the remote host.
#
# Usage:
#   CHILD_VPS_HOST=1.2.3.4 \
#   CHILD_VPS_KEY_PATH=~/.ssh/id_ed25519 \
#   CHILD_LLM_API_KEY=sk-ant-... \
#   ./provision.sh
#
# Required environment variables:
#   CHILD_VPS_HOST          IP or hostname of the target VPS
#   CHILD_VPS_KEY_PATH      Path to SSH private key for the target
#   CHILD_LLM_API_KEY       LLM API key (Anthropic or other provider)
#
# Optional environment variables:
#   CHILD_VPS_USER          SSH user on target (default: root)
#   CHILD_VPS_PORT          SSH port (default: 22)
#   CHILD_LLM_PROVIDER      LLM provider string (default: anthropic)
#   CHILD_OPENCLAW_PORT     Port OpenClaw listens on (default: 18789)
#   CHILD_OPENCLAW_TOKEN    Gateway auth token (default: generated)
#   CHILD_SLACK_APP_TOKEN   Slack app-level token (xapp-...) — enables Slack
#   CHILD_SLACK_BOT_TOKEN   Slack bot token (xoxb-...)
#   CHILD_SLACK_CHANNEL     Slack channel name without # (default: general)
#   PARENT_PUBKEY_PATH      Path to parent's SSH public key (default: ~/.ssh/id_ed25519.pub)
#   REMOTE_STAGING          Staging path on remote (default: /tmp/claw-provision)

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────

HOST="${CHILD_VPS_HOST:?Need CHILD_VPS_HOST}"
SSH_USER="${CHILD_VPS_USER:-root}"
SSH_PORT="${CHILD_VPS_PORT:-22}"
KEY="${CHILD_VPS_KEY_PATH:?Need CHILD_VPS_KEY_PATH}"
LLM_API_KEY="${CHILD_LLM_API_KEY:?Need CHILD_LLM_API_KEY}"
LLM_PROVIDER="${CHILD_LLM_PROVIDER:-anthropic}"
OPENCLAW_PORT="${CHILD_OPENCLAW_PORT:-18789}"
OPENCLAW_GATEWAY_TOKEN="${CHILD_OPENCLAW_TOKEN:-$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 64)}"
SLACK_APP_TOKEN="${CHILD_SLACK_APP_TOKEN:-}"
SLACK_BOT_TOKEN="${CHILD_SLACK_BOT_TOKEN:-}"
SLACK_CHANNEL="${CHILD_SLACK_CHANNEL:-general}"
PARENT_PUBKEY_PATH="${PARENT_PUBKEY_PATH:-${HOME}/.ssh/id_ed25519.pub}"
REMOTE_STAGING="${REMOTE_STAGING:-/tmp/claw-provision}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build Slack enabled flag
if [[ -n "${SLACK_APP_TOKEN}" && -n "${SLACK_BOT_TOKEN}" ]]; then
  SLACK_ENABLED=true
else
  SLACK_ENABLED=false
fi

SSH_OPTS="-i ${KEY} -p ${SSH_PORT} -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes"
SSH="ssh ${SSH_OPTS}"
SCP="scp -i ${KEY} -P ${SSH_PORT} -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes"

log()  { echo "==> $*"; }
info() { echo "    $*"; }
warn() { echo "    ⚠  WARNING: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── Preflight checks ──────────────────────────────────────────────────────────

log "Preflight checks"

[[ -f "${KEY}" ]] || die "SSH key not found: ${KEY}"
[[ -r "${KEY}" ]] || die "SSH key not readable: ${KEY}"

[[ -f "${PARENT_PUBKEY_PATH}" ]] || {
  warn "Parent pubkey not found at ${PARENT_PUBKEY_PATH}"
  warn "The child node won't have SSH access back to this machine."
  PARENT_PUBKEY=""
}
[[ -n "${PARENT_PUBKEY:-}" ]] || PARENT_PUBKEY="$(cat "${PARENT_PUBKEY_PATH}" 2>/dev/null || echo "")"

# Check required tools on parent
for tool in ssh scp; do
  command -v "${tool}" > /dev/null 2>&1 || die "${tool} not found — required for provisioning"
done

# Check for jq (used for JSON generation)
if ! command -v jq > /dev/null 2>&1; then
  warn "jq not found. Will use envsubst or sed for config generation."
  JQ_AVAILABLE=false
else
  JQ_AVAILABLE=true
fi

# Check connectivity
log "Testing SSH connectivity to ${SSH_USER}@${HOST}:${SSH_PORT}"
$SSH "${SSH_USER}@${HOST}" "echo 'SSH OK'" \
  || die "Cannot connect to ${SSH_USER}@${HOST}:${SSH_PORT} — check host, user, key, and port"
info "Connected."

# Check for tmux on remote
log "Checking remote environment"
REMOTE_HAS_TMUX=true
$SSH "${SSH_USER}@${HOST}" "command -v tmux > /dev/null 2>&1" 2>/dev/null || REMOTE_HAS_TMUX=false

if [[ "${REMOTE_HAS_TMUX}" == "false" ]]; then
  echo ""
  warn "tmux is NOT installed on the remote host."
  warn "The bootstrap script installs tmux, but it won't be available for the"
  warn "initial run. The bootstrap will run in a background nohup process instead."
  warn "You can attach via tmux once bootstrap completes."
  warn ""
  warn "To pre-install tmux manually:"
  warn "  ssh ${SSH_USER}@${HOST} 'apt-get install -y tmux'"
  echo ""
fi

REMOTE_OS=$($SSH "${SSH_USER}@${HOST}" "cat /etc/os-release 2>/dev/null | grep '^ID=' | cut -d= -f2 | tr -d '\"'" 2>/dev/null || echo "unknown")
info "Remote OS: ${REMOTE_OS}"

# ── Generate openclaw.json from template ──────────────────────────────────────

log "Generating openclaw.json from template"

TEMPLATE="${REPO_DIR}/config/openclaw.json"
[[ -f "${TEMPLATE}" ]] || die "Template not found: ${TEMPLATE}"

RESOLVED_JSON_FILE="$(mktemp /tmp/openclaw-resolved.XXXXXX.json)"
trap 'rm -f "${RESOLVED_JSON_FILE}"' EXIT

# Export all vars needed by envsubst
export LLM_API_KEY LLM_PROVIDER OPENCLAW_PORT OPENCLAW_GATEWAY_TOKEN
export SLACK_APP_TOKEN SLACK_BOT_TOKEN SLACK_CHANNEL SLACK_ENABLED

# Substitute only our known variables (leave any others untouched)
KNOWN_VARS='${LLM_API_KEY}${LLM_PROVIDER}${OPENCLAW_PORT}${OPENCLAW_GATEWAY_TOKEN}${SLACK_APP_TOKEN}${SLACK_BOT_TOKEN}${SLACK_CHANNEL}${SLACK_ENABLED}'

if command -v envsubst > /dev/null 2>&1; then
  envsubst "${KNOWN_VARS}" < "${TEMPLATE}" > "${RESOLVED_JSON_FILE}"
else
  # Fallback: sed substitution
  sed \
    -e "s|\${LLM_API_KEY}|${LLM_API_KEY}|g" \
    -e "s|\${LLM_PROVIDER}|${LLM_PROVIDER}|g" \
    -e "s|\${OPENCLAW_PORT}|${OPENCLAW_PORT}|g" \
    -e "s|\${OPENCLAW_GATEWAY_TOKEN}|${OPENCLAW_GATEWAY_TOKEN}|g" \
    -e "s|\${SLACK_APP_TOKEN}|${SLACK_APP_TOKEN}|g" \
    -e "s|\${SLACK_BOT_TOKEN}|${SLACK_BOT_TOKEN}|g" \
    -e "s|\${SLACK_CHANNEL}|${SLACK_CHANNEL}|g" \
    -e "s|\${SLACK_ENABLED}|${SLACK_ENABLED}|g" \
    "${TEMPLATE}" > "${RESOLVED_JSON_FILE}"
fi

# Validate the resulting JSON
if [[ "${JQ_AVAILABLE}" == "true" ]]; then
  jq empty "${RESOLVED_JSON_FILE}" 2>/dev/null \
    || die "Generated openclaw.json is not valid JSON — check template substitution"
  info "openclaw.json validated OK"
fi

info "Slack: ${SLACK_ENABLED} (channel: #${SLACK_CHANNEL})"

# ── Create remote staging directory ───────────────────────────────────────────

log "Creating remote staging directory: ${REMOTE_STAGING}"
$SSH "${SSH_USER}@${HOST}" "rm -rf '${REMOTE_STAGING}' && mkdir -p '${REMOTE_STAGING}'"

# ── Copy files to remote ──────────────────────────────────────────────────────

log "Copying files to remote"

# Bootstrap script
info "bootstrap-child.sh"
$SCP "${REPO_DIR}/bootstrap-child.sh" "${SSH_USER}@${HOST}:${REMOTE_STAGING}/bootstrap-child.sh"
$SSH "${SSH_USER}@${HOST}" "chmod +x '${REMOTE_STAGING}/bootstrap-child.sh'"

# Generated openclaw.json
info "config/openclaw.json (with substituted values)"
$SCP "${RESOLVED_JSON_FILE}" "${SSH_USER}@${HOST}:${REMOTE_STAGING}/openclaw.json"

# Cron jobs
info "config/cron/jobs.json"
$SSH "${SSH_USER}@${HOST}" "mkdir -p '${REMOTE_STAGING}/cron'"
$SCP "${REPO_DIR}/config/cron/jobs.json" "${SSH_USER}@${HOST}:${REMOTE_STAGING}/cron/jobs.json"

# Workspace directories (agent soul files)
info "workspaces/ (agent soul + AGENTS.md files)"
$SCP -r "${REPO_DIR}/workspaces" "${SSH_USER}@${HOST}:${REMOTE_STAGING}/workspaces"

# Scripts
info "scripts/"
$SCP -r "${REPO_DIR}/scripts" "${SSH_USER}@${HOST}:${REMOTE_STAGING}/scripts"
$SSH "${SSH_USER}@${HOST}" "chmod +x '${REMOTE_STAGING}/scripts/'*.sh 2>/dev/null || true"

# Tmux config
info "tmux.conf"
$SCP "${REPO_DIR}/tmux.conf" "${SSH_USER}@${HOST}:${REMOTE_STAGING}/tmux.conf"

# ── Export bootstrap environment vars ─────────────────────────────────────────

# Write a sourced env file to the remote (avoids quoting hell in tmux send-keys)
$SSH "${SSH_USER}@${HOST}" "cat > '${REMOTE_STAGING}/bootstrap-env.sh'" <<ENV
#!/usr/bin/env bash
export CLAW_USER="claw"
export LLM_API_KEY='${LLM_API_KEY}'
export LLM_PROVIDER='${LLM_PROVIDER}'
export OPENCLAW_PORT='${OPENCLAW_PORT}'
export PARENT_PUBKEY='${PARENT_PUBKEY}'
export REMOTE_STAGING='${REMOTE_STAGING}'
ENV
$SSH "${SSH_USER}@${HOST}" "chmod 600 '${REMOTE_STAGING}/bootstrap-env.sh'"

# ── Run bootstrap on remote ───────────────────────────────────────────────────

log "Starting bootstrap on remote"

BOOTSTRAP_CMD="source '${REMOTE_STAGING}/bootstrap-env.sh' && bash '${REMOTE_STAGING}/bootstrap-child.sh' 2>&1 | tee '${REMOTE_STAGING}/bootstrap.log'"
LOG_PATH="${REMOTE_STAGING}/bootstrap.log"

if [[ "${REMOTE_HAS_TMUX}" == "true" ]]; then
  # Run inside a detached tmux session so we can attach later
  $SSH "${SSH_USER}@${HOST}" \
    "tmux new-session -d -s claw-bootstrap -x 220 -y 50 2>/dev/null || true; \
     tmux send-keys -t claw-bootstrap \"${BOOTSTRAP_CMD}\" Enter"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Bootstrap is running in tmux session 'claw-bootstrap'"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Attach to watch live:"
  echo "  ssh -t -i ${KEY} -p ${SSH_PORT} ${SSH_USER}@${HOST} tmux attach -t claw-bootstrap"
  echo ""
  echo "  Or tail the log:"
  echo "  ssh -i ${KEY} -p ${SSH_PORT} ${SSH_USER}@${HOST} 'tail -f ${LOG_PATH}'"
  echo ""
  echo "  Once complete, attach to the forge session:"
  echo "  ssh -t -i ${KEY} -p ${SSH_PORT} claw@${HOST} tmux attach -t forge"

else
  # No tmux: run with nohup so it survives SSH disconnection
  warn "Running without tmux (tmux not installed). Using nohup."
  $SSH "${SSH_USER}@${HOST}" \
    "nohup bash -c \"${BOOTSTRAP_CMD}\" > '${LOG_PATH}' 2>&1 &"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Bootstrap is running in the background (nohup)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Tail the log:"
  echo "  ssh -i ${KEY} -p ${SSH_PORT} ${SSH_USER}@${HOST} 'tail -f ${LOG_PATH}'"
  echo ""
  echo "  Once complete, a tmux session 'forge' will be available as the claw user:"
  echo "  ssh -t -i ${KEY} -p ${SSH_PORT} claw@${HOST} tmux attach -t forge"
fi

echo ""
echo "  Gateway token (save this):"
echo "  ${OPENCLAW_GATEWAY_TOKEN}"
echo ""
