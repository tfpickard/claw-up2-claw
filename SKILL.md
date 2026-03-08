---
name: vps-provisioner
description: SSH into a remote VPS and provision it as a child OpenClaw instance configured as an autonomous creative/coding agent. Handles full install, configuration, multi-agent setup, and ongoing remote task delegation.
metadata:
  openclaw:
    cliHelp: |
      vps-provisioner --help
      Usage: vps-provisioner [command]

      Commands:
        provision   Install and configure OpenClaw on a remote VPS
        delegate    Send a task to the child node
        status      Check child node health and current activity
        report      Pull latest report from child node
        kill        Gracefully shut down child node instance

      Options:
        --host      Remote VPS IP or hostname
        --user      SSH user (default: root)
        --key       Path to SSH private key
        --port      SSH port (default: 22)
runtime:
  env:
    - CHILD_VPS_HOST
    - CHILD_VPS_USER
    - CHILD_VPS_KEY_PATH
    - CHILD_OPENCLAW_PORT
    - CHILD_LLM_API_KEY
    - CHILD_LLM_PROVIDER
  binaries:
    - ssh
    - scp
    - bash
---

# VPS Provisioner Skill

Gives The Architect the ability to SSH into a blank VPS, bootstrap it as a
fully configured child OpenClaw instance, and communicate with it on an ongoing basis.

## Commands

### provision
Connects to the target VPS and runs the bootstrap script. The child instance is configured with:
- OpenClaw installed and running as a systemd service
- A focused "Worker" soul personality
- Multi-agent orchestration enabled (up to 6 concurrent agents)
- Git repo for syncing work back to parent
- Daily report cron job at 06:00
- Sandboxed under non-root user `claw`

### delegate
Sends a task description to the child node via its API. The child node picks it
up, executes autonomously, and writes results to the shared git repo.

### status
SSHes in and checks:
- Is the OpenClaw service running?
- What's in the current task queue?
- Any errors in recent logs?

### report
Pulls the latest morning report from `~/reports/` on the child node.

### kill
Gracefully stops the child node's OpenClaw service via systemctl.

## Security Notes

- Child node runs as non-root user `claw` with restricted sudo
- No outbound email or social posting without parent approval
- All actions logged to `/home/claw/logs/`
- SSH key auth only — password auth disabled on child node
- UFW configured: only SSH and OpenClaw port open

---
