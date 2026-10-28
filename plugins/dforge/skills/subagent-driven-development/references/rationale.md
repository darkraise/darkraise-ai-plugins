# Why subagents and tiered agents

**Why subagents:** You delegate tasks to specialized agents with isolated context. By precisely crafting their instructions and context, you ensure they stay focused and succeed at their task. They should never inherit your session's context or history — you construct exactly what they need. This also preserves your own context for coordination work.

**Why tiered agents:** the plan records, per task, a model-and-effort pairing
chosen by the rubric in [ladder.md](../../../reference/ladder.md). Each fleet agent
pins both in its frontmatter, so the tier the plan recorded is the tier that
runs without the dispatch naming either. The Agent tool has taken an `effort`
argument since Claude Code 2.1.292, but a fleet dispatch passes neither it nor
`model`: either one overrides the pinned value.

**Core principle:** Assigned subagent per task + scored task review + broad final review = high quality, fast iteration
