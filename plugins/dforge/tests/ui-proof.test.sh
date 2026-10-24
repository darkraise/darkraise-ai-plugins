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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
