# Gates

What proves a change works in this project, in the order it must run. This file
is read by the running-gates skill. Every gate needs a `Command` field and a
`Green` field; the nine optional ones are `Applies`, `Evidence`, `Repo`,
`Setup`, `Teardown`, `Known-flaky`, `Why`, `Tier` and `Budget`.

## 1. Build
Command: `npm run build`
Green: exit 0 with no error lines
Evidence: output
Tier: task

## 2. Test suite
Command: `npm test`
Green: `0 failed`
Known-flaky: the reconnect timing test under load
Budget: 900s

## 3. Full-corpus sweep
Tier: sweep
Setup:
```sh
export SAMPLE_CORPUS="$HOME/data/sample-corpus"
```
Command: `npm run test:corpus`
Green: `0 failed`
Teardown: `unset SAMPLE_CORPUS`
Applies: changes touching the parser or any decoder table
Why: the regular run never sets the corpus variable, so the suite otherwise
  reads only the handful of in-repo fixtures and passes green over a real decoding error

## 4. Screenshot of the changed screen
Command: `npm run screenshot -- dashboard`
Green: no card on card, no clipped text, nothing drawn off the screen
Evidence: image
Applies: changes touching layout, routing or rendering
Why: metrics have reported zero overlaps over a screen that was visibly wrong

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

```markdown
An optional gate for projects that install the official claude-security
plugin. Its documented launch is interactive
(`claude --agent claude-security:claude-security`); the headless `-p` form
below is unverified, so run it once by hand before relying on it.

## 5. Security scan of the branch
Command: `timeout 1800 claude --agent claude-security:claude-security -p "Scan this branch's changes"`
Green: the scan reports no finding at High severity or above
Evidence: judgment
Applies: always
Why: the review lenses read a diff; this scan traces data flow across the codebase
```
