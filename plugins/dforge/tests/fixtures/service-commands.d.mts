// Types for service-commands.mjs, so cockpit.test.ts's import type-checks.
declare const cases: readonly { command: string; role: 'service' | 'timer' | 'work' }[]
export default cases
