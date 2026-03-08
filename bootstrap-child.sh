#!/usr/bin/env bash
# bootstrap-child.sh
# Provisions a child OpenClaw instance — the Product Forge Collective.
#
# This script runs ON the remote VPS. It expects config files to have been
# staged to $REMOTE_STAGING by provision.sh before this script runs.
#
# Environment variables (set by provision.sh via bootstrap-env.sh):
#   CLAW_USER       Unix user to create (default: claw)
#   LLM_API_KEY     LLM API key
#   LLM_PROVIDER    LLM provider (default: anthropic)
#   OPENCLAW_PORT   Port for OpenClaw gateway (default: 18789)
#   PARENT_PUBKEY   SSH public key to add to claw user's authorized_keys
#   REMOTE_STAGING  Path where provision.sh staged the config files

set -euo pipefail

CLAW_USER="${CLAW_USER:-claw}"
CLAW_HOME="/home/${CLAW_USER}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
LLM_API_KEY="${LLM_API_KEY:?Need LLM_API_KEY}"
LLM_PROVIDER="${LLM_PROVIDER:-anthropic}"
PARENT_PUBKEY="${PARENT_PUBKEY:-}"
REMOTE_STAGING="${REMOTE_STAGING:-/tmp/claw-provision}"

# ── Helpers ───────────────────────────────────────────────────────────────────

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -d "${REMOTE_STAGING}" ]] \
  || die "Staging directory not found: ${REMOTE_STAGING} — run provision.sh first"

# ── System update ─────────────────────────────────────────────────────────────

log "Updating system packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# ── Base utilities ────────────────────────────────────────────────────────────

log "Installing base utilities"
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
  zsh \
  btm

# ── Node.js 22 LTS ────────────────────────────────────────────────────────────

log "Installing Node.js 22.x LTS"
if ! node --version 2>/dev/null | grep -q '^v22'; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi
npm install -g npm@latest
log "  Node: $(node --version) | npm: $(npm --version)"

# ── pnpm ──────────────────────────────────────────────────────────────────────

log "Installing pnpm"
npm install -g pnpm
log "  pnpm: $(pnpm --version)"

# ── claw user ─────────────────────────────────────────────────────────────────

PNPM_HOME="${CLAW_HOME}/.local/share/pnpm"
PNPM_BIN="${PNPM_HOME}"

log "Creating ${CLAW_USER} user"
useradd -m -s /bin/bash -d "${CLAW_HOME}" "${CLAW_USER}" 2>/dev/null || true

mkdir -p "${CLAW_HOME}/.ssh"
if [[ -n "${PARENT_PUBKEY}" ]]; then
  echo "${PARENT_PUBKEY}" >> "${CLAW_HOME}/.ssh/authorized_keys"
fi
chmod 700 "${CLAW_HOME}/.ssh"
chmod 600 "${CLAW_HOME}/.ssh/authorized_keys" 2>/dev/null || true
chown -R "${CLAW_USER}:${CLAW_USER}" "${CLAW_HOME}/.ssh"

# ── Build OpenClaw ────────────────────────────────────────────────────────────

if [[ ! -x "${PNPM_BIN}/openclaw" ]]; then
  log "Cloning and building OpenClaw (master)"
  git clone https://github.com/openclaw/openclaw.git "${CLAW_HOME}/openclaw"
  chown -R "${CLAW_USER}:${CLAW_USER}" "${CLAW_HOME}/openclaw"

  sudo -u "${CLAW_USER}" bash -c "
    cd ${CLAW_HOME}/openclaw
    pnpm install
    pnpm ui:build
    pnpm build
  "

  log "Linking openclaw binary"
  sudo -u "${CLAW_USER}" bash -c "
    export PNPM_HOME=${PNPM_HOME}
    export PATH=${PNPM_HOME}:\$PATH
    mkdir -p \"\${PNPM_HOME}\"
    cd ${CLAW_HOME}/openclaw
    pnpm link --global
  "
else
  log "openclaw already installed — skipping build"
fi

log "  openclaw: ${PNPM_BIN}/openclaw"

# ── Working directories ───────────────────────────────────────────────────────

log "Creating working directories"
mkdir -p \
  "${CLAW_HOME}/projects" \
  "${CLAW_HOME}/logs" \
  "${CLAW_HOME}/scripts" \
  "${CLAW_HOME}/reports/trends" \
  "${CLAW_HOME}/reports/research" \
  "${CLAW_HOME}/reports/builds" \
  "${CLAW_HOME}/reports/tests" \
  "${CLAW_HOME}/reports/standups" \
  "${CLAW_HOME}/ideas/briefs" \
  "${CLAW_HOME}/ideas/specs" \
  "${CLAW_HOME}/ideas/competitive" \
  "${CLAW_HOME}/ideas/pending-specs" \
  "${CLAW_HOME}/ideas/archive" \
  "${CLAW_HOME}/scratch"

chown -R "${CLAW_USER}:${CLAW_USER}" \
  "${CLAW_HOME}/projects" \
  "${CLAW_HOME}/logs" \
  "${CLAW_HOME}/scripts" \
  "${CLAW_HOME}/reports" \
  "${CLAW_HOME}/ideas" \
  "${CLAW_HOME}/scratch"

# ── Seed idea backlog ─────────────────────────────────────────────────────────

if [[ ! -f "${CLAW_HOME}/ideas/backlog.md" ]]; then
  log "Seeding idea backlog"
  cat > "${CLAW_HOME}/ideas/backlog.md" <<'BACKLOG'
# Product Idea Backlog

Status: `[backlog]` `[researching]` `[brief]` `[speccing]` `[building]` `[testing]` `[shipped]` `[abandoned]`

| Status | Idea | Composite Score | Added |
|--------|------|----------------|-------|
| — | _(trend hunt will populate this)_ | — | — |

---

## Scoring

`composite = (pain × market) / build_effort` — pursue ≥ 3.5
- pain 1–5: how desperate is the user?
- market 1–5: how many people share this problem?
- build_effort 1–5: how hard to build? (lower = easier)
BACKLOG
  chown "${CLAW_USER}:${CLAW_USER}" "${CLAW_HOME}/ideas/backlog.md"
fi

# ── Install openclaw.json ─────────────────────────────────────────────────────

log "Installing openclaw.json"
mkdir -p "${CLAW_HOME}/.openclaw"

[[ -f "${REMOTE_STAGING}/openclaw.json" ]] \
  || die "openclaw.json not found in staging — did provision.sh run successfully?"

cp "${REMOTE_STAGING}/openclaw.json" "${CLAW_HOME}/.openclaw/openclaw.json"
chown -R "${CLAW_USER}:${CLAW_USER}" "${CLAW_HOME}/.openclaw"

# ── Install cron jobs ─────────────────────────────────────────────────────────

log "Installing cron jobs"
mkdir -p "${CLAW_HOME}/.openclaw/cron"

[[ -f "${REMOTE_STAGING}/cron/jobs.json" ]] \
  || die "cron/jobs.json not found in staging"

cp "${REMOTE_STAGING}/cron/jobs.json" "${CLAW_HOME}/.openclaw/cron/jobs.json"
chown -R "${CLAW_USER}:${CLAW_USER}" "${CLAW_HOME}/.openclaw/cron"

# ── Install agent workspaces ──────────────────────────────────────────────────

log "Installing agent workspaces"
WORKSPACE_ROOT="${CLAW_HOME}/.openclaw/workspaces"

[[ -d "${REMOTE_STAGING}/workspaces" ]] \
  || die "workspaces/ not found in staging"

mkdir -p "${WORKSPACE_ROOT}"
cp -r "${REMOTE_STAGING}/workspaces/"* "${WORKSPACE_ROOT}/"
chown -R "${CLAW_USER}:${CLAW_USER}" "${WORKSPACE_ROOT}"

for ws in "${WORKSPACE_ROOT}"/*/; do
  [[ -d "${ws}" ]] || continue
  name=$(basename "${ws}")
  files=$(ls "${ws}" | tr '\n' ' ')
  echo "    ${name}: ${files}"
done

# ── Install scripts ───────────────────────────────────────────────────────────

log "Installing scripts"

[[ -d "${REMOTE_STAGING}/scripts" ]] \
  || die "scripts/ not found in staging"

cp -r "${REMOTE_STAGING}/scripts/"* "${CLAW_HOME}/scripts/"
chmod +x "${CLAW_HOME}/scripts/"*.sh 2>/dev/null || true
chown -R "${CLAW_USER}:${CLAW_USER}" "${CLAW_HOME}/scripts"

echo "    $(ls "${CLAW_HOME}/scripts/" | tr '\n' ' ')"

# ── Install tmux config ───────────────────────────────────────────────────────

if [[ -f "${REMOTE_STAGING}/tmux.conf" ]]; then
  cp "${REMOTE_STAGING}/tmux.conf" "${CLAW_HOME}/.tmux.conf"
  chown "${CLAW_USER}:${CLAW_USER}" "${CLAW_HOME}/.tmux.conf"
fi

# ── Systemd: OpenClaw service ─────────────────────────────────────────────────

log "Creating openclaw systemd service"
cat > /etc/systemd/system/openclaw.service <<EOF
[Unit]
Description=OpenClaw Gateway — Product Forge Collective
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=${CLAW_USER}
WorkingDirectory=${CLAW_HOME}
Environment=HOME=${CLAW_HOME}
Environment=PATH=${PNPM_BIN}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=PNPM_HOME=${PNPM_HOME}
ExecStart=${PNPM_BIN}/openclaw start --port ${OPENCLAW_PORT} --no-interactive
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable openclaw
systemctl start openclaw

# ── SSH hardening ─────────────────────────────────────────────────────────────

log "Hardening SSH"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# ── Firewall ──────────────────────────────────────────────────────────────────

log "Configuring UFW firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow "${OPENCLAW_PORT}/tcp"
ufw --force enable

# ── Run doctor ────────────────────────────────────────────────────────────────

log "Running openclaw doctor"
sudo -u "${CLAW_USER}" bash -c "
  export PNPM_HOME=${PNPM_HOME}
  export PATH=${PNPM_HOME}:\$PATH
  export HOME=${CLAW_HOME}
  ${PNPM_BIN}/openclaw doctor --fix || true
" 2>&1 | tail -20

# ── Persistent tmux session ───────────────────────────────────────────────────

log "Starting tmux session 'forge'"
sudo -u "${CLAW_USER}" tmux new-session   -d -s forge -x 220 -y 50 2>/dev/null || true
sudo -u "${CLAW_USER}" tmux new-window    -t forge -n "openclaw" \
  "journalctl -fu openclaw.service" 2>/dev/null || true
sudo -u "${CLAW_USER}" tmux new-window    -t forge -n "trends" \
  "watch -n 60 'ls -lt ${CLAW_HOME}/reports/trends/ 2>/dev/null | head -8'" 2>/dev/null || true
sudo -u "${CLAW_USER}" tmux new-window    -t forge -n "ideas" \
  "watch -n 30 'cat ${CLAW_HOME}/ideas/backlog.md 2>/dev/null'" 2>/dev/null || true
sudo -u "${CLAW_USER}" tmux new-window    -t forge -n "btm" \
  "btm" 2>/dev/null || true
sudo -u "${CLAW_USER}" tmux select-window -t forge:1 2>/dev/null || true

# ── Done ──────────────────────────────────────────────────────────────────────

VPS_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓  Product Forge Collective is live"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  User:  ${CLAW_USER} @ ${VPS_IP}"
echo "  Port:  ${OPENCLAW_PORT}"
echo ""
echo "  Agents:"
echo "    🎯  product-strategist  (default)"
echo "    🔬  researcher"
echo "    🎨  designer"
echo "    ⚡  implementer"
echo "    🧪  tester"
echo ""
echo "  Cron schedule:"
echo "    00 */4 * * *  trend-hunt       → product-strategist"
echo "    30 */4 * * *  research-sweep   → researcher"
echo "    00 9   * * *  morning-standup  → Slack"
echo "    00 18  * * *  evening-checkin  → Slack"
echo "    00 */8 * * *  build-cycle      → implementer"
echo "    00 4   * * *  test-cycle       → tester"
echo "    00 10  * * 1  weekly-review    → Slack"
echo ""
echo "  Attach:"
echo "  ssh -t ${CLAW_USER}@${VPS_IP} tmux attach -t forge"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
