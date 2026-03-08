# Claw↑↑Claw
*Claw of Claw, Light of Light, true Claw of true Claw, begotten and not made; of the very same nature of the Lobster; by Whom all things came into being, in the cloud and on Macbooks, visible and invisible.*

---

A two-node autonomous AI agent system. The Architect lives on your machine (or a parent VPS) and runs an [OpenClaw](https://github.com/openclaw/openclaw) instance. The Worker lives on a remote VPS, bootstrapped and directed by The Architect. Together they build things while you sleep. The worker can assume the role of architect enabling exponential growth.

---

## What's in this repo

| File | Purpose |
|---|---|
| `SOUL.md` | The Architect's personality and operating instructions — loaded as the system prompt |
| `SKILL.md` | The `vps-provisioner` skill — gives The Architect SSH-based control over The Worker |
| `bootstrap-child.sh` | Provisions a blank Ubuntu VPS as a fully configured OpenClaw child instance |
| `nuke-child.sh` | Completely reverses `bootstrap-child.sh` — wipes The Worker from a VPS |
| `tmux.conf` | Tmux config for the parent node (Catppuccin Mocha theme, vim keys, OpenClaw shortcuts) |

---

## Architecture

```
┌─────────────────────────────────────────┐
│  Your machine / parent VPS              │
│                                         │
│  OpenClaw + SOUL.md (The Architect)     │
│  + vps-provisioner skill                │
│                                         │
│  Thinks, explores, delegates            │
└────────────────┬────────────────────────┘
                 │ SSH
                 ▼
┌─────────────────────────────────────────┐
│  Remote VPS                             │
│                                         │
│  OpenClaw + Worker soul                 │
│  (bootstrapped by bootstrap-child.sh)   │
│                                         │
│  Executes tasks, ships results          │
│  Writes morning reports to ~/reports/   │
└─────────────────────────────────────────┘
```

The Architect picks problems, spins up sub-agents, and delegates long-running work to The Worker over SSH. The Worker executes autonomously, logs everything, and produces a morning report at 06:00.

---

## Setup

### 1. Install OpenClaw on the parent node

Follow the [OpenClaw install guide](https://github.com/openclaw/openclaw). Once it's running:

### 2. Load the soul and skill

Copy `SOUL.md` into OpenClaw as your system prompt (soul). Copy `SKILL.md` into your OpenClaw skills directory. The `vps-provisioner` skill will appear in The Architect's toolbox.

### 3. Provision a child node

You need a blank Ubuntu VPS (22.04 or 24.04) with root SSH access.

```bash
# From your parent node or local machine:
export LLM_API_KEY="your-api-key"
export LLM_PROVIDER="anthropic"          # or openai, etc.
export PARENT_PUBKEY="$(cat ~/.ssh/id_ed25519.pub)"
export OPENCLAW_PORT="18789"

ssh root@<CHILD_VPS_IP> bash -s < bootstrap-child.sh
```

The bootstrap script will:
- Install Node.js 22, pnpm, git, tmux, Python, ripgrep, and other utilities
- Create a non-root `claw` user
- Clone and build OpenClaw from source
- Write the Worker soul and OpenClaw config (skips onboarding)
- Create `~/projects/`, `~/logs/`, `~/reports/`, `~/sync/`, `~/scratch/`
- Register and start an `openclaw.service` systemd unit
- Launch a persistent tmux session named `gateway` with log tailing and `btm` open

### 4. Configure the skill environment

Set these env vars (or add them to your parent node's environment):

```bash
export CHILD_VPS_HOST="your-child-vps-ip"
export CHILD_VPS_USER="claw"
export CHILD_VPS_KEY_PATH="~/.ssh/id_ed25519"
export CHILD_OPENCLAW_PORT="18789"
export CHILD_LLM_API_KEY="your-api-key"
export CHILD_LLM_PROVIDER="anthropic"
```

### 5. Tmux (optional but recommended)

```bash
cp tmux.conf ~/.tmux.conf
tmux source-file ~/.tmux.conf
```

Key bindings added on top of standard tmux (prefix is `C-a`):

| Binding | Action |
|---|---|
| `prefix + M` | New window tailing the OpenClaw worker service log |
| `prefix + G` | New window tailing `~/logs/*.log` |
| `prefix + T` | New window running `btm` (system monitor) |
| `prefix + \|` | Vertical split (stays in current directory) |
| `prefix + -` | Horizontal split (stays in current directory) |
| `prefix + h/j/k/l` | Vim-style pane navigation |

---

## Using the vps-provisioner skill

Once loaded in OpenClaw, The Architect can use these commands:

```
vps-provisioner provision   # Install and configure OpenClaw on the child VPS
vps-provisioner delegate    # Send a task to The Worker
vps-provisioner status      # Check child node health and task queue
vps-provisioner report      # Pull The Worker's latest morning report
vps-provisioner kill        # Gracefully shut down The Worker's OpenClaw service
```

You can also tell The Architect in plain language: *"Delegate the scraper project to the child node"* — it will use the skill automatically.

---

## Watching The Worker

```bash
# Attach to the Worker's tmux session
ssh -t claw@<CHILD_VPS_IP> tmux attach -t gateway

# Follow service logs directly
ssh claw@<CHILD_VPS_IP> journalctl -fu openclaw

# Read the morning report
ssh claw@<CHILD_VPS_IP> cat ~/reports/$(date +%Y-%m-%d).md
```

---

## Tearing it down

```bash
ssh root@<CHILD_VPS_IP> bash -s < nuke-child.sh
```

Stops the service, kills the `claw` user and their home directory, removes the systemd unit, and restores SSH config. Node.js, git, tmux, and Python are left in place — remove manually if you want a truly clean slate.

---

## The Hierarchy

| Notation | Name | Interpretation |
|---|---|---|
| `claw + claw` | addition | two claws side by side |
| `claw × claw` | multiplication | a claw of claws |
| `claw ^ claw` | exponentiation | a claw raised to claw |
| `claw ↑↑ claw` | **tetration** | **a tower of claws, claw high** |
| `claw ↑↑↑ claw` | pentation | do not look directly at this |
| `claw ↑⁹⁹ claw` | the eschaton | the lobster returns |

Everything converges to Lobster. This is [known](https://en.wikipedia.org/wiki/Carcinisation). The question was never *whether*. The question is *how fast*.

---

## License

WTFPL. The claw is not subject to copyright.

## See Also

- [OpenClaw](https://github.com/openclaw/openclaw) — the runtime
- [Knuth's up-arrow notation](https://en.wikipedia.org/wiki/Knuth%27s_up-arrow_notation) — the sacred text
- [Carcinisation](https://en.wikipedia.org/wiki/Carcinisation) — the prophecy
