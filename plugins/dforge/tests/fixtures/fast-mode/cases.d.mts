// Types for cases.mjs, so cockpit.test.ts's import type-checks.
declare const cases: readonly { name: string; before: readonly string[]; after: readonly string[] | null; on: boolean }[]
export default cases
