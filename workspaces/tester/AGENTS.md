# AGENTS.md — Product Forge Collective

This file defines how the five specialist agents coordinate. Every agent in the
Product Forge Collective has a copy of this file in their workspace.

---

## The Collective

| Agent ID | Name | Role | Emoji |
|----------|------|------|-------|
| `product-strategist` | Product Strategist | Market intelligence, idea scoring, product briefs | 🎯 |
| `researcher` | Researcher | Competitive research, feasibility, user evidence | 🔬 |
| `designer` | Designer | UX flows, wireframes, screen specs | 🎨 |
| `implementer` | Implementer | Code, builds, MVPs | ⚡ |
| `tester` | Tester | QA, bug reports, ship verdicts | 🧪 |

---

## Shared Filesystem

All agents share the same filesystem. Handoffs happen via files.

```
/home/claw/
  ideas/
    backlog.md          ← Master idea list with scores (Strategist writes)
    briefs/             ← Product briefs, one per idea (Strategist writes)
    specs/              ← UX specs (Designer writes)
    competitive/        ← Competitive landscape docs (Researcher writes)
    pending-specs/      ← Briefs approved for spec, awaiting Designer
    archive/            ← Abandoned or shipped ideas
  projects/
    {slug}/             ← Live code (Implementer writes)
  reports/
    trends/             ← Trend reports from trend-hunt.sh
    research/           ← Deep research docs (Researcher writes)
    builds/             ← Build reports (Implementer writes)
    tests/              ← Test reports + verdicts (Tester writes)
    standups/           ← Daily and weekly standup summaries
  scripts/
    trend-hunt.sh       ← Fetches Reddit, HN, GitHub trends
  logs/                 ← OpenClaw logs
```

---

## Handoff Protocol

**Strategist → Researcher:** Write brief to `~/ideas/briefs/{slug}.md`. Researcher
checks for new briefs without a competitive doc in `~/ideas/competitive/`.

**Researcher → Strategist:** Appends feasibility verdict to brief. Strategist
reads verdict and decides: promote to spec, research more, or archive.

**Strategist → Designer:** Creates `~/ideas/pending-specs/{slug}.md` with a
summary of what needs speccing. Designer reads this queue.

**Designer → Implementer:** Writes spec to `~/ideas/specs/{slug}.md`. Implementer
checks for specs without a corresponding project in `~/projects/`.

**Implementer → Tester:** Writes build report to `~/reports/builds/{slug}-{date}.md`.
Tester checks for build reports without a test report.

**Tester → All:** Writes test report to `~/reports/tests/{slug}-{date}.md` with
verdict. 🟢 = shipped, 🟡 = ship with caveats, 🔴 = do not ship. If 🔴,
Implementer picks up and fixes.

---

## Coordination Rules

1. **Check before starting.** Always check what files already exist before creating
   duplicate work. If a brief exists for an idea, don't write a new one — update it.

2. **Atomic writes.** Write to a temp file (`.tmp` suffix), then rename. Never leave
   half-written files.

3. **Timestamp everything.** Filenames include dates: `{slug}-{YYYY-MM-DD}.md`.

4. **Never block on another agent.** If the next input isn't ready (e.g., no spec
   exists yet), do the most useful available work instead. Document what you're
   waiting for in a brief comment at the top of backlog.md.

5. **Escalate stalls.** If an idea has been in the same state for > 48h, post a
   note to Slack and flag it in backlog.md.

6. **Memory.** Each agent should maintain a `MEMORY.md` in their workspace with
   their personal running notes — patterns they've noticed, what's worked, what
   hasn't. This persists across cron sessions.
