#!/usr/bin/env bash
# nuke-child.sh — completely reverses bootstrap-child.sh
# ssh root@<VPS_IP> bash -s < nuke-child.sh

set -euo pipefail

CLAW_USER="claw"
CLAW_HOME="/home/${CLAW_USER}"
OPENCLAW_PORT="${OPENCLAW_PORT:-3001}"

echo "==> Stopping OpenClaw service"
systemctl stop openclaw-worker 2>/dev/null || true
systemctl disable openclaw-worker 2>/dev/null || true
rm -f /etc/systemd/system/openclaw-worker.service
systemctl daemon-reload

echo "==> Killing stray processes"
pkill -u "${CLAW_USER}" 2>/dev/null || true
pkill -f "openclaw" 2>/dev/null || true

echo "==> Killing tmux sessions"
sudo -u "${CLAW_USER}" tmux kill-server 2>/dev/null || true

echo "==> Uninstalling OpenClaw"
npm uninstall -g openclaw 2>/dev/null || true

echo "==> Removing claw user and home"
crontab -r -u "${CLAW_USER}" 2>/dev/null || true
userdel -r "${CLAW_USER}" 2>/dev/null || true
rm -rf "${CLAW_HOME}" 2>/dev/null || true

echo "==> Removing Docker (optional — comment out to keep)"
systemctl stop docker 2>/dev/null || true
apt-get remove -y --purge \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
rm -rf /var/lib/docker /etc/docker
rm -f /etc/apt/sources.list.d/docker.list
rm -f /etc/apt/keyrings/docker.gpg

echo "==> Removing firewall rule for OpenClaw port"
ufw delete allow "${OPENCLAW_PORT}/tcp" 2>/dev/null || true

echo "==> Restoring SSH config"
sed -i 's/^PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

echo "==> Cleaning up"
rm -f /tmp/bootstrap-child.sh /tmp/provision.log /tmp/bottom.deb
apt-get autoremove -y 2>/dev/null || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓  Child node fully nuked. VPS is clean."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Note: nodejs, npm, git, tmux, python3, btm"
echo "  left in place. Remove manually if needed."
echo ""
