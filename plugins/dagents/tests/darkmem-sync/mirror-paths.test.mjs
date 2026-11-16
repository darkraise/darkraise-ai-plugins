import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { pathToUri, propertiesFor } from "../../scripts/lib/darkmem-mirror.mjs";
import { scratch, write } from "./helpers.mjs";

test("document references containing dotfiles have no URI or workstream link", () => {
  const root = scratch("dms-paths-");
  const roots = { docsRoot: path.join(root, "dagents"), workRoot: path.join(root, "work") };
  for (const name of ["plans/.hidden.md", "plans/.draft/p.md", "specs/.hidden.md"]) {
    for (const file of [`docs/dagents/${name}`, path.join(roots.docsRoot, name)]) {
      assert.equal(pathToUri(roots, file), null, file);
      assert.deepEqual(propertiesFor(roots, "p1", file), {}, file);
    }
  }
  write(path.join(roots.docsRoot, "plans", "p1.md"), "**Spec:** docs/dagents/specs/.hidden.md\n");
  assert.deepEqual(propertiesFor(roots, "p1", "docs/dagents/plans/p1.md"), { plan_uri: "dagents/plans/p1.md" });
});
