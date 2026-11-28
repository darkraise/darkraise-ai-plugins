// Acceptance test for docs/dforge/specs/2026-11-27-review-3c81c7d6-fixes-design.md,
// statement A9's darkmem half: a reconcile run after a documents move that was
// killed after `git rm` completes without refusing on uncommitted changes. The
// move is run through the real command; the kill is a git stand-in that lets the
// move's `git rm` run, then kills the command at its next git call.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { startStub } from "./stub-server.mjs";
import { git, makeHome, makeRepo, read, run, scratch, write } from "./helpers.mjs";

const SKIP = process.platform === "win32" && "a POSIX git shim";

async function documentsRepo(t) {
  const stub = await startStub({});
  t.after(() => stub.close());
  const repo = makeRepo();
  write(path.join(repo, "docs", "dforge", "specs", "a.md"), "# A\n");
  write(path.join(repo, "docs", "dforge", "plans", "p.md"), "# P\n");
  git(repo, "add", "-A");
  git(repo, "commit", "-q", "-m", "docs");
  const config = { darkmemEnabled: true, darkmem: { url: stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [repo]: { project: "proj", progressSource: "local" } } } };
  const home = makeHome({ repo, url: stub.url, stores: { documents: "local", progress: "local" }, config });
  const stores = () => JSON.parse(read(path.join(home.home, ".dforge", "stores.json")))[repo];
  return { stub, repo, home, stores };
}

function gitStandIn(body) {
  const realGit = process.env.PATH.split(path.delimiter).map(dir => path.join(dir, "git")).find(file => fs.existsSync(file));
  const bin = scratch("a9-git-");
  const flag = path.join(bin, "rm-ran");
  fs.writeFileSync(path.join(bin, "git"), `#!/bin/sh\n${body(realGit, flag)}\nexec "${realGit}" "$@"\n`, { mode: 0o755 });
  return { bin, flag };
}

test("A9: a reconcile after a documents move killed after git rm completes without refusing on uncommitted changes", { skip: SKIP }, async t => {
  const s = await documentsRepo(t);
  // After the move's `git rm` has run, the next git call kills the command.
  const { bin, flag } = gitStandIn((realGit, flagFile) => [
    `[ -e "${flagFile}" ] && { kill -KILL $PPID; exit 137; }`,
    `for a in "$@"; do if [ "$a" = "rm" ]; then "${realGit}" "$@"; rc=$?; : > "${flagFile}"; exit $rc; fi; done`,
  ].join("\n"));
  const env = { ...s.home.env, PATH: `${bin}${path.delimiter}${s.home.env.PATH ?? process.env.PATH}` };

  const killed = await run(["reconcile"], { cwd: s.repo, env });
  assert.ok(fs.existsSync(flag), `the move never reached git rm\n${killed.stdout}${killed.stderr}`);
  assert.notEqual(killed.code, 0, `the command was not killed: ${killed.stdout}${killed.stderr}`);
  // The kill left the deletion staged, which is the state a rerun must accept.
  assert.equal(git(s.repo, "diff", "--cached", "--name-only").split("\n").sort().join(","), "docs/dforge/plans/p.md,docs/dforge/specs/a.md");

  const again = await run(["reconcile"], { cwd: s.repo, env: s.home.env });
  assert.equal(again.code, 0, again.stdout + again.stderr);
  assert.doesNotMatch(again.stdout + again.stderr, /uncommitted changes/);
  assert.equal(s.stores().documents, "darkmem");
});
