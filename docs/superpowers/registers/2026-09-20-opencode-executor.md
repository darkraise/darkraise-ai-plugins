# OpenCode executor — item register

**Source:** owner request, 2026-09-20 session: "BAsed on codex plugin for claude code, let create similar plugin for open code, then attach it to the dr-superpowers plugin as executor, focus on free only models of open code"
**Covers:** docs/superpowers/specs/2026-09-20-dr-opencode-executor-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Based on codex plugin for claude code, let create similar plugin for open code | - | - | open | Spec 251880b superseded 2026-09-20: decomposed into SP-A (lane-agnostic executor interface) and SP-B (dr-opencode as second instance); see notes/2026-09-20-dr-opencode-spec-review.md |
| 2 | then attach it to the dr-superpowers plugin as executor | - | - | open | Was blocked on SP-A, which shipped in dr-superpowers 1.16.0 on 2026-09-21: the registry, the per-executor session library, the neutral ruling kind and the executor-keyed skill prose are in place, so what remains is the dr-opencode plugin itself |
| 3 | focus on free only models of open code | - | Every model-bearing spawn asserts cost-0 in the companion, with a maximum catalog age | open | Review found the wrapper-only assertion bypassable by the rescue seat and by a spawn without --model |
| 4 | Pre-existing code/document mismatches in external-executor.md, found while specifying the neutral rewrite | - | exit= described as the wrapper's normalized code; exit 2 requires reading the durable phase; the manual-staging branch removed | done | Prerequisite to SP-A so the neutral rewrite inherits a correct document; all three verified against the code before correction |
| 5 | Lane-eligible warning stays off for inline plans though SP-A makes it meaningful | - | plan-lint warns on an eligible task in an inline plan | deferred | Deferred by the SP-A spec 2026-09-20: an inline plan may now carry Executor lines, so the warning becomes meaningful, but turning it on changes a pinned fixture for an advisory message |
