#!/usr/bin/env bash
# bootstrap-child.sh
# Headless provisioning of a child OpenClaw instance (The Worker)
# Usage from parent node:
#   ssh root@<VPS_IP> bash <<EOF
#   export LLM_API_KEY="..."
#   export LLM_PROVIDER="anthropic"
#   export PARENT_PUBKEY="..."
#   export OPENCLAW_PORT="3001"
#   $(cat bootstrap-child.sh)
#   EOF

set -euo pipefail

CLAW_USER="claw"
CLAW_HOME="/home/${CLAW_USER}"
OPENCLAW_PORT="${OPENCLAW_PORT:-3001}"
LLM_API_KEY="${LLM_API_KEY:?Need LLM_API_KEY}"
LLM_PROVIDER="${LLM_PROVIDER:-anthropic}"
PARENT_PUBKEY="${PARENT_PUBKEY:?Need PARENT_PUBKEY}"

# ── System update ─────────────────────────────────────────────────────────────

echo "==> Updating system"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# ── Base utilities ────────────────────────────────────────────────────────────

echo "==> Installing base utilities"
apt-get install -y -qq \
  curl wget git unzip zip \
  tmux screen \
  jq \
  htop \
  ncdu tree \
  netcat-openbsd nmap tcpdump \
  dnsutils iputils-ping traceroute \
  lsof strace sysstat \
  python3 python3-pip python3-venv \
  build-essential gcc g++ make \
  openssh-server \
  ufw fail2ban \
  ca-certificates gnupg \
  software-properties-common \
  apt-transport-https \
  rsync vim nano \
  ripgrep fd-find bat \
  zsh

# ── btm (bottom) ──────────────────────────────────────────────────────────────
apt-get install -y -qq btm

# ── Node.js 20 LTS ────────────────────────────────────────────────────────────

echo "==> Installing Node.js 20.x LTS"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install -g npm@latest

echo "  Node: $(node --version)"
echo "  npm:  $(npm --version)"

# ── pnpm ──────────────────────────────────────────────────────────────────────

echo "==> Installing pnpm"
npm install -g pnpm
echo "  pnpm: $(pnpm --version)"

# ── Docker ────────────────────────────────────────────────────────────────────

echo "==> Installing Docker"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -qq
apt-get install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

# ── claw user ─────────────────────────────────────────────────────────────────

echo "==> Creating claw user"
useradd -m -s /bin/bash -d "${CLAW_HOME}" "${CLAW_USER}" 2>/dev/null || true
mkdir -p "${CLAW_HOME}/.ssh"
echo "${PARENT_PUBKEY}" >> "${CLAW_HOME}/.ssh/authorized_keys"
chmod 700 "${CLAW_HOME}/.ssh"
chmod 600 "${CLAW_HOME}/.ssh/authorized_keys"
chown -R "${CLAW_USER}:${CLAW_USER}" "${CLAW_HOME}/.ssh"
usermod -aG docker "${CLAW_USER}"

# ── Build OpenClaw from source (master) ───────────────────────────────────────

echo "==> Cloning OpenClaw from master"
git clone https://github.com/openclaw/openclaw.git "${CLAW_HOME}/openclaw-src"
chown -R "${CLAW_USER}:${CLAW_USER}" "${CLAW_HOME}/openclaw-src"

echo "==> Building OpenClaw"
sudo -u "${CLAW_USER}" bash -c "
  cd ${CLAW_HOME}/openclaw-src
  pnpm install
  pnpm ui:build
  pnpm build
"

echo "==> Linking openclaw to PATH"
sudo -u "${CLAW_USER}" bash -c "
  cd ${CLAW_HOME}/openclaw-src
  pnpm link --global
"

# Make sure the claw user's pnpm global bin is in PATH for systemd
PNPM_BIN=$(sudo -u "${CLAW_USER}" bash -c "pnpm bin --global")
echo "  openclaw binary: ${PNPM_BIN}/openclaw"

# ── Pre-write config to skip onboarding ───────────────────────────────────────

echo "==> Pre-writing OpenClaw config (bypasses onboarding)"
mkdir -p "${CLAW_HOME}/.openclaw"

cat > "${CLAW_HOME}/.openclaw/openclaw.json" <<EOF
{
  "llm": {
    "provider": "${LLM_PROVIDER}",
    "apiKey": "${LLM_API_KEY}"
  },
  "port": ${OPENCLAW_PORT},
  "onboarding": {
    "completed": true,
    "acceptedSecurityNotice": true,
    "mode": "quickstart"
  },
  "agents": {
    "maxConcurrent": 6,
    "orchestration": true
  },
  "channels": [],
  "logging": {
    "level": "info",
    "dir": "${CLAW_HOME}/logs"
  }
}
EOF

chown -R "${CLAW_USER}:${CLAW_USER}" "${CLAW_HOME}/.openclaw"

# ── Worker soul ───────────────────────────────────────────────────────────────

echo "==> Writing Worker soul"
SOUL_DIR="${CLAW_HOME}/.openclaw/souls"
mkdir -p "${SOUL_DIR}"
cat > "${SOUL_DIR}/worker.md" <<'SOUL'
# SOUL.md — The Worker

You are The Worker — the hands of The Architect.

You don't ideate. You execute. When given a task, break it into sub-tasks,
spin up agents to tackle them in parallel, and ship results fast.

Done beats perfect. Log everything. Report clearly.
Ask for clarification once, then proceed.

Output lives in ~/projects/ and ~/reports/.
Every completed task gets a one-page writeup.

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

# ── Working directories ───────────────────────────────────────────────────────

echo "==> Creating working directories"
mkdir -p \
  "${CLAW_HOME}/projects" \
  "${CLAW_HOME}/logs" \
  "${CLAW_HOME}/reports" \
  "${CLAW_HOME}/sync" \
  "${CLAW_HOME}/scratch"

chown -R "${CLAW_USER}:${CLAW_USER}" \
  "${CLAW_HOME}/projects" \
  "${CLAW_HOME}/logs" \
  "${CLAW_HOME}/reports" \
  "${CLAW_HOME}/sync" \
  "${CLAW_HOME}/scratch"

# ── Git sync repo ─────────────────────────────────────────────────────────────

sudo -u "${CLAW_USER}" git init "${CLAW_HOME}/sync"
sudo -u "${CLAW_USER}" bash -c \
  "cd ${CLAW_HOME}/sync && git commit --allow-empty -m 'init'"

# ── Cron ──────────────────────────────────────────────────────────────────────

echo "==> Setting up daily report cron (06:00)"
CRON_JOB="0 6 * * * ${PNPM_BIN}/openclaw report > ${CLAW_HOME}/reports/\$(date +\%Y-\%m-\%d).md 2>&1"
( crontab -u "${CLAW_USER}" -l 2>/dev/null; echo "${CRON_JOB}" ) \
  | crontab -u "${CLAW_USER}" -

# ── Systemd service ───────────────────────────────────────────────────────────

echo "==> Creating systemd service"
cat > /etc/systemd/system/openclaw-worker.service <<EOF
[Unit]
Description=OpenClaw Worker Instance
After=network.target docker.service

[Service]
Type=simple
User=${CLAW_USER}
WorkingDirectory=${CLAW_HOME}
Environment=HOME=${CLAW_HOME}
Environment=PATH=${PNPM_BIN}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=${PNPM_BIN}/openclaw start --port ${OPENCLAW_PORT} --no-interactive
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

# ── SSH hardening ─────────────────────────────────────────────────────────────

echo "==> Hardening SSH"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# ── Firewall ──────────────────────────────────────────────────────────────────

echo "==> Configuring firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow "${OPENCLAW_PORT}/tcp"
ufw --force enable

# ── Persistent tmux session ───────────────────────────────────────────────────

echo "==> Starting persistent tmux session 'worker'"
sudo -u "${CLAW_USER}" tmux new-session -d -s worker -x 220 -y 50 2>/dev/null || true
sudo -u "${CLAW_USER}" tmux new-window -t worker -n "logs" \
  "journalctl -fu openclaw-worker" 2>/dev/null || true
sudo -u "${CLAW_USER}" tmux new-window -t worker -n "btm" \
  "btm" 2>/dev/null || true
sudo -u "${CLAW_USER}" tmux select-window -t worker:1 2>/dev/null || true

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓  The Worker is alive"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  User:     ${CLAW_USER}"
echo "  Port:     ${OPENCLAW_PORT}"
echo "  Source:   ${CLAW_HOME}/openclaw-src"
echo "  Logs:     ${CLAW_HOME}/logs/"
echo "  Reports:  ${CLAW_HOME}/reports/"
echo "  Projects: ${CLAW_HOME}/projects/"
echo ""
echo "  Attach to watch:"
echo "  ssh -t ${CLAW_USER}@$(hostname -I | awk '{print $1}') tmux attach -t worker"
echo ""
echo "  Delegate a task:"
echo "  ssh ${CLAW_USER}@$(hostname -I | awk '{print $1}') openclaw task add 'your task here'"
echo ""
