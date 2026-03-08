---
name: vps-provisioner
description: SSH into a remote VPS and provision it as a child OpenClaw instance running the Product Forge Collective — five specialist agents (strategist, researcher, designer, implementer, tester) that continuously scout trends on Reddit and GitHub, develop ideas into products, and report via Slack.
metadata:
  openclaw:
    cliHelp: |
      vps-provisioner --help
      Usage: vps-provisioner [command]

      Commands:
        provision        Install and configure OpenClaw on a remote VPS with the Product Forge Collective
        configure-slack  Set up Slack integration on the child node
        forge            Trigger an immediate innovation cycle (trend hunt → ideas → Slack)
        delegate         Send a task to the child node
        standup          Pull today's standup from the child node's Slack reports
        ideas            List product ideas currently in the pipeline
        sprint           Show what the Implementer is currently building
        status           Check child node health and current activity
        report           Pull latest report from child node
        kill             Gracefully shut down child node instance

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
    - CHILD_SLACK_APP_TOKEN
    - CHILD_SLACK_BOT_TOKEN
    - CHILD_SLACK_CHANNEL
  binaries:
    - ssh
    - scp
    - bash
---

# VPS Provisioner Skill

Gives The Architect the ability to SSH into a blank VPS, bootstrap it as a
fully configured child OpenClaw instance running the **Product Forge Collective**
— five autonomous agents that continuously find, develop, and ship products.

---

## Commands

### provision

Connects to the target VPS and runs `bootstrap-child.sh`. The child instance is configured with:

- OpenClaw installed and running as a systemd service
- Five specialist souls: Product Strategist, Researcher, Designer, Implementer, Tester
- Multi-agent orchestration enabled (up to 6 concurrent agents)
- Slack integration (if tokens provided — see `configure-slack`)
- Automated trend hunting via `scripts/trend-hunt.sh`
- Cron jobs: trend hunt (every 4h), morning standup (9am UTC), evening check-in (6pm UTC), weekly review (Mon 10am UTC)
- Sandboxed under non-root user `claw`

**To provision:**

```bash
ssh root@<VPS_IP> bash <<EOF
export LLM_API_KEY="${CHILD_LLM_API_KEY}"
export LLM_PROVIDER="${CHILD_LLM_PROVIDER:-anthropic}"
export PARENT_PUBKEY="$(cat ~/.ssh/id_ed25519.pub)"
export OPENCLAW_PORT="${CHILD_OPENCLAW_PORT:-18789}"
export SLACK_APP_TOKEN="${CHILD_SLACK_APP_TOKEN:-}"
export SLACK_BOT_TOKEN="${CHILD_SLACK_BOT_TOKEN:-}"
export SLACK_CHANNEL="${CHILD_SLACK_CHANNEL:-general}"
$(cat bootstrap-child.sh)
EOF
```

### configure-slack

Sets up Slack integration on an already-provisioned child node.

**Step 1: Create a Slack App**

1. Go to https://api.slack.com/apps → "Create New App" → "From scratch"
2. Name it something like "Product Forge" and select your workspace
3. Under **OAuth & Permissions**:
   - Add Bot Token Scopes: `chat:write`, `chat:write.public`, `channels:history`, `channels:read`
   - Click "Install to Workspace" → copy the **Bot User OAuth Token** (`xoxb-...`)
4. Under **Socket Mode**:
   - Enable Socket Mode
   - Generate an App-Level Token with scope `connections:write` → copy the **App Token** (`xapp-...`)
5. Under **Event Subscriptions** → Enable Events → Subscribe to:
   - `message.channels`, `app_mention`
6. Invite the bot to your desired channel: `/invite @ProductForge`

**Step 2: Apply to child node**

```bash
ssh ${CHILD_VPS_USER}@${CHILD_VPS_HOST} -i ${CHILD_VPS_KEY_PATH} <<EOF
export SLACK_APP_TOKEN="xapp-..."
export SLACK_BOT_TOKEN="xoxb-..."
export SLACK_CHANNEL="general"

# Update openclaw.json with Slack config
python3 -c "
import json, os
cfg = json.load(open('/home/claw/.openclaw/openclaw.json'))
cfg['channels'] = {
  'slack': {
    'appToken': os.environ['SLACK_APP_TOKEN'],
    'botToken': os.environ['SLACK_BOT_TOKEN'],
    'channel': {'policy': 'open'}
  }
}
json.dump(cfg, open('/home/claw/.openclaw/openclaw.json', 'w'), indent=2)
print('Slack configured.')
"

# Restart OpenClaw to pick up new config
systemctl restart openclaw
systemctl --wait is-active openclaw && echo "OpenClaw restarted OK"

# Register cron job announcement channel
sudo -u claw /home/claw/.local/share/pnpm/openclaw cron list
EOF
```

**Step 3: Verify**

Send a test message via the child:
```bash
ssh claw@${CHILD_VPS_HOST} -i ${CHILD_VPS_KEY_PATH} \
  "openclaw chat --channel slack 'Product Forge is online. Innovation flywheel starting.'"
```

### forge

Triggers an immediate innovation cycle on the child node: runs the trend
hunter, feeds output to the Product Strategist, and posts top opportunities to Slack.

```bash
ssh claw@${CHILD_VPS_HOST} -i ${CHILD_VPS_KEY_PATH} \
  "/home/claw/scripts/trend-hunt.sh && \
   openclaw task add 'Read the latest trend report in ~/reports/trends/. Score the top 3 opportunities using the product brief template. Post findings to Slack.'"
```

### delegate

Sends a task description to the child node. The child picks it up, executes
autonomously, and writes results to the relevant output directories.

```bash
ssh claw@${CHILD_VPS_HOST} -i ${CHILD_VPS_KEY_PATH} \
  "openclaw task add '${TASK_DESCRIPTION}'"
```

Example tasks:
- `"Research the competitive landscape for AI-powered code review tools. Write a competitive landscape doc to ~/reports/research/."`
- `"Build an MVP CLI tool that [description]. Spec is in ~/ideas/specs/[name].md."`
- `"Run a full test pass on the project in ~/projects/[name]/. Write a test report."`

### standup

Pulls today's standup from the child node's reports directory.

```bash
ssh claw@${CHILD_VPS_HOST} -i ${CHILD_VPS_KEY_PATH} \
  "cat ~/reports/standups/$(date +%Y-%m-%d).md 2>/dev/null \
   || ls -t ~/reports/standups/ | head -1 | xargs -I{} cat ~/reports/standups/{}"
```

### ideas

Lists the current product idea pipeline on the child node.

```bash
ssh claw@${CHILD_VPS_HOST} -i ${CHILD_VPS_KEY_PATH} "cat ~/ideas/backlog.md"
```

To see active briefs:
```bash
ssh claw@${CHILD_VPS_HOST} -i ${CHILD_VPS_KEY_PATH} "ls -lh ~/ideas/briefs/ && ls -lh ~/ideas/specs/"
```

### sprint

Shows what the Implementer is currently building.

```bash
ssh claw@${CHILD_VPS_HOST} -i ${CHILD_VPS_KEY_PATH} \
  "ls -lh ~/projects/ && find ~/reports/builds/ -name '*.md' -newer ~/reports/builds/$(ls -t ~/reports/builds/ | tail -1) 2>/dev/null | head -5"
```

### status

SSHes in and checks:
- Is the OpenClaw service running?
- What's in the current task queue?
- Latest trend report timestamp?
- Any errors in recent logs?

```bash
ssh claw@${CHILD_VPS_HOST} -i ${CHILD_VPS_KEY_PATH} <<'EOF'
echo "=== OpenClaw service ===" && systemctl is-active openclaw
echo "=== Latest trend report ===" && ls -t ~/reports/trends/*.md 2>/dev/null | head -1
echo "=== Recent log tail ===" && tail -20 ~/logs/*.log 2>/dev/null | tail -20
echo "=== Active projects ===" && ls ~/projects/ 2>/dev/null
echo "=== Cron jobs ===" && openclaw cron list 2>/dev/null
EOF
```

### report

Pulls the latest morning report from `~/reports/` on the child node.

```bash
ssh claw@${CHILD_VPS_HOST} -i ${CHILD_VPS_KEY_PATH} \
  "ls -t ~/reports/*.md 2>/dev/null | head -1 | xargs cat"
```

### kill

Gracefully stops the child node's OpenClaw service via systemctl.

```bash
ssh ${CHILD_VPS_USER}@${CHILD_VPS_HOST} -i ${CHILD_VPS_KEY_PATH} \
  "systemctl stop openclaw && echo 'OpenClaw stopped.'"
```

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `CHILD_VPS_HOST` | Yes | IP or hostname of child VPS |
| `CHILD_VPS_USER` | Yes | SSH user (usually `root` for provisioning, `claw` after) |
| `CHILD_VPS_KEY_PATH` | Yes | Path to SSH private key |
| `CHILD_OPENCLAW_PORT` | Yes | Port OpenClaw listens on (default: 18789) |
| `CHILD_LLM_API_KEY` | Yes | API key for the LLM provider |
| `CHILD_LLM_PROVIDER` | No | LLM provider (default: `anthropic`) |
| `CHILD_SLACK_APP_TOKEN` | No | Slack App-Level Token (`xapp-...`), enables Slack check-ins |
| `CHILD_SLACK_BOT_TOKEN` | No | Slack Bot Token (`xoxb-...`), enables Slack check-ins |
| `CHILD_SLACK_CHANNEL` | No | Slack channel name without `#` (default: `general`) |

---

## Security Notes

- Child node runs as non-root user `claw` with restricted sudo
- No outbound communication without scheduled cron announcements or explicit delegation
- All actions logged to `/home/claw/logs/`
- SSH key auth only — password auth disabled on child node
- UFW configured: only SSH and OpenClaw port open
- Slack tokens stored only in `~/.openclaw/openclaw.json` on the child node (not in this repo)

---

## Directory Layout on Child Node

```
/home/claw/
  .openclaw/
    openclaw.json     ← main config (LLM, Slack, agents)
    souls/            ← specialist soul definitions
      product-strategist.md
      researcher.md
      designer.md
      implementer.md
      tester.md
  scripts/
    trend-hunt.sh     ← fetches Reddit + GitHub + HN trends
    setup-cron.sh     ← registers cron jobs (runs once at setup)
  ideas/
    backlog.md        ← all ideas, scored
    briefs/           ← product briefs (one per idea)
    specs/            ← UX specs from Designer
    competitive/      ← competitive research docs
    archive/          ← shipped or abandoned ideas
  projects/           ← active builds
  reports/
    trends/           ← trend reports from trend-hunt.sh
    research/         ← deep research from Researcher
    builds/           ← build reports from Implementer
    tests/            ← test reports from Tester
    standups/         ← daily standup summaries
  logs/               ← openclaw logs
```

---
