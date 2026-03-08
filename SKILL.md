---
name: vps-provisioner
description: Provision a remote VPS as a child OpenClaw instance running the Product Forge Collective — five specialist agents (strategist, researcher, designer, implementer, tester) that continuously scout trends on Reddit and GitHub, develop ideas into products, and report via Slack.
metadata:
  openclaw:
    cliHelp: |
      vps-provisioner --help
      Usage: vps-provisioner [command]

      Commands:
        provision        Run provision.sh to set up the child VPS
        configure-slack  Step-by-step guide to add Slack integration
        forge            Trigger an immediate innovation cycle on the child
        delegate         Send a task to a specific agent on the child
        standup          Pull today's standup report from child
        ideas            Show the current idea pipeline
        sprint           Show what the Implementer is actively building
        status           Health-check the child node
        report           Pull latest report from child
        kill             Stop the child node's OpenClaw service

      Options:
        --host      Remote VPS IP or hostname
        --user      SSH user
        --key       Path to SSH private key
runtime:
  env:
    - CHILD_VPS_HOST
    - CHILD_VPS_USER
    - CHILD_VPS_KEY_PATH
    - CHILD_LLM_API_KEY
    - CHILD_LLM_PROVIDER
    - CHILD_OPENCLAW_PORT
    - CHILD_SLACK_APP_TOKEN
    - CHILD_SLACK_BOT_TOKEN
    - CHILD_SLACK_CHANNEL
  binaries:
    - ssh
    - scp
    - bash
    - jq
---

# VPS Provisioner Skill

Manages the **Product Forge Collective** — a five-agent OpenClaw instance on a
remote VPS that continuously hunts trends, develops product ideas, and ships.

---

## Repo Layout

```
claw-up2-claw/
  provision.sh                 ← run this to provision a target VPS
  bootstrap-child.sh           ← runs on the remote VPS (called by provision.sh)
  nuke-child.sh                ← tears everything down
  tmux.conf                    ← tmux config copied to the claw user
  config/
    openclaw.json              ← template; ${VAR} placeholders substituted by provision.sh
    cron/
      jobs.json                ← cron job definitions (loaded directly by OpenClaw)
  workspaces/
    AGENTS.md                  ← shared cross-agent coordination rules
    product-strategist/
      SOUL.md                  ← Product Strategist persona
      AGENTS.md
    researcher/
      SOUL.md                  ← Researcher persona
      AGENTS.md
    designer/
      SOUL.md                  ← Designer persona
      AGENTS.md
    implementer/
      SOUL.md                  ← Implementer persona
      AGENTS.md
    tester/
      SOUL.md                  ← Tester persona
      AGENTS.md
  scripts/
    trend-hunt.sh              ← fetches Reddit, HN, GitHub trends
```

---

## Commands

### provision

Runs `provision.sh`, which:
1. Generates `openclaw.json` from the template with substituted values
2. SCPs all config, workspace, scripts, and tmux files to the target
3. Runs `bootstrap-child.sh` on the target inside a `tmux` session (or `nohup` if tmux isn't installed yet)

```bash
CHILD_VPS_HOST=1.2.3.4 \
CHILD_VPS_USER=root \
CHILD_VPS_KEY_PATH=~/.ssh/id_ed25519 \
CHILD_LLM_API_KEY=sk-ant-... \
CHILD_SLACK_APP_TOKEN=xapp-... \
CHILD_SLACK_BOT_TOKEN=xoxb-... \
./provision.sh
```

Required: `CHILD_VPS_HOST`, `CHILD_VPS_KEY_PATH`, `CHILD_LLM_API_KEY`

Optional: `CHILD_VPS_USER` (default: root), `CHILD_VPS_PORT` (default: 22),
`CHILD_LLM_PROVIDER` (default: anthropic), `CHILD_OPENCLAW_PORT` (default: 18789),
`CHILD_SLACK_APP_TOKEN`, `CHILD_SLACK_BOT_TOKEN`, `CHILD_SLACK_CHANNEL` (default: general)

**Watch bootstrap progress:**
```bash
ssh -t -i ~/.ssh/id_ed25519 root@1.2.3.4 tmux attach -t claw-bootstrap
```

### configure-slack

Step-by-step Slack app creation guide.

**Step 1: Create the Slack App**

1. Go to https://api.slack.com/apps → **Create New App** → **From scratch**
2. Name: `Product Forge` | Workspace: your workspace
3. **Socket Mode** (left sidebar):
   - Enable Socket Mode
   - App-Level Token: scope `connections:write` → copy `xapp-...` → `CHILD_SLACK_APP_TOKEN`
4. **OAuth & Permissions**:
   - Bot Token Scopes: `chat:write`, `chat:write.public`, `channels:history`, `channels:read`
   - **Install to Workspace** → copy `xoxb-...` → `CHILD_SLACK_BOT_TOKEN`
5. **Event Subscriptions** → Enable → bot events: `message.channels`, `app_mention`
6. In Slack: `/invite @ProductForge` in your target channel

**Step 2: Apply to child node** — re-run `provision.sh` with Slack tokens, or update live:

```bash
ssh -i ${CHILD_VPS_KEY_PATH} claw@${CHILD_VPS_HOST} <<'EOF'
python3 -c "
import json
cfg = json.load(open('/home/claw/.openclaw/openclaw.json'))
cfg['channels']['slack']['enabled'] = True
cfg['channels']['slack']['appToken'] = 'xapp-...'
cfg['channels']['slack']['botToken'] = 'xoxb-...'
json.dump(cfg, open('/home/claw/.openclaw/openclaw.json', 'w'), indent=2)
print('Done.')
"
systemctl restart openclaw
EOF
```

### forge

Trigger an immediate trend hunt + scoring cycle.

```bash
ssh -i ${CHILD_VPS_KEY_PATH} claw@${CHILD_VPS_HOST} \
  "~/scripts/trend-hunt.sh && \
   openclaw task add --agent product-strategist \
   'Read the latest trend report in ~/reports/trends/. Score the top 3 opportunities and write briefs to ~/ideas/briefs/. Post findings to Slack.'"
```

### delegate

Send a task to a specific agent.

```bash
ssh -i ${CHILD_VPS_KEY_PATH} claw@${CHILD_VPS_HOST} \
  "openclaw task add --agent researcher 'Research the competitive landscape for [idea].'"

# Agents: product-strategist, researcher, designer, implementer, tester
```

### standup

Pull today's standup.

```bash
ssh -i ${CHILD_VPS_KEY_PATH} claw@${CHILD_VPS_HOST} \
  "ls -t ~/reports/standups/*.md 2>/dev/null | head -1 | xargs cat"
```

### ideas

Show the idea pipeline.

```bash
ssh -i ${CHILD_VPS_KEY_PATH} claw@${CHILD_VPS_HOST} "cat ~/ideas/backlog.md"
```

### sprint

Show active builds.

```bash
ssh -i ${CHILD_VPS_KEY_PATH} claw@${CHILD_VPS_HOST} \
  "ls -lh ~/projects/ && \
   ls -t ~/reports/builds/*.md 2>/dev/null | head -1 | xargs cat 2>/dev/null"
```

### status

Full health check.

```bash
ssh -i ${CHILD_VPS_KEY_PATH} claw@${CHILD_VPS_HOST} <<'EOF'
echo "=== service ===" && systemctl is-active openclaw
echo "=== latest trend ===" && ls -t ~/reports/trends/*.md 2>/dev/null | head -1
echo "=== projects ===" && ls ~/projects/ 2>/dev/null
echo "=== cron ===" && openclaw cron list 2>/dev/null
echo "=== disk ===" && df -h /home/claw
echo "=== logs ===" && journalctl -u openclaw --lines=15 --no-pager
EOF
```

### report

Pull the latest report.

```bash
ssh -i ${CHILD_VPS_KEY_PATH} claw@${CHILD_VPS_HOST} \
  "ls -t ~/reports/**/*.md 2>/dev/null | head -1 | xargs cat"
```

### kill

Stop OpenClaw on the child.

```bash
ssh -i ${CHILD_VPS_KEY_PATH} ${CHILD_VPS_USER}@${CHILD_VPS_HOST} \
  "systemctl stop openclaw && echo 'stopped.'"
```

---

## How the Child Node Works

### Agents

Defined in `config/openclaw.json` under `agents.list`. Each agent gets its own
workspace directory (`~/.openclaw/workspaces/{id}/`) containing:
- `SOUL.md` — persona and operating principles (loaded by OpenClaw as context)
- `AGENTS.md` — cross-agent coordination protocol

Global tool profile is `full`: terminal (bash exec), web fetch, web search, and
browser automation all enabled.

### Cron Jobs

Defined in `config/cron/jobs.json`, placed at `~/.openclaw/cron/jobs.json` on the
child. OpenClaw loads them directly — no CLI registration step required.

| Job ID | Schedule | Agent | Slack |
|--------|----------|-------|-------|
| product-forge-trend-hunt | `0 */4 * * *` | product-strategist | ✓ |
| product-forge-research-sweep | `30 */4 * * *` | researcher | ✓ |
| product-forge-morning-standup | `0 9 * * *` | product-strategist | ✓ |
| product-forge-evening-checkin | `0 18 * * *` | implementer | ✓ |
| product-forge-build-cycle | `0 */8 * * *` | implementer | ✓ |
| product-forge-test-cycle | `0 4 * * *` | tester | ✓ |
| product-forge-weekly-review | `0 10 * * 1` | product-strategist | ✓ |

All jobs use `"bestEffort": true` on Slack delivery — if Slack isn't configured,
they still run silently.

### Filesystem Handoffs

```
~/reports/trends/        ← trend-hunt.sh writes here
~/ideas/briefs/          ← Strategist writes
~/ideas/competitive/     ← Researcher writes
~/ideas/specs/           ← Designer writes
~/projects/{slug}/       ← Implementer writes
~/reports/builds/        ← Implementer writes build reports
~/reports/tests/         ← Tester writes test verdicts
~/reports/standups/      ← Strategist writes daily/weekly summaries
```

---

## Security

- Child runs as non-root `claw` user
- SSH: root login and password auth disabled post-bootstrap
- UFW: only SSH + OpenClaw port allowed inbound
- Gateway auth token generated at provision time — saved in `provision.sh` output
- Slack tokens live only in `~/.openclaw/openclaw.json` on the child

---
