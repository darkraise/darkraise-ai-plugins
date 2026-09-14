# Gates

What proves a change works in this project, in the order it must run. This file
is read by the running-gates skill. Every gate needs a `Command` field and a
`Green` field; the seven optional ones are `Applies`, `Evidence`, `Repo`,
`Setup`, `Teardown`, `Known-flaky` and `Why`.

## 1. Build
Command: `pwsh -NoProfile -File scripts/build.ps1 -Repo both`
Green: 0 errors in both repos
Evidence: output

## 2. Layout suite
Command: `pwsh -NoProfile -File scripts/test-framework.ps1 layout`
Green: `Passed!`
Known-flaky: the routing timing gate under load

## 3. Script-schema corpus sweep
Setup:
```powershell
$env:DARKRAISE_SCRIPT_CORPUS = "D:/Games Modding/SRHD;D:/Repositories/Personal/SRHD-Mods"
```
Command: `pwsh -NoProfile -File scripts/test-framework.ps1 ScriptSchemaCorpus`
Green: `Passed!`
Teardown: `Remove-Item Env:DARKRAISE_SCRIPT_CORPUS`
Applies: changes touching ScriptSchema, ScriptValueTables, or any payload-mask or choice read
Why: the regression runner never sets the corpus variable, so these suites otherwise
  sweep only the handful of in-repo fixtures and pass green over a real mapping error

## 4. Graph capture
Command: `pwsh -NoProfile -File scripts/capture-graph.ps1 begin.svr -Sheet`
Green: no card on card, no edge through a card, no edge crossing the whole graph
Evidence: image
Applies: changes touching the script canvas, NodeGraph, layout, routing or rendering
Why: metrics have reported zero overlaps over a sheet that was visibly wrong

```markdown
Copy the block below for a new gate. It lives inside this fence so the format
check skips it.

## 1. <title>
Command: `<what to run>`
Green: <what output or observation proves it passed>
Evidence: output
Applies: always
Why: <why this gate exists, so a later session does not delete it>
```
