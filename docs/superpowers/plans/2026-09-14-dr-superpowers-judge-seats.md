# dr-superpowers Codex Judge Seats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move both Claude-hosted Codex review seats to `gpt-6-astra / high` with a declared fallback, and make selection, the run bound and the outcome policy executable in one script instead of prose.

**Architecture:** One new policy block in `reference/ladder.md`, one new field in `scripts/detect-executors.sh`, one new script `scripts/run-codex-review.sh` that both seats call, and additive edits to the two seat sections plus the prose the block falsifies. No change to execution admission, to `scripts/run-codex-task.sh`, or to the native Codex policy.

**Tech Stack:** Bash, `jq`, coreutils `timeout`, Markdown, git.

**Spec:** `docs/superpowers/specs/2026-09-14-dr-superpowers-judge-seats-design.md`

**Execution:** inline — `claude --model opus --effort low` — every task totals 4 or less and none is at risk 3; Tasks 2 and 4 are the 4s, so the model follows them into the Opus-low band.

**Program:** `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` — sub-project 7 of 7 — last

**Plan review:** 2026-09-14 — dr-superpowers:judge-fable — executability 17 / coherence 18 / coverage 16 / assumptions 16 (round 3)

## Global Constraints

- Plugin version is `1.8.0` on both `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json`. The two must stay equal.
- Every change is additive. No existing plan format, ledger format, script interface or manifest format changes. `reference/codex-routing.json`, `reference/native-codex.md`, `scripts/run-codex-task.sh`, and `reference/ladder.md`'s `gate`, `codex-assignment` and `codex-successor` blocks are **not** modified by any task.
- English only, in every file: code, comments, docs, commits, tests.
- Commits follow `<type>(<scope>): <subject>`, subject 50 characters or fewer, imperative, no trailing period. The scope for this sub-project is `superpowers`.
- New and modified test suites are executable at mode `100755` in the index. `git config core.filemode` is `false` on this machine, so `chmod +x` does **not** reach the index — use `git update-index --chmod=+x <path>` before committing.
- `jq` and coreutils `timeout` are the only external dependencies. `scripts/detect-executors.sh` already requires both.
- No task makes a paid model capability call. Every new test runs against stubs.
- Never commit `.superpowers/`.

## Contracts

Paths are repository-relative. Paths inside skill and reference bodies are relative to the file, per the existing house convention.

**Files this plan creates**

| Path | Produced by |
|---|---|
| `plugins/dr-superpowers/scripts/run-codex-review.sh` | Task 3, extended by Task 4 |
| `plugins/dr-superpowers/tests/codex-review.test.sh` | Task 3, extended by Task 4 |

**The `codex-judge` block** in `plugins/dr-superpowers/reference/ladder.md`, produced by Task 1 and read by Task 3's script. Three whitespace-separated fields per row — model, effort, timeout in seconds. First row preferred, last row the fallback:

````markdown
```codex-judge
gpt-6-astra high 1800
gpt-5.6-sol high 1800
```
````

**The `advertised` field**, produced by Task 2 on the codex row of `scripts/detect-executors.sh` output and consumed by Task 3. Exactly one of:

- `null` — the cache is absent, unreadable, or not valid JSON;
- an object `{"fetched_at": <string|null>, "client_version": <string|null>, "pairs": [{"model": <string>, "effort": <string>}, …]}`. `pairs` may be `[]`.

Every non-codex row carries `advertised: null`.

**`scripts/run-codex-review.sh` interface**, produced by Task 3 and consumed by Tasks 5 and 6:

```
scripts/run-codex-review.sh --kind risk3|final --cwd <dir> --out <path>
                            (--prompt <file> | --base <ref>) [--dry-run]
```

`--kind risk3` requires `--prompt`; `--kind final` requires `--base`. Exit 2 is a usage or environment error before any Codex call. Otherwise the script prints exactly one status line to stdout:

```
codex-judge <model>/<effort> status=OK|FALLBACK|TIMEOUT|FAILED exit=<n> out=<path> evidence=<fetched_at>
```

`evidence` is the cache's `fetched_at`, or `unknown` when `advertised` is `null`. Exit code is 0 for `OK` and `FALLBACK`, 1 for `TIMEOUT` and `FAILED`.

**`--dry-run`** prints the argv it would run, one token per line, preceded by a `would-run:` line and followed by the status line with `status=OK exit=0`. It makes no Codex call. This is the seam every selection test uses.

**Outcome names** — exactly four, upper case: `OK`, `FALLBACK`, `TIMEOUT`, `FAILED`.

**Valid output**, per kind: `risk3` — the output file parses as JSON and carries the keys `spec_verdict`, `task_quality` and `cannot_verify`; `final` — the output file exists and is non-empty.

**Judge models** (used verbatim in the block, the tests and the prose): `gpt-6-astra`, `gpt-5.6-sol`.

**Test-suite helpers.** `tests/codex-review.test.sh` defines `check` and `present`. It never calls `absent`, so it does not define it.

## Assumptions (evidence)

- `~/.codex/models_cache.json` exists and carries `models[].slug`, `models[].visibility` and `models[].supported_reasoning_levels[].effort`, plus top-level `fetched_at` and `client_version` — `jq`, 2026-09-14; 244,853 bytes, `fetched_at` 2026-09-14, `client_version` 0.153.4. `gpt-6-astra` is `visibility: "list"` with efforts low/medium/high/xhigh/max/ultra.
- `gpt-6-astra / high` is callable from the Claude-hosted lane on this account: `codex exec -s read-only -m gpt-6-astra -c model_reasoning_effort=high` completed twice with exit 0 on 2026-09-14, producing the two design reviews this spec was written from.
- `scripts/detect-executors.sh` emits four executors through one `emit` function and requires `jq` and `timeout` — read 2026-09-14, `scripts/detect-executors.sh:19-27,29,90-95`.
- `scripts/detect-executors.sh` does not currently read `CODEX_HOME`; `tests/detect.test.sh:38` sets it for the stubbed `codex` only — read 2026-09-14.
- `scripts/run-codex-task.sh:93-94` validates `--model` against the `codex-assignment` block, and `tests/lanes.test.sh:35` returns `-1` for any model outside `VALID_MODELS` — read 2026-09-14. Both are why `codex-judge` is a separate block.
- `criteria/codex-review-schema.json` is the risk-3 seat's output schema — read 2026-09-14.
- `tests/run-codex-task.test.sh` stubs `codex` on a synthetic `PATH` and asserts the constructed argv — read 2026-09-14, `tests/run-codex-task.test.sh:36-38`.
- `git config core.filemode` is `false` on this machine, so `chmod +x` does not reach the index — verified 2026-09-14 during sub-project 6, where three suites were committed `100644` despite `chmod +x`.
- What a real Codex model refusal writes, and on which stream, is **unverified — Task 4 Step 5 captures one** and confirms the refusal pattern matches it. This is the single rule that separates `FALLBACK` from `FAILED`: if the real message matches none of the pattern's forms, the fallback is unreachable in production, which is the exact defect this sub-project exists to remove. The evidence available today is indirect — `README.md:136` records `luna` and `terra` "rejected with HTTP 400", and the spec's round-one finding records a refusal as "exits non-zero in seconds with no output". `reference/external-executor.md:185-191` records that Codex reports API failures on its JSON stream, which is stdout, and not on stderr; `is_refusal` therefore searches both streams rather than assuming either.
- Task 4 Step 5's probe uses an **unknown model name**. The entitlement case — a listed model the account cannot call — is inferred to produce a comparable message and is not verified by that probe.
- Whether `codex exec review --base` accepts a commit sha as well as a branch name is **unknown and stays unknown**: `--help` only exercises the argument parser, and the ref is resolved inside a real review. Task 6 passes a base branch name, which the command already passes today, and the question is logged in the spec's §12 rather than answered.
- `node scripts/test-all.mjs` has one pre-existing failure on this machine: `tests/ui-discovery.test.mjs` needs `rg`, which is not on PATH — verified 2026-09-14. Task 8 Step 5 relies on it.
- No task depends on a network call or a paid model call.

## Task index

1. The codex-judge block
2. Advertised model pairs in the detector
3. The seat runner — selection and dry-run
4. The seat runner — the outcome policy
5. The risk-3 seat calls the runner
6. The final-review round calls the runner
7. The risk-3 caller defers to the outcome policy
8. README, manifests, and the program design amendment

---

### Task 1: The codex-judge block

**Files:**
- Modify: `plugins/dr-superpowers/reference/ladder.md` (add the block after the `codex-timeout` block; correct the sentence at `:220`)
- Modify: `plugins/dr-superpowers/tests/lanes.test.sh` (append before the final `printf`)

**Interfaces:**
- Consumes: nothing.
- Produces: the `codex-judge` block, read by Task 3's script. Named in Contracts.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/lanes.test.sh`, insert this block immediately before the final `printf '\n%d passed, %d failed\n'` line. It defines its own judge allowlist rather than widening `VALID_MODELS`, so the execution assertions keep asserting exactly what they assert today:

```bash
# --- codex-judge -------------------------------------------------------------
# The judge rung is policy for the two review seats, not a rung on the
# execution ladder: run-codex-task.sh:93 validates --model against
# codex-assignment, so a judge model there would widen execution admission.
# Its allowlist is therefore separate from VALID_MODELS on purpose.
JUDGE_MODELS="gpt-6-astra gpt-5.6-sol"

judge=$(block codex-judge)
check "codex-judge block is present" "$([ -n "$judge" ] && echo yes || echo no)" "yes"

rows=$(printf '%s\n' "$judge" | grep -c .)
check "codex-judge has exactly two rows" "$rows" "2"

# Exact pairs, not merely "two distinct rows". A test that only asserts
# distinctness admits a fallback the owner never approved, and admits a row
# that does not run at high.
check "codex-judge preferred row" "$(printf '%s\n' "$judge" | sed -n 1p)" "gpt-6-astra high 1800"
check "codex-judge fallback row" "$(printf '%s\n' "$judge" | sed -n 2p)" "gpt-5.6-sol high 1800"

bad_judge=NONE
while read -r model effort secs extra; do
  [ -n "$model" ] || continue
  [ -z "$extra" ] || bad_judge="extra-field:$model"
  in_list "$model" "$JUDGE_MODELS" || bad_judge="model:$model"
  in_list "$effort" "$VALID_EFFORTS" || bad_judge="effort:$effort"
  printf '%s' "$secs" | grep -qE '^[1-9][0-9]*$' || bad_judge="timeout:$model"
done <<< "$judge"
check "codex-judge rows are well formed" "$bad_judge" "NONE"

# The third column duplicates a constant that also lives in codex-timeout.
# Nothing else would notice the two drifting apart.
drift=NONE
while read -r model effort secs _; do
  [ -n "$model" ] || continue
  t=$(printf '%s\n' "$timeouts" | awk -v k="$model/$effort" '$1 == k {print $2}')
  [ -z "$t" ] && continue
  [ "$t" = "$secs" ] || drift="$model/$effort:$secs!=$t"
done <<< "$judge"
check "codex-judge agrees with codex-timeout" "$drift" "NONE"

# The judge block must not leak into execution admission.
leak=NONE
printf '%s\n' "$assignment" | awk '{print $2}' | grep -qxF gpt-6-astra && leak=assignment
printf '%s\n' "$successor" | tr ' ' '\n' | grep -qF gpt-6-astra && leak=successor
check "no judge model appears in the execution blocks" "$leak" "NONE"
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
plugins/dr-superpowers/tests/lanes.test.sh
```

Expected: FAIL — `codex-judge block is present` reports `no`, and the row assertions report empty strings.

- [ ] **Step 3: Add the block to ladder.md**

In `plugins/dr-superpowers/reference/ladder.md`, immediately after the closing fence of the `codex-timeout` block and its following paragraph (`Seconds. One constant cannot serve both a `medium` and an `xhigh` run.`), append:

````markdown
### Codex judge rung

The two Claude-hosted review seats — the risk-3 seat and the final-review
round — take their model from this block, not from `codex-assignment`. The
first row is preferred; the last row is the fallback.

```codex-judge
gpt-6-astra high 1800
gpt-5.6-sol high 1800
```

It is a separate block for two mechanical reasons. `scripts/run-codex-task.sh`
validates `--model` against `codex-assignment`, so a judge model there would
widen execution admission. And `tests/lanes.test.sh` ranks only the execution
models, so a judge row in `codex-successor` would fail the termination proof.
Judges are excluded from the implementer ladder anyway: nothing escalates into
a review seat.

`gpt-6-astra` is the rung `reference/codex-routing.json` already floors native
judges at, so both hosts now judge at the same tier. Selection is not automatic:
`scripts/run-codex-review.sh` takes the first row the local model catalog
advertises and otherwise falls back to the last row, because a catalog listing
is not an entitlement.

1800 seconds is a provisional operational budget, not a derived figure. The only
measurement is a `gpt-5.6-sol/high` whole-branch round at roughly four minutes on
2026-09-14. Revise it when real runs warrant it.
````

- [ ] **Step 4: Correct the sentence the block falsifies**

In the same file, in the paragraph under the `codex-assignment` block, replace:

```markdown
Only `gpt-5.5` and `gpt-5.6-sol` appear in this external CLI policy. On 2026-08-31,
```

with:

```markdown
Only `gpt-5.5` and `gpt-5.6-sol` appear in this external CLI *execution* policy;
the review seats take `gpt-6-astra` from the `codex-judge` block below. On 2026-08-31,
```

- [ ] **Step 5: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/lanes.test.sh
plugins/dr-superpowers/tests/ladder.test.sh
```

Expected: both summary lines end `0 failed`. `ladder.test.sh` matches block tags exactly, so the new tag is invisible to it; if it fails, the new block was placed inside another block's fence.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/reference/ladder.md plugins/dr-superpowers/tests/lanes.test.sh
git commit -m "feat(superpowers): add the codex-judge rung"
```

---

### Task 2: Advertised model pairs in the detector

**Files:**
- Modify: `plugins/dr-superpowers/scripts/detect-executors.sh` (a new helper, one `emit` argument, one jq field)
- Modify: `plugins/dr-superpowers/tests/detect.test.sh` (append before the final `printf`)

**Interfaces:**
- Consumes: nothing.
- Produces: the `advertised` field, consumed by Task 3's script. Named in Contracts.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

This task modifies a script two skills call at plan time and again at every dispatch. The field is additive and every existing field keeps its meaning: `usable` still means "the CLI is dispatchable" and never "this model will be accepted".

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/detect.test.sh`, insert this block immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
# --- advertised model pairs --------------------------------------------------
# The cache is a negative filter: a pair it does not list is never attempted.
# It is not entitlement — gpt-5.6-luna and gpt-5.6-terra were listed on
# 2026-09-14 and were rejected with HTTP 400 on this account on 2026-08-31.
cat > "$TMP/bin/codex" <<STUB
#!$BASH_BIN
case "\$1" in
  login) echo "Logged in using ChatGPT" ;;
  *) echo "codex-cli 0.153.4" ;;
esac
STUB
chmod +x "$TMP/bin/codex"

write_cache() { printf '%s' "$1" > "$TMP/codexhome/models_cache.json"; }

write_cache '{"fetched_at":"2026-09-14T13:35:00Z","client_version":"0.153.4","models":[
  {"slug":"gpt-6-astra","visibility":"list","supported_reasoning_levels":[{"effort":"high"},{"effort":"xhigh"}]},
  {"slug":"gpt-5.6-sol","visibility":"list","supported_reasoning_levels":[{"effort":"high"}]},
  {"slug":"gpt-reserve","visibility":"hide","supported_reasoning_levels":[{"effort":"high"}]}]}'
out=$(run)
check "advertised: fetched_at" "$(field codex advertised "$out" | jq -r '.fetched_at')" "2026-09-14T13:35:00Z"
check "advertised: client_version" "$(field codex advertised "$out" | jq -r '.client_version')" "0.153.4"
check "advertised: astra/high is listed" \
  "$(field codex advertised "$out" | jq '[.pairs[] | select(.model=="gpt-6-astra" and .effort=="high")] | length')" "1"
check "advertised: hidden models are filtered out" \
  "$(field codex advertised "$out" | jq '[.pairs[] | select(.model=="gpt-reserve")] | length')" "0"
# jq -r prints "null" for a key that does not exist, so a value check alone
# would pass against the unmodified script. Assert the key is present too.
has_field() { jq -r --arg i "$1" --arg f "$2" '.[] | select(.id==$i) | has($f)' <<< "$3"; }
check "advertised: the key exists on every row" "$(has_field cursor-agent advertised "$out")" "true"
check "advertised: non-codex rows are null" "$(field cursor-agent advertised "$out")" "null"

# A cache that lists nothing is not the same fact as no cache at all.
write_cache '{"fetched_at":"2026-09-14T13:35:00Z","client_version":"0.153.4","models":[]}'
out=$(run)
check "advertised: empty catalog is an empty pair list" \
  "$(field codex advertised "$out" | jq -c '.pairs')" "[]"

write_cache 'not json at all'
out=$(run)
check "advertised: malformed cache is null" "$(field codex advertised "$out")" "null"
check "malformed cache still emits the key" "$(has_field codex advertised "$out")" "true"
check "malformed cache does not break the roster" \
  "$(jq -e 'type=="array"' >/dev/null 2>&1 <<<"$out" && echo yes || echo no)" "yes"

# A half-written cache during a concurrent codex run: valid JSON followed by
# garbage. jq emits the object and then fails, so an unguarded extraction
# yields "{...}null", which --argjson rejects - and the whole codex row
# disappears from the roster, silently losing the lane.
write_cache '{"fetched_at":"x","client_version":"y","models":[]} trailing garbage'
out=$(run)
check "advertised: trailing garbage is null" "$(field codex advertised "$out")" "null"
check "trailing garbage keeps the codex row" \
  "$(jq -r '[.[] | select(.id=="codex")] | length' <<<"$out")" "1"

rm -f "$TMP/codexhome/models_cache.json"
out=$(run)
check "advertised: absent cache is null" "$(field codex advertised "$out")" "null"
check "absent cache still emits the key" "$(has_field codex advertised "$out")" "true"
check "absent cache leaves codex usable" "$(field codex usable "$out")" "true"
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
plugins/dr-superpowers/tests/detect.test.sh
```

Expected: FAIL. Specifically, these fail: the three key-presence checks (`the key exists on every row`, `malformed cache still emits the key`, `absent cache still emits the key`), plus `advertised: fetched_at`, `advertised: client_version`, `advertised: astra/high is listed`, `advertised: hidden models are filtered out`, and `advertised: empty catalog is an empty pair list`.

These **pass even now**, and that is expected: the bare value checks for the `null` cases (`non-codex rows are null`, `malformed cache is null`, `trailing garbage is null`, `absent cache is null`), because `jq -r` prints `null` for a key that does not exist — which is exactly why each is paired with a key-presence check; and `malformed cache does not break the roster`, `trailing garbage keeps the codex row` and `absent cache leaves codex usable`, because the roster and its codex row exist whether or not the cache is read at all.

- [ ] **Step 3: Emit the field**

In `plugins/dr-superpowers/scripts/detect-executors.sh`, insert this helper immediately above the `emit()` definition:

```bash
# The local Codex model catalog, as a negative filter. A pair absent from it is
# never attempted; a pair present in it is attempted and the seat runner's
# outcome policy carries the guarantee. Catalog listing is not entitlement:
# gpt-5.6-luna and gpt-5.6-terra were listed on 2026-09-14 and were rejected
# with HTTP 400 on this account on 2026-08-31.
#
# null and an empty pair list are different facts and must stay
# distinguishable: null means no usable catalog was read, [] means one was read
# and advertised nothing.
advertised_pairs() {
  local cache="${CODEX_HOME:-$HOME/.codex}/models_cache.json"
  [ -r "$cache" ] || { printf 'null'; return; }
  # Validate before extracting. A cache that is a valid object followed by
  # trailing bytes - a half-written file during a concurrent codex run - makes
  # jq print the object and *then* fail, so an unguarded `|| printf null`
  # appends to real output and yields "{...}null". --argjson would reject that
  # and emit() would produce nothing, dropping the codex row from the roster
  # entirely: a silent loss of the whole lane.
  jq -e . "$cache" >/dev/null 2>&1 || { printf 'null'; return; }
  jq -c '{fetched_at: .fetched_at, client_version: .client_version,
          pairs: [.models[]? | select(.visibility == "list") as $m
                  | $m.supported_reasoning_levels[]?
                  | {model: $m.slug, effort: .effort}]}' "$cache" 2>/dev/null \
    || printf 'null'
}
```

In `emit()`, add one local and one assignment. Change the locals line:

```bash
  local path present version authed reason usable auth_status=not_applicable
```

to:

```bash
  local path present version authed reason usable auth_status=not_applicable advertised=null
```

Immediately after the `authed=null` block's closing `fi` — that is, after the codex authentication probe and before the `usable=false` line — insert:

```bash
  if [ "$id" = codex ] && [ "$present" = true ]; then
    advertised=$(advertised_pairs)
  fi
```

Then add the field to the jq call. Change:

```bash
    --argjson reason "$reason" \
    --arg path "$path" \
```

to:

```bash
    --argjson reason "$reason" \
    --argjson advertised "$advertised" \
    --arg path "$path" \
```

and change the object body's last line:

```bash
      usable:$usable, reason:$reason}'
```

to:

```bash
      usable:$usable, reason:$reason, advertised:$advertised}'
```

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/detect.test.sh
```

Expected: the summary line ends `0 failed`, including every pre-existing check.

- [ ] **Step 5: Prove the field is real on this machine**

Run:

```bash
plugins/dr-superpowers/scripts/detect-executors.sh | jq -r '.[] | select(.id=="codex") | (.advertised.pairs // []) | map(select(.model=="gpt-6-astra")) | length'
```

Expected: a non-zero count. A `0` or `null` here means the local cache does not advertise Astra; that is not a failure of this task — record the output in the ledger and continue, because the fallback path in Task 4 is exactly what covers it.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/detect-executors.sh plugins/dr-superpowers/tests/detect.test.sh
git commit -m "feat(superpowers): emit advertised codex model pairs"
```

---

### Task 3: The seat runner — selection and dry-run

**Files:**
- Create: `plugins/dr-superpowers/scripts/run-codex-review.sh`
- Create: `plugins/dr-superpowers/tests/codex-review.test.sh`

**Interfaces:**
- Consumes: the `codex-judge` block from Task 1 and the `advertised` field from Task 2, both named in Contracts.
- Produces: the `scripts/run-codex-review.sh` interface and the four outcome names, named in Contracts. Tasks 5 and 6 call it; Task 4 extends it.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/codex-review.test.sh`:

```bash
#!/usr/bin/env bash
# The selection rule and the outcome policy are the two things a review seat
# gets wrong silently: a wrong model still produces a review, and a failed run
# still produces a file. Both are asserted here against a stub codex, so no
# model call is made and every branch is reachable.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/run-codex-review.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <haystack> <needle>
  case "$2" in
    *"$3"*) printf 'ok   - %s\n' "$1"; pass=$((pass + 1)) ;;
    *) printf 'FAIL - %s\n       missing: [%s]\n' "$1" "$3"; fail=$((fail + 1)) ;;
  esac
}

mkdir -p "$TMP/bin" "$TMP/codexhome" "$TMP/work"
BASH_BIN=$(command -v bash)
for dep in jq timeout head tr sed awk grep cat mktemp rm; do
  printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$(command -v "$dep")" > "$TMP/bin/$dep"
  chmod +x "$TMP/bin/$dep"
done

# A stub roster, so selection is tested without probing the real machine.
write_roster() { # write_roster <advertised-json>
  cat > "$TMP/bin/detect-stub" <<STUB
#!$BASH_BIN
cat <<'JSON'
[{"id":"codex","present":true,"path":"/stub/codex","version":"codex-cli 0.153.4",
  "authed":true,"auth_status":"authenticated","batch_capable":true,"usable":true,
  "reason":null,"advertised":$1}]
JSON
STUB
  chmod +x "$TMP/bin/detect-stub"
}

ASTRA='{"fetched_at":"2026-09-14T13:35:00Z","client_version":"0.153.4","pairs":[{"model":"gpt-6-astra","effort":"high"}]}'
SOL_ONLY='{"fetched_at":"2026-09-14T13:35:00Z","client_version":"0.153.4","pairs":[{"model":"gpt-5.6-sol","effort":"high"}]}'
EMPTY='{"fetched_at":"2026-09-14T13:35:00Z","client_version":"0.153.4","pairs":[]}'

run() { # run <args...>
  PATH="$TMP/bin:$PATH" CODEX_REVIEW_ROSTER="$TMP/bin/detect-stub" \
    "$BASH_BIN" "$SCRIPT" "$@" 2>"$TMP/err"
}

check "script exists" "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"

# --- selection ---------------------------------------------------------------
write_roster "$ASTRA"
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run)
present "advertised astra selects astra" "$out" "codex-judge gpt-6-astra/high"
present "dry run reports OK" "$out" "status=OK"
present "dry run carries the cache date as evidence" "$out" "evidence=2026-09-14T13:35:00Z"
# Line-exact: --dry-run prints one argv token per line, and a substring test
# for "review" would also match the schema filename.
tok() { printf '%s\n' "$2" | grep -qx -- "$3"; }
if tok x "$out" review; then printf 'ok   - final kind uses codex exec review\n'; pass=$((pass + 1))
else printf 'FAIL - final kind uses codex exec review\n'; fail=$((fail + 1)); fi
if tok x "$out" '--base' && tok x "$out" main; then
  printf 'ok   - final kind passes the base\n'; pass=$((pass + 1))
else printf 'FAIL - final kind passes the base\n'; fail=$((fail + 1)); fi
present "selected effort reaches the command" "$out" "model_reasoning_effort=high"

# Fail closed: three distinct states, one outcome.
write_roster "$SOL_ONLY"
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run)
present "catalog without astra falls back to sol" "$out" "codex-judge gpt-5.6-sol/high"

write_roster "$EMPTY"
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run)
present "empty catalog falls back to sol" "$out" "codex-judge gpt-5.6-sol/high"

write_roster null
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run)
present "absent catalog falls back to sol" "$out" "codex-judge gpt-5.6-sol/high"
present "absent catalog reports unknown evidence" "$out" "evidence=unknown"

# --- the two kinds differ ----------------------------------------------------
write_roster "$ASTRA"
printf 'prompt text\n' > "$TMP/p.txt"
out=$(run --kind risk3 --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
if tok x "$out" '--output-schema'; then printf 'ok   - risk3 passes a schema flag\n'; pass=$((pass + 1))
else printf 'FAIL - risk3 passes a schema flag\n'; fail=$((fail + 1)); fi
present "risk3 is read-only" "$out" "read-only"
present "risk3 passes the review schema" "$out" "codex-review-schema.json"
if tok x "$out" review; then printf 'FAIL - risk3 never uses codex exec review\n'; fail=$((fail + 1))
else printf 'ok   - risk3 never uses codex exec review\n'; pass=$((pass + 1)); fi

# The unusable branch has its own status line and must still be parseable.
cat > "$TMP/bin/detect-stub" <<STUB
#!$BASH_BIN
cat <<'JSON'
[{"id":"codex","present":true,"path":null,"version":null,"authed":false,
  "auth_status":"logged_out","batch_capable":true,"usable":false,
  "reason":"present but not authenticated; run codex login","advertised":null}]
JSON
STUB
chmod +x "$TMP/bin/detect-stub"
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run); rc=$?
present "an unusable codex is FAILED" "$out" "status=FAILED"
present "the unusable status line keeps the model/effort shape" "$out" "codex-judge none/none"
check "an unusable codex exits 1" "$rc" "1"

# --- usage errors are exit 2, before any call --------------------------------
run --kind risk3 --cwd "$TMP/work" --out "$TMP/o.json" --dry-run >/dev/null; rc=$?
check "risk3 without --prompt is a usage error" "$rc" "2"
run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --dry-run >/dev/null; rc=$?
check "final without --base is a usage error" "$rc" "2"
run --kind bogus --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run >/dev/null; rc=$?
check "an unknown kind is a usage error" "$rc" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
chmod +x plugins/dr-superpowers/tests/codex-review.test.sh
plugins/dr-superpowers/tests/codex-review.test.sh
```

Expected: FAIL — `script exists` reports `no`.

- [ ] **Step 3: Write the runner**

Create `plugins/dr-superpowers/scripts/run-codex-review.sh`:

```bash
#!/usr/bin/env bash
# Runs one Codex review seat: selects the judge rung, bounds the run, and
# classifies the outcome.
#
# Both Claude-hosted seats call this instead of composing a codex command
# themselves. An earlier design left the selection and fallback rules in prose,
# and the runtime never reached the paragraph describing them: the fallback was
# unreachable code written in English. Anything a seat must decide lives here,
# where a test can reach it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER="$HERE/../reference/ladder.md"
SCHEMA="$HERE/../criteria/codex-review-schema.json"
# Tests point this at a stub roster. Unset in production, where the real
# detector runs and its auth probe is the usability guard.
ROSTER="${CODEX_REVIEW_ROSTER:-$HERE/detect-executors.sh}"

die() { printf 'run-codex-review: %s\n' "$1" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || die "jq is required but not on PATH"
command -v timeout >/dev/null 2>&1 || die "GNU timeout is required but not on PATH"

kind=""; cwd=""; out=""; prompt=""; base=""; dry_run=false
while [ $# -gt 0 ]; do
  case "$1" in
    --kind|--cwd|--out|--prompt|--base) [ $# -ge 2 ] || die "$1 needs a value" ;;
  esac
  case "$1" in
    --kind) kind="$2"; shift 2 ;;
    --cwd) cwd="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --prompt) prompt="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$kind" in
  risk3) [ -n "$prompt" ] || die "--kind risk3 requires --prompt" ;;
  final) [ -n "$base" ] || die "--kind final requires --base" ;;
  *) die "--kind must be risk3 or final" ;;
esac
[ -n "$cwd" ] || die "--cwd is required"
[ -n "$out" ] || die "--out is required"
[ -d "$cwd" ] || die "--cwd is not a directory: $cwd"
[ -d "$(dirname "$out")" ] || die "--out directory not found: $(dirname "$out")"

# Resolve before anything runs. The seat runs inside a subshell that cd's to
# --cwd, while the output is read back from here, so a relative path would be
# written into the worktree and then reported missing.
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
cwd="$(cd "$cwd" && pwd)"
[ "$kind" != risk3 ] || [ -r "$prompt" ] || die "--prompt is not readable: $prompt"
[ "$kind" != risk3 ] || [ -r "$SCHEMA" ] || die "review schema not found: $SCHEMA"
[ -z "$prompt" ] || prompt="$(cd "$(dirname "$prompt")" && pwd)/$(basename "$prompt")"

# The judge policy, first row preferred and last row the fallback.
judge=$(awk '
  $0 == "```codex-judge" { f = 1; next }
  f && $0 == "```" { exit }
  f && NF { print }
' "$LADDER")
[ -n "$judge" ] || die "the codex-judge block is missing from $LADDER"

pref_model=$(printf '%s\n' "$judge" | sed -n 1p | awk '{print $1}')
pref_effort=$(printf '%s\n' "$judge" | sed -n 1p | awk '{print $2}')
back_model=$(printf '%s\n' "$judge" | tail -1 | awk '{print $1}')
back_effort=$(printf '%s\n' "$judge" | tail -1 | awk '{print $2}')
secs_of() { printf '%s\n' "$judge" | awk -v m="$1" -v e="$2" '$1 == m && $2 == e {print $3; exit}'; }

# Selection. The catalog is a negative filter: a pair it does not advertise is
# never attempted, and every state that is not a positive match - no catalog, an
# unreadable one, one that lists nothing, one that lists other models - takes the
# fallback row. That is the owner's fail-closed rule, and null is deliberately
# not treated as [].
# Invoked through bash, not executed directly: core.filemode is false on some
# checkouts, so the detector can arrive at mode 100644 and a direct call would
# fail every seat with "no codex row".
roster=$(bash "$ROSTER" 2>/dev/null) || roster=""
codex_row=$(printf '%s' "$roster" | jq -c '.[]? | select(.id=="codex")' 2>/dev/null)
[ -n "$codex_row" ] || die "no codex row in the executor roster"

usable=$(printf '%s' "$codex_row" | jq -r '.usable')
if [ "$usable" != true ]; then
  reason=$(printf '%s' "$codex_row" | jq -r '.reason // "codex is not usable"')
  printf 'codex-judge none/none status=FAILED exit=0 out=%s evidence=unknown\n' "$out"
  printf 'run-codex-review: %s\n' "$reason" >&2
  exit 1
fi

advertised=$(printf '%s' "$codex_row" | jq -c '.advertised')
if [ "$advertised" = null ]; then
  evidence=unknown
  listed=false
else
  evidence=$(printf '%s' "$advertised" | jq -r '.fetched_at // "unknown"')
  listed=$(printf '%s' "$advertised" | jq --arg m "$pref_model" --arg e "$pref_effort" \
    '[.pairs[]? | select(.model == $m and .effort == $e)] | length > 0')
fi

if [ "$listed" = true ]; then
  model="$pref_model"; effort="$pref_effort"
else
  model="$back_model"; effort="$back_effort"
fi
secs=$(secs_of "$model" "$effort")
[ -n "$secs" ] || die "no timeout for $model/$effort in the codex-judge block"

# The command each kind runs. risk3 uses plain `codex exec` with this plugin's
# own schema, never `codex exec review`, which imposes its own report shape -
# the three risk-3 judges must return comparable criteria.
build_argv() { # build_argv <model> <effort>
  if [ "$kind" = risk3 ]; then
    printf '%s\n' codex exec -s read-only -m "$1" -c "model_reasoning_effort=$2" \
      --output-schema "$SCHEMA" -o "$out" -C "$cwd"
  else
    printf '%s\n' codex exec review --base "$base" -m "$1" -c "model_reasoning_effort=$2" \
      -o "$out"
  fi
}

if [ "$dry_run" = true ]; then
  printf 'would-run:\n'
  build_argv "$model" "$effort"
  printf 'codex-judge %s/%s status=OK exit=0 out=%s evidence=%s\n' \
    "$model" "$effort" "$out" "$evidence"
  exit 0
fi

die "only --dry-run is implemented; see Task 4"
```

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/codex-review.test.sh
```

Expected: the summary line ends `0 failed`.

- [ ] **Step 5: Commit**

`core.filemode` is `false` here, so `chmod +x` does not reach the index.

```bash
chmod +x plugins/dr-superpowers/scripts/run-codex-review.sh plugins/dr-superpowers/tests/codex-review.test.sh
git add plugins/dr-superpowers/scripts/run-codex-review.sh plugins/dr-superpowers/tests/codex-review.test.sh
git update-index --chmod=+x plugins/dr-superpowers/scripts/run-codex-review.sh plugins/dr-superpowers/tests/codex-review.test.sh
git commit -m "feat(superpowers): add the codex review seat runner"
```

---

### Task 4: The seat runner — the outcome policy

**Files:**
- Modify: `plugins/dr-superpowers/scripts/run-codex-review.sh` (replace the final `die` line with the run and classification)
- Modify: `plugins/dr-superpowers/tests/codex-review.test.sh` (append before the final `printf`)

**Interfaces:**
- Consumes: Task 3's script and its status-line format, named in Contracts.
- Produces: the four outcome names and the per-kind validity rule, named in Contracts. Tasks 5, 6 and 7 describe this policy in prose.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

This is the task the whole sub-project exists for. Three axes are tracked separately — process exit, deadline expiry, and per-kind output validity — because conflating them is what makes a failed review read as a clean one. Only an explicit model or effort refusal selects the fallback: a different model repairs neither an expired token nor an exhausted quota nor a cancelled run, and a second attempt would fail identically.

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/codex-review.test.sh`, insert this block immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
# --- the outcome policy ------------------------------------------------------
# A stub codex whose behaviour is chosen per case by CODEX_STUB_MODE. The
# fallback cases need the stub to behave differently on its second invocation,
# so it counts its own calls.
cat > "$TMP/bin/codex" <<STUB
#!$BASH_BIN
n=\$(cat "$TMP/calls" 2>/dev/null || echo 0); n=\$((n + 1)); printf '%s' "\$n" > "$TMP/calls"
model=""; prev=""
for a in "\$@"; do [ "\$prev" = "-m" ] && model="\$a"; prev="\$a"; done
outfile=""; prev=""
for a in "\$@"; do [ "\$prev" = "-o" ] && outfile="\$a"; prev="\$a"; done
case "\$CODEX_STUB_MODE" in
  ok) printf '{"spec_verdict":"met","task_quality":18,"cannot_verify":[]}' > "\$outfile"; exit 0 ;;
  ok-final) printf 'a review\n' > "\$outfile"; exit 0 ;;
  empty) : > "\$outfile"; exit 0 ;;
  noout) exit 0 ;;
  refuse-then-ok)
    if [ "\$model" = gpt-6-astra ]; then
      echo "stream error: unsupported model gpt-6-astra" >&2; exit 1
    fi
    printf 'a review\n' > "\$outfile"; exit 0 ;;
  refuse-always) echo "stream error: unsupported model \$model" >&2; exit 1 ;;
  # An API-level refusal arrives on the JSON event stream, which is stdout.
  refuse-stdout)
    if [ "\$model" = gpt-6-astra ]; then
      echo '{"type":"error","message":"http 400: model not available"}'; exit 1
    fi
    printf 'a review\n' > "\$outfile"; exit 0 ;;
  authfail) echo "stream error: 401 unauthorized" >&2; exit 1 ;;
  cancel) exit 130 ;;
  # 124 is what coreutils timeout returns after it kills the child; the stub
  # returns it directly, so this asserts the classification, not the deadline.
  hang) exit 124 ;;
esac
exit 1
STUB
chmod +x "$TMP/bin/codex"

seat() { # seat <mode> <kind> <extra-args...>
  rm -f "$TMP/calls" "$TMP"/o.md* "$TMP"/o.json*
  local mode="$1" k="$2"; shift 2
  CODEX_STUB_MODE="$mode" run --kind "$k" --cwd "$TMP/work" "$@"
}

write_roster "$ASTRA"

out=$(seat ok-final final --out "$TMP/o.md" --base main); rc=$?
present "a complete run with output is OK" "$out" "status=OK"
check "OK exits 0" "$rc" "0"

out=$(seat empty final --out "$TMP/o.md" --base main); rc=$?
present "exit 0 with an empty report is FAILED" "$out" "status=FAILED"
check "FAILED exits 1" "$rc" "1"

out=$(seat noout final --out "$TMP/o.md" --base main)
present "exit 0 with no report at all is FAILED" "$out" "status=FAILED"

out=$(seat ok risk3 --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "a schema-shaped risk3 report is OK" "$out" "status=OK"

out=$(seat ok-final risk3 --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "risk3 output that is not schema-shaped is FAILED" "$out" "status=FAILED"

out=$(seat hang final --out "$TMP/o.md" --base main); rc=$?
present "exit 124 is TIMEOUT, never a model change" "$out" "status=TIMEOUT"
check "TIMEOUT exits 1" "$rc" "1"
check "TIMEOUT does not run a second seat" "$(cat "$TMP/calls")" "1"

out=$(seat refuse-then-ok final --out "$TMP/o.md" --base main); rc=$?
present "a refused model falls back once" "$out" "status=FALLBACK"
present "the fallback line names the model that ran" "$out" "codex-judge gpt-5.6-sol/high"
check "FALLBACK exits 0" "$rc" "0"
check "the fallback runs exactly one extra seat" "$(cat "$TMP/calls")" "2"

out=$(seat refuse-always final --out "$TMP/o.md" --base main)
present "a fallback that also fails is FAILED" "$out" "status=FAILED"
check "the fallback is attempted at most once" "$(cat "$TMP/calls")" "2"

out=$(seat authfail final --out "$TMP/o.md" --base main)
present "an auth failure is FAILED, not a model change" "$out" "status=FAILED"
check "an auth failure runs no second seat" "$(cat "$TMP/calls")" "1"

# A cancelled run is the owner's decision, not a capability signal.
out=$(seat cancel final --out "$TMP/o.md" --base main)
present "a cancelled run is FAILED, not a model change" "$out" "status=FAILED"
check "a cancelled run runs no second seat" "$(cat "$TMP/calls")" "1"

# Already on the fallback row: there is nothing to fall back to.
write_roster "$SOL_ONLY"
out=$(seat refuse-always final --out "$TMP/o.md" --base main)
present "a refusal on the fallback row is FAILED" "$out" "status=FAILED"
check "the fallback row is never retried against itself" "$(cat "$TMP/calls")" "1"

write_roster "$ASTRA"
out=$(seat refuse-stdout final --out "$TMP/o.md" --base main)
present "a refusal on stdout also falls back" "$out" "status=FALLBACK"
check "the stdout refusal runs exactly one extra seat" "$(cat "$TMP/calls")" "2"

# The refusal must survive the fallback run, because the ledger quotes it.
seat refuse-then-ok final --out "$TMP/o.md" --base main >/dev/null
check "the refusal's own logs are kept" \
  "$([ -s "$TMP/o.md.stderr" ] && echo yes || echo no)" "yes"
check "the fallback writes its own logs" \
  "$([ -f "$TMP/o.md.fallback.stderr" ] && echo yes || echo no)" "yes"
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
plugins/dr-superpowers/tests/codex-review.test.sh
```

Expected: FAIL — every outcome check reports the `only --dry-run is implemented` path.

- [ ] **Step 3: Implement the policy**

In `plugins/dr-superpowers/scripts/run-codex-review.sh`, replace the final line:

```bash
die "only --dry-run is implemented; see Task 4"
```

with:

```bash
# Valid output is defined per kind. risk3 must parse as the criteria the other
# two judges return; final has no schema and only has to be non-empty.
valid_output() {
  if [ "$kind" = risk3 ]; then
    jq -e 'has("spec_verdict") and has("task_quality") and has("cannot_verify")' \
      "$out" >/dev/null 2>&1
  else
    [ -s "$out" ]
  fi
}

# A refusal is the one failure a different model repairs. An expired token, an
# exhausted quota, a bad working directory and a cancelled run are not refusals:
# the fallback would fail identically and would cost a second full round.
#
# Both streams are searched. Codex reports API failures as events on its JSON
# stream, which is stdout - see external-executor.md, "Read `## Codex error` in
# the report, not `<report>.stderr`" - while stderr carries the CLI's own
# complaints. A model refusal can arrive on either, and searching only stderr
# would make this whole rule unreachable for the API-level case.
is_refusal() { # is_refusal <log-prefix>
  grep -qiE '(unsupported|unknown|invalid|not (supported|available|found)).*(model|effort)|(model|effort).*(unsupported|unknown|invalid|not (supported|available|found))|http 400|status 400' \
    "$1.stdout" "$1.stderr" 2>/dev/null
}

refusal_line() { # refusal_line <log-prefix>
  cat "$1.stderr" "$1.stdout" 2>/dev/null | grep -m1 . | tr -d '\r'
}

# Each attempt writes its own pair of logs. Sharing one would let the fallback's
# (usually empty) output overwrite the refusal that explains why the fallback
# ran at all, which is the line the ledger substitution quotes.
run_seat() { # run_seat <model> <effort> <seconds> <log-prefix>; echoes the exit code
  local argv=() line
  while IFS= read -r line; do argv+=("$line"); done < <(build_argv "$1" "$2")
  rm -f "$out"
  ( cd "$cwd" && timeout "$3" "${argv[@]}" >"$4.stdout" 2>"$4.stderr" \
      < "${prompt:-/dev/null}" )
  printf '%s' "$?"
}

status() { # status <model> <effort> <state> <exit>
  printf 'codex-judge %s/%s status=%s exit=%s out=%s evidence=%s\n' \
    "$1" "$2" "$3" "$4" "$out" "$evidence"
}

rc=$(run_seat "$model" "$effort" "$secs" "$out")

# Deadline expiry is tracked apart from every other non-zero exit: a hang and a
# refusal both exit non-zero, and only one of them is worth a second run.
if [ "$rc" -eq 124 ]; then
  status "$model" "$effort" TIMEOUT "$rc"; exit 1
fi

if [ "$rc" -eq 0 ] && valid_output; then
  status "$model" "$effort" OK "$rc"; exit 0
fi

# The fallback is attempted at most once, and never when the row that just ran
# is already the fallback row.
if is_refusal "$out" \
   && { [ "$model" != "$back_model" ] || [ "$effort" != "$back_effort" ]; }; then
  printf 'run-codex-review: %s/%s refused (%s); falling back to %s/%s\n' \
    "$model" "$effort" "$(refusal_line "$out")" "$back_model" "$back_effort" >&2
  back_secs=$(secs_of "$back_model" "$back_effort")
  rc=$(run_seat "$back_model" "$back_effort" "$back_secs" "$out.fallback")
  if [ "$rc" -eq 124 ]; then
    status "$back_model" "$back_effort" TIMEOUT "$rc"; exit 1
  fi
  if [ "$rc" -eq 0 ] && valid_output; then
    status "$back_model" "$back_effort" FALLBACK "$rc"; exit 0
  fi
  status "$back_model" "$back_effort" FAILED "$rc"; exit 1
fi

status "$model" "$effort" FAILED "$rc"; exit 1
```

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/codex-review.test.sh
```

Expected: the summary line ends `0 failed`, including every selection check from Task 3.

- [ ] **Step 5: Capture a real refusal and check the pattern against it**

`is_refusal` is the one rule that separates `FALLBACK` from `FAILED`, and it was written against indirect evidence. Capture a real refusal. A rejected model name is refused by the API before any reasoning happens, so this costs no tokens; it is not the paid capability probe `reference/ladder.md` forbids.

Capture **both** streams. `reference/external-executor.md` records that Codex reports API failures as events on its JSON stream — stdout — while stderr carries the CLI's own complaints, so which stream a refusal uses is itself part of what this step establishes:

```bash
cd "$(git rev-parse --show-toplevel)"
printf 'reply with the single word ok\n' > /tmp/refusal-probe.txt
timeout 120 codex exec -s read-only -m definitely-not-a-real-model \
  -c model_reasoning_effort=high -o /tmp/refusal-probe.report \
  < /tmp/refusal-probe.txt > /tmp/refusal-probe.stdout 2>/tmp/refusal-probe.stderr
printf 'exit=%s\n' "$?"
echo "--- stdout:"; cat /tmp/refusal-probe.stdout
echo "--- stderr:"; cat /tmp/refusal-probe.stderr
```

Record the exit code, which stream carried the message, and the message itself in the ledger as a `Ruling:` line. Then check the pattern against both:

```bash
grep -qiE '(unsupported|unknown|invalid|not (supported|available|found)).*(model|effort)|(model|effort).*(unsupported|unknown|invalid|not (supported|available|found))|http 400|status 400' \
  /tmp/refusal-probe.stdout /tmp/refusal-probe.stderr \
  && echo "pattern matches" || echo "pattern MISSES - widen it"
rm -f /tmp/refusal-probe.txt /tmp/refusal-probe.report /tmp/refusal-probe.stdout /tmp/refusal-probe.stderr
```

Expected: `pattern matches`. `is_refusal` already searches both streams, so a message on either satisfies it.

On `pattern MISSES`, widen `is_refusal` in `scripts/run-codex-review.sh` to match the observed wording, add the observed line as a new stub mode in `tests/codex-review.test.sh` asserting `status=FALLBACK`, and re-run the suite. Do **not** widen it to anything that would also match an authentication or quota message — the `authfail` and `cancel` cases assert that those stay `FAILED`, and a pattern that matches them would fail there.

This probe establishes the wording for an **unknown model name**. The production case this design was written for is different — a model the catalog lists but the account is not entitled to, which is what `README.md` records as HTTP 400 for `luna` and `terra` on 2026-08-31. The two may take different API paths. Say in the ruling which one you verified, so a later session knows the entitlement form is still inferred rather than observed.

If the probe cannot run at all (no network, unauthenticated), say so, leave the pattern as written, and record that the assumption is still unverified. Do not claim it was checked.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/run-codex-review.sh plugins/dr-superpowers/tests/codex-review.test.sh
git commit -m "feat(superpowers): classify codex review outcomes"
```

---

### Task 5: The risk-3 seat calls the runner

**Files:**
- Modify: `plugins/dr-superpowers/reference/external-executor.md` (§Risk-3 Codex seat; the Failure rows table)

**Interfaces:**
- Consumes: the runner interface and the four outcome names from Tasks 3 and 4, named in Contracts.
- Produces: nothing later tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 1 = 2

- [ ] **Step 1: Replace the seat's command block**

In `plugins/dr-superpowers/reference/external-executor.md`, in §Risk-3 Codex seat, replace this block:

````markdown
```bash
timeout 1800 codex exec -s read-only -m gpt-5.6-sol -c model_reasoning_effort=high \
  --output-schema "<plugin-root>/criteria/codex-review-schema.json" \
  -o <workspace>/task-<N>-review-codex.json \
  -C <worktree-root> < <prompt-file>
```
````

with:

````markdown
```bash
bash "<plugin-root>/scripts/run-codex-review.sh" --kind risk3 \
  --cwd <worktree-root> --out <workspace>/task-<N>-review-codex.json \
  --prompt <prompt-file>
```

The runner owns the model, the effort, the bound and the outcome. It takes the
first row of [ladder.md](ladder.md)'s `codex-judge` block that the local model
catalog advertises, falls back to that block's last row whenever the catalog is
absent, unreadable or silent, and prints one status line:

```
codex-judge <model>/<effort> status=OK|FALLBACK|TIMEOUT|FAILED exit=<n> out=<path> evidence=<fetched_at>
```

Read that line and nothing else. `OK` and `FALLBACK` are a seat that scored;
`FALLBACK` additionally means the preferred rung refused the run, so say the
substitution aloud and record it in the task's ledger line with the reason the
runner prints in its own `refused (...)` message — it reads that line from
`<out>.stderr` or `<out>.stdout`, because an API-level refusal arrives on the
JSON stream rather than on stderr. `TIMEOUT` and `FAILED` are a seat that
produced no score.
````

- [ ] **Step 2: Replace the timeout paragraph that follows it**

In the same section, replace:

```markdown
A `timeout` exit of 124 is a seat that produced no score. Fall back to a third
Claude judge rather than averaging two scores as if three had voted.
```

with:

```markdown
`TIMEOUT` or `FAILED` is a seat that produced no score. Fall back to a third
Claude judge rather than averaging two scores as if three had voted. Never read
an absent or malformed report as a clean review, and never count it as a third
vote: the runner has already distinguished a report that is missing from one
that is merely unfavourable.
```

- [ ] **Step 3: Remove the prose the runner now owns**

The section still tells the controller to establish usability itself, to look up the `codex-timeout` row, and to wrap the call in its own `timeout`. The runner does all three, so a controller following both would double-wrap the bound and pre-read a roster the runner re-reads.

The text to remove starts mid-paragraph and **the phrase wraps across two lines** in the file — `does not share. Establish` ends one line and `usability by running` begins the next — so search for `Establish` rather than for the whole phrase. Keep the sentence ending `a property the final-review Codex round does not share.` and delete from `Establish usability by running` through `nothing but the round.`, which is the rest of that paragraph plus the `Run it as a background Bash call` paragraph plus the whole `**This seat needs its own bound, unlike the task wrapper.**` paragraph. Insert the replacement as its own new paragraph between the surviving sentence and the command block:

```markdown
The runner establishes usability from the roster itself and never trusts the
plan's copy, applies the `codex-judge` row's bound with coreutils `timeout`, and
reports `FAILED` with the roster's own `reason` when Codex is not usable. Run it
as a background Bash call: the Bash tool's `timeout` caps at ten minutes, the
rung's bound is longer, and a background call is not bound by it at all.
```

Then, near the top of the same file, add the new block to the sentence listing what `ladder.md` holds. Replace:

```markdown
The lane is a gate in front of the Claude assignment table, never a rung on the
escalation ladder. [ladder.md](ladder.md) explains why, and holds the `gate`,
`codex-assignment`, `codex-successor`, and `codex-timeout` blocks read below.
```

with:

```markdown
The lane is a gate in front of the Claude assignment table, never a rung on the
escalation ladder. [ladder.md](ladder.md) explains why, and holds the `gate`,
`codex-assignment`, `codex-successor`, and `codex-timeout` blocks read below,
plus the `codex-judge` block the review seats' runner reads.
```

- [ ] **Step 4: Add the refusal row to the Failure rows table**

In the same file, append this as the **last** row of the `## Failure rows` table — the row after the one beginning `| A fix round returned DONE with an empty diff`. Do not confuse that table with the "When a run fails" table earlier in the file, which is about task runs and has its own timeout row:

```markdown
| A review seat's status line says `FALLBACK` | The preferred judge rung refused the run and the runner already used the fallback once. Not a failure: record the substitution and its reason in the ledger line you are already writing |
```

- [ ] **Step 5: Verify the prose matches the runner**

Run:

```bash
plugins/dr-superpowers/tests/codex-review.test.sh
grep -c 'gpt-5.6-sol' plugins/dr-superpowers/reference/external-executor.md
```

Expected: the suite ends `0 failed`, and the `grep` count is `2`. It was `3` before this task — the risk-3 command, the final-round command, and the sentence about the borrowed `codex-timeout` row. This task removes the first; Task 6 removes the other two.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/reference/external-executor.md
git commit -m "feat(superpowers): run the risk-3 seat through the runner"
```

---

### Task 6: The final-review round calls the runner

**Files:**
- Modify: `plugins/dr-superpowers/reference/external-executor.md` (§Final-review Codex round)
- Modify: `plugins/dr-superpowers/reference/final-review.md` (step 2)

**Interfaces:**
- Consumes: the runner interface and the four outcome names, named in Contracts.
- Produces: nothing later tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Pass a base branch, and leave the sha question open**

Whether `codex exec review --base` resolves a commit sha as well as a branch name is **unknown**, and no cheap probe settles it: `--help` exercises the argument parser, which accepts any string, while the ref is resolved at run time inside a real review. So this task does not claim an answer. It passes a **base branch name**, which is what the command passes today and is therefore already known to work, and the sha question stays in §12 of the spec as logged-not-fixed.

This matters because `reference/final-review.md:21` computes `MERGE_BASE` as a sha for the review package. The two are not the same value, and the prose below says which one this round takes.

No command to run. Record in the ledger: `Ruling: the final round passes a base branch, not the package's MERGE_BASE sha — no probe distinguishes them without a paid run — if wrong, the round reviews a slightly wider range than the package shows`.

- [ ] **Step 2: Replace the round's intro and command block**

In `plugins/dr-superpowers/reference/external-executor.md`, in §Final-review Codex round, first replace the intro sentence:

```markdown
The final whole-branch review adds this round when Codex is usable. Run it as a
background Bash call:
```

with:

```markdown
The final whole-branch review adds this round. The runner decides whether Codex
is usable:
```

Then replace this block:

````markdown
```bash
(cd <worktree-root> && timeout 1800 codex exec review --base <base-branch> \
  -m gpt-5.6-sol -c model_reasoning_effort=high \
  -o <workspace>/final-review-codex.md)
```
````

with:

````markdown
```bash
bash "<plugin-root>/scripts/run-codex-review.sh" --kind final \
  --cwd <worktree-root> --out <workspace>/final-review-codex.md \
  --base <base-branch>
```

`<base-branch>` is the branch this one forked from, not the review package's
`MERGE_BASE` sha: whether `--base` resolves a sha is unverified, and a branch
name is what this round has always passed. The runner owns the model, the
effort, the bound and the outcome, and prints one status line:

```
codex-judge <model>/<effort> status=OK|FALLBACK|TIMEOUT|FAILED exit=<n> out=<path> evidence=<fetched_at>
```

`OK` and `FALLBACK` are a round that produced findings; on `FALLBACK` say the
substitution aloud, because the round was judged by the fallback rung rather
than the preferred one. `TIMEOUT` and `FAILED` mean this round produced
nothing: skip it, say so, and report the Claude review alone, exactly as a
missing Codex has always been reported.
````

- [ ] **Step 3: Replace the paragraph that follows it**

In the same section, replace the paragraph beginning `` `codex exec review` is purpose-built for this `` through to `round, say so, and report the Claude review alone.` with:

```markdown
`codex exec review` is purpose-built for this and takes no sandbox flag, because
review is read-only by nature. Run the runner as a background Bash call: the
Bash tool's own `timeout` caps at ten minutes while a whole-branch round needs
more, and a background call is not bound by it at all. The bound is the
`codex-judge` row's third field, applied by the runner with coreutils `timeout`.

The runner establishes usability itself from the same `detect-executors.sh`
roster the risk-3 seat uses, so this round needs no separate guard; a Codex that
is not usable comes back as `status=FAILED` with the roster's own reason on
stderr.
```

- [ ] **Step 4: Update final-review.md step 2**

In `plugins/dr-superpowers/reference/final-review.md`, replace step 2:

```markdown
2. **Codex round.** When Codex is usable, run the round in
   [external-executor.md](external-executor.md) §Final-review Codex round. If it
   is not usable, or it times out, skip it and say so.
```

with:

```markdown
2. **Codex round.** Run the round in
   [external-executor.md](external-executor.md) §Final-review Codex round. Its
   runner reports one of four outcomes: `OK` and `FALLBACK` produce findings
   for step 3, and `FALLBACK` also means the preferred judge rung refused the
   run — say so. `TIMEOUT` and `FAILED` produce nothing: skip the round, say
   which, and go to step 3 with the Claude review alone. An absent or empty
   report is never a clean round.
```

- [ ] **Step 5: Run the affected suites**

Run:

```bash
plugins/dr-superpowers/tests/codex-review.test.sh
plugins/dr-superpowers/tests/inline-mode.test.sh
```

Expected: both end `0 failed`. `inline-mode.test.sh` asserts `A red gate stops` and `dr-superpowers:running-gates` in `final-review.md`; neither is in the text this task replaces.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/reference/external-executor.md plugins/dr-superpowers/reference/final-review.md
git commit -m "feat(superpowers): run the final round through the runner"
```

---

### Task 7: The risk-3 caller defers to the outcome policy

**Files:**
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` (the Risk 3 paragraph)

**Interfaces:**
- Consumes: the four outcome names from Task 4, named in Contracts.
- Produces: nothing later tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 1 = 2

Both design reviews found that this caller handles only unusability and timeout, and that its generic missing-verdict rule says to redispatch. Without this task, a `FAILED` seat can reopen a retry loop the runner already decided against.

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/codex-review.test.sh`, insert this block immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
# The caller must defer to the runner's outcome rather than running its own
# retry rule: a FAILED seat that redispatches turns one refused run into two.
SDD="$HERE/../skills/subagent-driven-development/SKILL.md"
sdd=$(cat "$SDD")
present "the risk-3 caller names the runner" "$sdd" "run-codex-review.sh"
present "the risk-3 caller defers on FAILED" "$sdd" "TIMEOUT or FAILED"
# Needle must be unique to the new text: SKILL.md's recovery table already
# carries a bare "never re-dispatch", so a shorter needle would pass untouched.
present "the risk-3 caller does not redispatch a decided seat" "$sdd" "never re-dispatch the Codex seat"
```

- [ ] **Step 2: Run it and verify it fails**

Run:

```bash
plugins/dr-superpowers/tests/codex-review.test.sh
```

Expected: FAIL — the three new checks report missing needles.

- [ ] **Step 3: Update the caller**

In `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, in the **Risk 3.** paragraph, replace:

```markdown
diff. One of the three seats is Codex when usable — see
[external-executor.md](../../reference/external-executor.md) §Risk-3 Codex
seat; otherwise, or when that seat times out, a third Claude judge. Never
average two scores as if three had voted.
```

with:

```markdown
diff. One of the three seats is Codex, run through
`scripts/run-codex-review.sh`, which decides for itself whether Codex is usable
and which judge rung to use — see
[external-executor.md](../../reference/external-executor.md) §Risk-3 Codex
seat. Never average two scores as if three had voted.
```

The `otherwise, or when that seat times out` clause goes with it: `otherwise` referred to the `when usable` condition this replacement removes, and the timeout case is now one half of the `TIMEOUT or FAILED` rule the next step appends.

Then, at the end of that paragraph, append:

```markdown
Read the runner's status line and take its word: `OK` and `FALLBACK` are a seat
that scored, and `TIMEOUT or FAILED` is a seat that did not — dispatch a third
Claude judge for it and never re-dispatch the Codex seat. The runner has
already applied its own one-shot fallback, so a second attempt here would turn
one refused run into two. A seat that produced no report is never averaged in
as if it had voted.
```

- [ ] **Step 4: Run the test and verify it passes**

Run:

```bash
plugins/dr-superpowers/tests/codex-review.test.sh
plugins/dr-superpowers/tests/inline-mode.test.sh
```

Expected: both end `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md plugins/dr-superpowers/tests/codex-review.test.sh
git commit -m "fix(superpowers): defer risk-3 retries to the runner"
```

---

### Task 8: README, manifests, and the program design amendment

**Files:**
- Modify: `plugins/dr-superpowers/README.md` (the cross-family review paragraph; a dated addendum to the model-policy paragraph; the Tests and Reference sections)
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json` (version)
- Modify: `plugins/dr-superpowers/.codex-plugin/plugin.json` (version)
- Modify: `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` (§6, append the amendment)

**Interfaces:**
- Consumes: every file created by Tasks 1 through 7.
- Produces: nothing.

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Bump both manifests to 1.8.0**

In `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json`, change the `"version"` value from `"1.7.0"` to `"1.8.0"`.

Run:

```bash
grep -h '"version"' plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json
```

Expected: two identical `"version": "1.8.0",` lines.

- [ ] **Step 2: Update the cross-family review paragraph**

In `plugins/dr-superpowers/README.md`, in the paragraph beginning `**Cross-family review.**`, replace:

```markdown
the final whole-branch review gains a `codex exec review` round whose findings
```

with:

```markdown
the final whole-branch review gains a Codex round whose findings
```

Then append to that same paragraph:

```markdown
Both review seats run through `scripts/run-codex-review.sh`, which judges at
`gpt-6-astra` — the rung the native Codex policy already floors judges at —
and falls back to `gpt-5.6-sol` whenever the local model catalog does not
advertise Astra. Selection, the run bound and the four outcomes live in that
script rather than in prose, so a refused model is a recorded substitution
instead of a silently missing seat.
```

- [ ] **Step 3: Date the historical model evidence**

In the same file, find the intro sentence ending `They are historical CLI policy evidence, not native Codex capability declarations:` — it wraps across lines, with `historical CLI policy` ending one and `evidence, not native` beginning the next, so search for `historical CLI policy` rather than the whole sentence. Append this as a new paragraph immediately **after the bullet list that follows it** — that is, after the last bullet of that list and before the next heading or paragraph. It is a note about the list as a whole, not about one bullet:

```markdown
That probe is a dated observation, not a standing fact: the same two models were
listed in the local catalog on 2026-09-14, and `gpt-6-astra` ran there on that
date. Catalog listing is not entitlement, which is why the judge seats fall back
at runtime rather than trusting either list.
```

- [ ] **Step 4: Name the new suite and the new script**

In the same file, under `## Tests`, append to the paragraph ending `structurally, against the documents themselves.`:

```markdown
`codex-review.test.sh` covers the judge seats' selection and outcome policy
against a stub `codex`, so every branch — refusal, fallback, timeout, empty
report — is exercised without a model call.
```

Under `## Reference`, the section is prose paragraphs, not a bullet list. Append this sentence to the paragraph that begins `` `reference/external-executor.md` holds the Claude-hosted Codex CLI lane `` — the one ending `the whole-branch review both execution skills end at.`:

```markdown
`scripts/run-codex-review.sh` runs one Codex review seat for both of them: it
selects the judge rung from `codex-judge`, bounds the run, and classifies the
outcome as `OK`, `FALLBACK`, `TIMEOUT` or `FAILED`.
```

- [ ] **Step 5: Amend the program design**

In `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`, at the end of §6 (after the 2026-09-14 sub-project 6 amendment), append:

```markdown
**Amendment 2026-09-14 (sub-project 7 spec).** The decomposition gains a seventh
sub-project, "Codex judge seats", after project state. Both Claude-hosted Codex
review seats — the risk-3 seat and the final-review round — move from
`gpt-5.6-sol / high` to `gpt-6-astra / high`, the rung `codex-routing.json`
already floors native judges at, with `gpt-5.6-sol / high` as a fallback declared
in a new `codex-judge` block in `reference/ladder.md`. Execution admission is
unchanged: the block is separate because `run-codex-task.sh` validates `--model`
against `codex-assignment`. `scripts/detect-executors.sh` gains an `advertised`
field of model/effort pairs read from the local Codex model cache, used strictly
as a negative filter — catalog listing is not entitlement — and selection falls
closed to the fallback row whenever the cache is absent, malformed or silent. A
new `scripts/run-codex-review.sh` owns selection, the run bound and the outcome
policy for both seats, so the rule is executable and testable rather than prose.
The official OpenAI `codex` plugin is deliberately not adopted as the substrate:
its review path accepts no caller schema and no caller prompt, drops the selected
reasoning effort, imposes no deadline, does not background, returns no job id to
cancel with, and leaves a detached broker daemon its own session hook owns.
Details: `docs/superpowers/specs/2026-09-14-dr-superpowers-judge-seats-design.md`.
```

- [ ] **Step 6: Run everything**

Run from the repository root, with a 600-second timeout:

```bash
node scripts/validate-repository.mjs && node scripts/test-all.mjs
```

Expected: the validator reports no errors. `test-all.mjs` may report one pre-existing environment failure in `tests/ui-discovery.test.mjs` (`bash: rg: command not found`) that predates this plan. Every other suite passes, including `codex-review.test.sh`.

- [ ] **Step 7: Validate the plugin manifests**

Run from the repository root, with a 300-second timeout:

```bash
claude plugin validate .claude-plugin/marketplace.json
claude plugin validate plugins/dr-superpowers
```

Expected: both report valid. If `claude` is unavailable, say so and record it; do not claim the check passed.

- [ ] **Step 8: Confirm the new files are executable in the index**

Run:

```bash
git ls-files -s plugins/dr-superpowers/scripts/run-codex-review.sh plugins/dr-superpowers/tests/codex-review.test.sh
```

Expected: both report mode `100755`. If either reports `100644`, run `git update-index --chmod=+x` on it and let Step 9's commit carry the mode change — do **not** amend, which would fold a Task 3 file into Task 7's unrelated commit.

- [ ] **Step 9: Commit**

```bash
git add plugins/dr-superpowers/README.md plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md
git commit -m "chore(superpowers): bump to 1.8.0"
```
