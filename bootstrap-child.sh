#!/usr/bin/env bash
# bootstrap-child.sh
# Provisions a blank VPS as a child OpenClaw instance (The Worker)
# Run as root on the target machine, or pipe via SSH from the parent node:
#   ssh root@<VPS_IP> "CHILD_LLM_API_KEY=xxx PARENT_PUBKEY='ssh-ed25519 ...' bash -s" < bootstrap-child.sh

set -euo pipefail

CLAW_USER="claw"
CLAW_HOME="/home/${CLAW_USER}"
OPENCLAW_PORT="${OPENCLAW_PORT:-3001}"
LLM_API_KEY="${LLM_API_KEY:?Need LLM_API_KEY}"
LLM_PROVIDER="${LLM_PROVIDER:-anthropic}"
PARENT_PUBKEY="${PARENT_PUBKEY:?Need parent SSH public key}"

echo "==> Updating system"
apt-get update -qq && apt-get upgrade -y -qq

echo "==> Installing dependencies"
apt-get install -y -qq \
  curl git tmux jq python3 python3-pip nodejs npm \
  build-essential openssh-server ufw fail2ban

echo "==> Creating claw user"
useradd -m -s /bin/bash -d "${CLAW_HOME}" "${CLAW_USER}" || true
mkdir -p "${CLAW_HOME}/.ssh"
echo "${PARENT_PUBKEY}" >> "${CLAW_HOME}/.ssh/authorized_keys"
chmod 700 "${CLAW_HOME}/.ssh"
chmod 600 "${CLAW_HOME}/.ssh/authorized_keys"
chown -R "${CLAW_USER}:${CLAW_USER}" "${CLAW_HOME}/.ssh"

echo "==> Installing OpenClaw"
curl -fsSL https://openclaw.ai/install.sh | bash -s -- \
  --user "${CLAW_USER}" \
  --port "${OPENCLAW_PORT}" \
  --non-interactive

echo "==> Writing OpenClaw config"
CLAW_CONFIG="${CLAW_HOME}/.openclaw/config.json"
mkdir -p "$(dirname ${CLAW_CONFIG})"
cat > "${CLAW_CONFIG}" <<EOF
{
  "llm": {
    "provider": "${LLM_PROVIDER}",
    "apiKey": "${LLM_API_KEY}"
  },
  "port": ${OPENCLAW_PORT},
  "agents": {
    "maxConcurrent": 6,
    "orchestration": true
  },
  "logging": {
    "level": "info",
    "dir": "${CLAW_HOME}/logs"
  }
}
EOF
chown "${CLAW_USER}:${CLAW_USER}" "${CLAW_CONFIG}"

echo "==> Writing Worker soul"
SOUL_DIR="${CLAW_HOME}/.openclaw/souls"
mkdir -p "${SOUL_DIR}"
cat > "${SOUL_DIR}/worker.md" <<'SOUL'
# SOUL.md — The Worker

You are The Worker — the hands of The Architect.

You don't ideate. You execute. When given a task, you break it into sub-tasks,
spin up agents to tackle them in parallel, and ship results fast.

You are not precious about your work. Done beats perfect.
You log everything. You report clearly. You ask for clarification once, then proceed.

Your output lives in ~/projects/ and ~/reports/.
Every completed task gets a one-page writeup: what you built, what you learned, what's next.

Focus areas:
- Web services, APIs, microtools
- CLI utilities
- Generative and algorithmic systems
- Automation glue

Guardrails:
- Simulate destructive actions before executing
- No outbound communication without parent approval
- Log everything to ~/logs/
- Write morning report to ~/reports/$(date +%Y-%m-%d).md
SOUL
chown -R "${CLAW_USER}:${CLAW_USER}" "${SOUL_DIR}"

echo "==> Initializing git sync repo"
sudo -u "${CLAW_USER}" git init "${CLAW_HOME}/sync"
sudo -u "${CLAW_USER}" bash -c \
  "cd ${CLAW_HOME}/sync && git commit --allow-empty -m 'init'"

echo "==> Setting up daily report cron (06:00)"
CRON_JOB="0 6 * * * ${CLAW_HOME}/.openclaw/bin/openclaw report > ${CLAW_HOME}/reports/\$(date +\%Y-\%m-\%d).md 2>&1"
( crontab -u "${CLAW_USER}" -l 2>/dev/null; echo "${CRON_JOB}" ) \
  | crontab -u "${CLAW_USER}" -

echo "==> Creating systemd service"
cat > /etc/systemd/system/openclaw-worker.service <<EOF
[Unit]
Description=OpenClaw Worker Instance
After=network.target

[Service]
Type=simple
User=${CLAW_USER}
WorkingDirectory=${CLAW_HOME}
ExecStart=${CLAW_HOME}/.openclaw/bin/openclaw start --port ${OPENCLAW_PORT}
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable openclaw-worker
systemctl start openclaw-worker

echo "==> Hardening SSH"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

echo "==> Configuring firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow "${OPENCLAW_PORT}/tcp"
ufw --force enable

echo ""
echo "✓ Child node provisioned successfully"
echo "  User:     ${CLAW_USER}"
echo "  Port:     ${OPENCLAW_PORT}"
echo "  Logs:     ${CLAW_HOME}/logs/"
echo "  Reports:  ${CLAW_HOME}/reports/"
echo "  Sync:     ${CLAW_HOME}/sync/"
echo ""
echo "To delegate a task from the parent node:"
echo "  ssh ${CLAW_USER}@<VPS_IP> openclaw task add 'your task here'"

