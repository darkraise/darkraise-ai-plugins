# OpenCode executor — item register

**Source:** owner request, 2026-09-20 session: "BAsed on codex plugin for claude code, let create similar plugin for open code, then attach it to the dr-superpowers plugin as executor, focus on free only models of open code"
**Covers:** docs/superpowers/specs/2026-09-20-dr-opencode-executor-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Based on codex plugin for claude code, let create similar plugin for open code | - | - | open | Spec 251880b superseded 2026-09-20: decomposed into SP-A (lane-agnostic executor interface) and SP-B (dr-opencode as second instance); see notes/2026-09-20-dr-opencode-spec-review.md |
| 2 | then attach it to the dr-superpowers plugin as executor | - | - | open | Blocked on SP-A: plan-lint, codex-session.sh, review-route ruling kinds and the driving skills are Codex-specific by name; verified 2026-09-20 |
| 3 | focus on free only models of open code | - | Every model-bearing spawn asserts cost-0 in the companion, with a maximum catalog age | open | Review found the wrapper-only assertion bypassable by the rescue seat and by a spawn without --model |
