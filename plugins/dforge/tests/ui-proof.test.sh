#!/usr/bin/env bash
# ui-proof is the ui-ux skill's gate: which files are UI files, their
# fingerprint, a spec's contract, and the check that blocks finishing until a
# proof report covers the current UI. Every case runs in a throwaway repository.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UP="$HERE/../scripts/ui-proof"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q "$REPO"
cd "$REPO" || exit 1
git config user.email t@example.com && git config user.name t
mkdir -p src
printf 'export const App = () => null;\n' > src/App.tsx
printf '# readme\n' > README.md
git add . && git commit -q -m base
BASE=$(git rev-parse HEAD)
up() { bash "$UP" "$@"; }

# --- paths ---
check "paths: the defaults hold the web globs" "$(up paths | grep -cxF '*.tsx')" "1"
check "paths: the defaults hold the windows globs" "$(up paths | grep -cxF '*.xaml')" "1"
check "paths: no bare *.ts" "$(up paths | grep -cxF '*.ts')" "0"
mkdir -p docs/dforge/ui-ux
printf '# UI profile\n\n**Platform:** web\n**UI paths:** `src/ui/*` `*.tsx`\n' > docs/dforge/ui-ux/profile.md
check "paths: the profile's globs replace the defaults" "$(up paths | tr '\n' ' ')" "src/ui/* *.tsx "
rm docs/dforge/ui-ux/profile.md

# --- filter: one awk pass that must agree with uiux_is_ui ---
SAMPLE="$TMP/sample"
printf '%s\n' a.tsx src/x.test.tsx src/x.spec.vue b.stories.tsx c.acceptance.html res/layout/main.xml \
  app/src/main/res/values/s.xml layout/a.xml F.Designer.cs F.cs 'a+b.css' 'p(1).html' 'w [x].scss' x.tsx.bak \
  'name with space.vue' 'caf.é.css' 'dot.in.dir/x.qml' src/ui/k ab.c bx/q.c zy.go yy.go app/a.ts app/ab.ts \
  'odd$.less' 'q^.sass' 'h|i.html' > "$SAMPLE"
agree() { # agree <label>: uiux_filter and uiux_is_ui pick the same lines of $SAMPLE
  ( . "$HERE/../scripts/lib/ui-ux.sh"
    globs=$(uiux_globs "$REPO")
    want=$(while IFS= read -r p; do if uiux_is_ui "$p" "$globs"; then printf '%s\n' "$p"; fi; done < "$SAMPLE")
    got=$(uiux_filter "$REPO" < "$SAMPLE")
    check "filter: $1" "$got" "$want"
    check "filter: $1 selects some" "$([ -n "$got" ] && echo yes || echo no)" "yes"
    printf '%s %s\n' "$pass" "$fail" > "$TMP/counts" )
  read -r pass fail < "$TMP/counts"
}
agree "the default globs match as uiux_is_ui does"
printf '# UI profile\n\n**UI paths:** `src/ui/*` `app/?.ts` `[ab]x/*.c` `[!z]y.go` `*\\(1\\).html` `w [[]x].scss`\n' > docs/dforge/ui-ux/profile.md
agree "?, [..], [!..] and escapes match as uiux_is_ui does"
rm docs/dforge/ui-ux/profile.md
big=$(awk 'BEGIN { for (i = 0; i < 50000; i++) printf "src/m%d/f%d.%s\n", i % 500, i, (i % 10 ? "ts" : "tsx") }')
start=$SECONDS
n=$( (. "$HERE/../scripts/lib/ui-ux.sh"; uiux_filter "$REPO" <<<"$big") | grep -c .)
check "filter: 50000 paths in under 10 s" "$n $(( SECONDS - start < 10 ))" "5000 1"

# --- fingerprint ---
fp1=$(up fingerprint)
check "fingerprint: 16 hex digits" "$(grep -cE '^[0-9a-f]{16}$' <<<"$fp1")" "1"
check "fingerprint: stable" "$(up fingerprint)" "$fp1"
printf 'readme 2\n' >> README.md
check "fingerprint: a non-UI edit leaves it" "$(up fingerprint)" "$fp1"
git checkout -q README.md
printf '// edit\n' >> src/App.tsx
check "fingerprint: an uncommitted UI edit changes it" "$([ "$(up fingerprint)" != "$fp1" ] && echo yes || echo no)" "yes"
git checkout -q src/App.tsx
printf 'a {}\n' > src/new.css
check "fingerprint: an untracked UI file changes it" "$([ "$(up fingerprint)" != "$fp1" ] && echo yes || echo no)" "yes"
rm src/new.css
printf 'x\n' > src/a.test.tsx
check "fingerprint: a test file is not a UI file" "$(up fingerprint)" "$fp1"
rm src/a.test.tsx
printf 'a {}\n' > "src/caf$(printf '\303\251').css"
check "fingerprint: a non-ASCII file name counts" "$([ "$(up fingerprint)" != "$fp1" ] && echo yes || echo no)" "yes"
check "changed: a non-ASCII file name is listed" "$(up changed --base HEAD | grep -c "caf$(printf '\303\251').css")" "1"
rm src/caf*.css
mkdir -p "$TMP/empty" && (cd "$TMP/empty" && git init -q && bash "$UP" fingerprint) > "$TMP/fp-empty"
check "fingerprint: none without UI files" "$(cat "$TMP/fp-empty")" "none"

# --- changed ---
printf '// v2\n' >> src/App.tsx
printf 'b {}\n' > src/b.css
check "changed: uncommitted and untracked UI files" "$(up changed --base HEAD | tr '\n' ' ')" "src/App.tsx src/b.css "
rm src/b.css; git checkout -q src/App.tsx
up changed >/dev/null 2>&1; check "changed: --base is required" "$?" "2"

# --- contract ---
mkdir -p docs/dforge/specs
cat > docs/dforge/specs/s.md <<'EOF'
# Spec

## UI/UX contract

**UI/UX depth:** feature — a settings screen

### UI

- **UI-1** — Settings layout.
  Board: default, error.
- **UI-2** — Tokens only.

### UX

- **UX-1** — Escape closes the dialog.

```markdown
- **UX-9** — an example, not an item
```

### Output promise

| ID | Promise |
|---|---|
| OP-1 | Matches the boards. |

## Acceptance

- **UX-7** — outside the section
EOF
check "contract: the ids in order, fences and other sections skipped" "$(up contract docs/dforge/specs/s.md | tr '\n' ' ')" "UI-1 UI-2 UX-1 OP-1 "
check "contract: a bullet item with its continuation" "$(up contract docs/dforge/specs/s.md UI-1)" $'- **UI-1** — Settings layout.\n  Board: default, error.'
check "contract: a table item under its header" "$(up contract docs/dforge/specs/s.md OP-1)" $'| ID | Promise |\n|---|---|\n| OP-1 | Matches the boards. |'
check "contract: an unknown id prints nothing" "$(up contract docs/dforge/specs/s.md UX-5)" ""
up contract docs/dforge/specs/missing.md >/dev/null 2>&1; check "contract: a missing spec exits 2" "$?" "2"
up nope >/dev/null 2>&1; check "usage: an unknown verb exits 2" "$?" "2"

# --- check: the gate ---
up check >/dev/null 2>&1; check "check: --base is required" "$?" "2"
out=$(up check --base HEAD); st=$?
check "check: gate off without a profile or a contract" "$st" "0"
check "check: says the gate is off" "$(grep -c 'gate off' <<<"$out")" "1"
printf '# UI profile\n\n**Platform:** web\n' > docs/dforge/ui-ux/profile.md
git add docs && git commit -q -m docs
check "check: no UI change since the base passes" "$(up check --base "$BASE" >/dev/null; echo $?)" "0"
printf '// v2\n' >> src/App.tsx
out=$(up check --base HEAD); st=$?
check "check: an uncommitted UI change with no report fails" "$st" "1"
check "check: names the missing report" "$(grep -c '^ui-proof: FAIL report:' <<<"$out")" "1"
check "check: names the changed file" "$(grep -c 'src/App.tsx' <<<"$out")" "1"
git commit -q -am 'ui v2'
check "check: a committed UI change with no report fails" "$(up check --base "$BASE" >/dev/null; echo $?)" "1"

PROOFS=docs/dforge/ui-ux/proofs
mkdir -p "$PROOFS" .dforge/ui-ux/t
printf '*\n' > .dforge/.gitignore
printf 'png' > .dforge/ui-ux/t/a.png
report() { # report <name> <contract> <rows> [extra header line]
  { printf '# UI proof: t\n\n**Contract:** %s\n**Platform:** web\n**Evidence:** local\n%s\n' "$2" "${4:-}"
    if [ "$2" = touch ]; then printf '\n## Delta\n\n**UI/UX depth:** touch — a fix\n\n- **UX-1** — the fix\n'; fi
    printf '\n## Results\n\n| ID | Verdict | Evidence | Note |\n|---|---|---|---|\n%s\n' "$3"
  } > "$PROOFS/$1.md"
}
judge() { # judge <name> <verdict> — the judge file and the report's Judge line
  local fp; fp=$(up fingerprint)
  printf 'The proof holds.\n\nVerdict: %s %s\n' "$2" "$fp" > "$PROOFS/$1.judge.md"
  printf '\n**Judge:** %s %s — %s/%s.judge.md\n' "$2" "$fp" "$PROOFS" "$1" >> "$PROOFS/$1.md"
}
PASSROW='| UX-1 | pass | .dforge/ui-ux/t/a.png | |'
report 2026-10-24-t touch "$PASSROW"
out=$(up stamp "$PROOFS/2026-10-24-t.md")
check "stamp: reports the fingerprint" "$(grep -c "^ui-proof: stamped $(up fingerprint)" <<<"$out")" "1"
check "stamp: writes one fingerprint line under Contract" "$(grep -A1 '^\*\*Contract:\*\*' "$PROOFS/2026-10-24-t.md" | grep -c '^\*\*Fingerprint:\*\*')" "1"
judge 2026-10-24-t ship
out=$(up check --base "$BASE"); st=$?
check "check: a stamped, judged touch report passes" "$st" "0"
check "check: says ok" "$(grep -c '^ui-proof: ok' <<<"$out")" "1"
up stamp "$PROOFS/2026-10-24-t.md" >/dev/null
check "stamp: keeps a judge line for the current fingerprint" "$(grep -c '^\*\*Judge:\*\*' "$PROOFS/2026-10-24-t.md")" "1"
check "stamp: never duplicates the fingerprint line" "$(grep -c '^\*\*Fingerprint:\*\*' "$PROOFS/2026-10-24-t.md")" "1"

printf '// v3\n' >> src/App.tsx
out=$(up check --base "$BASE"); st=$?
check "check: a UI edit after the stamp fails" "$st" "1"
check "check: names the stale report" "$(grep -c '^ui-proof: FAIL freshness:' <<<"$out")" "1"
up stamp "$PROOFS/2026-10-24-t.md" >/dev/null
check "stamp: a judge line for another fingerprint is removed" "$(grep -c '^\*\*Judge:\*\*' "$PROOFS/2026-10-24-t.md")" "0"
out=$(up check --base "$BASE"); st=$?
check "check: no judge line fails" "$st" "1"
check "check: names the judge step" "$(grep -c '^ui-proof: FAIL judge:' <<<"$out")" "1"
judge 2026-10-24-t ship
check "check: judged again, it passes" "$(up check --base "$BASE" >/dev/null; echo $?)" "0"
report 2026-10-24-u touch '| UX-1 | fail | .dforge/ui-ux/t/a.png | abandoned |'
up stamp "$PROOFS/2026-10-24-u.md" >/dev/null
out=$(up check --base "$BASE"); st=$?
check "check: a failing report sorting last does not hide a passing one" "$st" "0"
check "check: names the report that passes" "$(grep -c '^ui-proof: ok — .*2026-10-24-t.md' <<<"$out")" "1"
mv "$PROOFS/2026-10-24-t.md" "$TMP/t.md"
out=$(up check --base "$BASE"); st=$?
check "check: with no passing report at the fingerprint it fails" "$st" "1"
check "check: names the last report it checked" "$(grep -c '^ui-proof: report .*2026-10-24-u.md' <<<"$out")" "1"
mv "$TMP/t.md" "$PROOFS/2026-10-24-t.md"
rm "$PROOFS/2026-10-24-u.md"

try() { # try <rows> [extra header line] [judge verdict] — a fresh touch report; prints check's status
  rm -f "$PROOFS"/2026-10-24-t.*
  report 2026-10-24-t touch "$1" "${2:-}"
  up stamp "$PROOFS/2026-10-24-t.md" >/dev/null
  judge 2026-10-24-t "${3:-ship}"
  up check --base "$BASE" >/dev/null; echo "$?"
}
check "verdicts: a fail row fails" "$(try '| UX-1 | fail | .dforge/ui-ux/t/a.png | the dialog stays open |')" "1"
check "verdicts: an uncited deviation fails" "$(try '| UX-1 | deviation | .dforge/ui-ux/t/a.png | looks better |')" "1"
check "verdicts: a cited deviation passes" "$(try '| UX-1 | deviation | .dforge/ui-ux/t/a.png | cites: user answer 2026-10-24 |')" "0"
check "verdicts: a pass row without evidence fails" "$(try '| UX-1 | pass | - | |')" "1"
check "verdicts: a missing screenshot fails" "$(try '| UX-1 | pass | .dforge/ui-ux/t/missing.png | |')" "1"
check "verdicts: a test name is evidence" "$(try '| UX-1 | pass | A12: escape closes the dialog | |')" "0"
check "verdicts: unverifiable without acceptance fails" "$(try '| UX-1 | unverifiable | - | no emulator here |')" "1"
check "verdicts: unverifiable with the user's acceptance passes" "$(try '| UX-1 | unverifiable | - | no emulator here |' '**Accepted by:** "ship it without the Android run"')" "0"
check "verdicts: an unknown verdict fails" "$(try '| UX-1 | ok | .dforge/ui-ux/t/a.png | |')" "1"
check "coverage: a delta item with no row fails" "$(try '| UX-2 | pass | .dforge/ui-ux/t/a.png | |')" "1"
check "judge: a fix verdict fails" "$(try "$PASSROW" '' fix)" "1"
try "$PASSROW" >/dev/null
rm "$PROOFS/2026-10-24-t.judge.md"
check "judge: a missing judge file fails" "$(up check --base "$BASE" >/dev/null; echo $?)" "1"
try "$PASSROW" >/dev/null
printf 'Verdict: fix %s\n' "$(up fingerprint)" > "$PROOFS/2026-10-24-t.judge.md"
check "judge: a judge file whose verdict differs fails" "$(up check --base "$BASE" >/dev/null; echo $?)" "1"

# --- a spec with a contract binds the report ---
try "$PASSROW" >/dev/null
out=$(up check --base "$BASE" --spec docs/dforge/specs/s.md); st=$?
check "spec: a touch report does not prove a spec with a contract" "$st" "1"
check "spec: says no report names the spec" "$(grep -c '^ui-proof: FAIL report:' <<<"$out")" "1"
rm -f "$PROOFS"/2026-10-24-t.*
cp docs/dforge/specs/s.md docs/dforge/specs/other.md
ROWS='| UI-1 | pass | .dforge/ui-ux/t/a.png | |
| UI-2 | pass | .dforge/ui-ux/t/a.png | |
| UX-1 | pass | .dforge/ui-ux/t/a.png | |
| OP-1 | pass | .dforge/ui-ux/t/a.png | |'
report 2026-10-24-o docs/dforge/specs/other.md "$ROWS"; up stamp "$PROOFS/2026-10-24-o.md" >/dev/null; judge 2026-10-24-o ship
check "spec: a report bound to another spec does not count" "$(up check --base "$BASE" --spec docs/dforge/specs/s.md >/dev/null; echo $?)" "1"
rm -f "$PROOFS"/2026-10-24-o.*
report 2026-10-24-s docs/dforge/specs/s.md "$(head -n 3 <<<"$ROWS")"; up stamp "$PROOFS/2026-10-24-s.md" >/dev/null; judge 2026-10-24-s ship
out=$(up check --base "$BASE" --spec docs/dforge/specs/s.md); st=$?
check "spec: a contract ID with no row fails" "$st" "1"
check "spec: names the missing ID" "$(grep -c 'FAIL coverage: OP-1' <<<"$out")" "1"
check "spec: coverage applies without --spec too" "$(up check --base "$BASE" >/dev/null; echo $?)" "1"
report 2026-10-24-s docs/dforge/specs/s.md "$ROWS"; up stamp "$PROOFS/2026-10-24-s.md" >/dev/null; judge 2026-10-24-s ship
check "spec: a full report bound to the spec passes" "$(up check --base "$BASE" --spec docs/dforge/specs/s.md >/dev/null; echo $?)" "0"
TWO='| UI-1 | pass | .dforge/ui-ux/t/a.png | |
| UI-2 | pass | .dforge/ui-ux/t/a.png | |
| UX-1 | unverifiable | - | no emulator here |
| OP-1 | unverifiable | - | no tablet here |'
accept() { # accept <header lines> — the two-unverifiable report, stamped and judged; prints check's status
  report 2026-10-24-s docs/dforge/specs/s.md "$TWO" "$1"; up stamp "$PROOFS/2026-10-24-s.md" >/dev/null; judge 2026-10-24-s ship
  up check --base "$BASE" --spec docs/dforge/specs/s.md >/dev/null; echo $?
}
check "accepted: one nameless line does not cover two unverifiable rows" "$(accept '**Accepted by:** "fine without the emulator"')" "1"
check "accepted: a line naming only one of two rows fails" "$(accept '**Accepted by:** UX-1: "fine without the emulator"')" "1"
check "accepted: a line per row passes" "$(accept '**Accepted by:** UX-1: "fine without the emulator"
**Accepted by:** OP-1: "fine without the tablet"')" "0"
report 2026-10-24-s docs/dforge/specs/s.md "$ROWS"; up stamp "$PROOFS/2026-10-24-s.md" >/dev/null
printf 'The proof holds.\n\nVerdict: ship 0000000000000000\n' > "$PROOFS/2026-10-24-s.judge.md"
printf '\n**Judge:** ship %s — %s/2026-10-24-s.judge.md\n' "$(up fingerprint)" "$PROOFS" >> "$PROOFS/2026-10-24-s.md"
out=$(up check --base "$BASE" --spec docs/dforge/specs/s.md); st=$?
check "judge: a judge file for another fingerprint fails" "$st" "1"
check "judge: names the judge file's missing verdict" "$(grep -c 'FAIL judge:.*does not end with' <<<"$out")" "1"
report 2026-10-24-s docs/dforge/specs/s.md "$ROWS"; up stamp "$PROOFS/2026-10-24-s.md" >/dev/null; judge 2026-10-24-s ship
rm docs/dforge/ui-ux/profile.md
check "active: a spec with a contract turns the gate on" "$(up check --base "$BASE" --spec docs/dforge/specs/s.md >/dev/null; echo $?)" "0"
rm -f "$PROOFS"/*.md
check "active: a spec with a contract and no report fails" "$(up check --base "$BASE" --spec docs/dforge/specs/s.md >/dev/null; echo $?)" "1"
check "active: --active turns the gate on without a profile" "$(up check --base "$BASE" --active >/dev/null; echo $?)" "1"
check "active: without it, no profile and no spec, the gate is off" "$(up check --base "$BASE" >/dev/null; echo $?)" "0"

# --- file listing edge cases ---
printf 'export const Other = () => null;\n' > src/Other.tsx
rm src/App.tsx
check "deleted: the fingerprint is still 16 hex digits" "$(up fingerprint | grep -cE '^[0-9a-f]{16}$')" "1"
check "deleted: the changed list names the deleted file" "$(up changed --base "$BASE" | grep -cx 'src/App.tsx')" "1"
check "deleted: a deletion with no report fails" "$(up check --base "$BASE" --active >/dev/null; echo $?)" "1"
git checkout -q -- src/App.tsx
rm src/Other.tsx
printf 'x\n' > src/Page.acceptance.tsx
check "acceptance: a *.acceptance.* file is not a UI file" "$(up changed --base "$BASE" | grep -c 'acceptance')" "0"
rm src/Page.acceptance.tsx
printf 'a {}\n' > 'src/we"ird.css'
check "quoting: a file name with a double quote is a changed UI file" "$(up changed --base "$BASE" | grep -cF 'src/we"ird.css')" "1"
rm 'src/we"ird.css'
printf 'a {}\n' > '"q.css'
check "quoting: a top-level file name starting with a double quote fingerprints" "$(up fingerprint >/dev/null 2>&1; echo $?)" "0"
rm '"q.css'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
