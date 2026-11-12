export const meta = {
  name: 'deep-review',
  description: 'Tier 2 dflow review: two reviewers with different lenses record findings, then one verifier tries to refute each',
  whenToUse: 'When `dflow review pack` reports tier 2 (a risk is set on the plan, or the diff is very large)',
  phases: [
    { title: 'Review', detail: 'correctness and plan conformance, and the plan\'s risk, in parallel', model: 'opus' },
    { title: 'Verify', detail: 'one skeptic tries to refute every recorded finding', model: 'sonnet' },
  ],
}

const input = typeof args === 'string' ? { pack: args } : (args || {})
if (!input.pack) throw new Error('deep-review needs args: { pack: "<path printed by dflow review pack>" }')

const SUMMARY = {
  type: 'object',
  properties: {
    recorded: { type: 'array', items: { type: 'string' }, description: 'ids of the findings recorded, such as F1' },
    notChecked: { type: 'string', description: 'what this pass did not look at, or an empty string' },
  },
  required: ['recorded', 'notChecked'],
}

const VERDICTS = {
  type: 'object',
  properties: {
    confirmed: { type: 'array', items: { type: 'string' } },
    refuted: { type: 'array', items: { type: 'string' } },
  },
  required: ['confirmed', 'refuted'],
}

const LENSES = [
  {
    key: 'correctness',
    focus: 'Correctness and plan conformance: logic errors, unhandled inputs and states, broken callers, and every Acceptance line and Design decision of the pack checked against the diff. Name anything the plan asked for that the diff does not do, and anything the diff does that the plan put out of scope.',
  },
  {
    key: 'risk',
    focus: 'The risk the plan names (security, data loss, migration or concurrency) and, where none is named, the failure modes of a large change: partial failure, ordering, rollback, input an attacker or an old client could send, data written in a form the next version cannot read.',
  },
]

phase('Review')
const results = await parallel(LENSES.map(lens => () => agent(
  `Review the change described in the pack at ${input.pack}. Your lens: ${lens.focus}\n\nRecord every finding with \`dflow review add ... --lens ${lens.key}\`. Return the ids you recorded and what you did not check.`,
  { label: `review:${lens.key}`, phase: 'Review', agentType: 'dflow:reviewer', model: 'opus', effort: 'high', schema: SUMMARY },
)))

// A reviewer that failed or was skipped comes back as null. Its lens was not
// reviewed, and the caller must not record the review as complete.
const missingLenses = LENSES.filter((lens, index) => !results[index]).map(lens => lens.key)
const reviews = results.filter(Boolean)
if (missingLenses.length) log(`Not reviewed: the ${missingLenses.join(' and ')} lens did not run. Do not record this review as tier 2.`)

const recorded = reviews.flatMap(review => review.recorded)
if (!recorded.length) {
  log(missingLenses.length ? 'No findings were recorded by the reviewers that ran.' : 'No findings were recorded; nothing to verify.')
  return { complete: missingLenses.length === 0, missingLenses, recorded: [], confirmed: [], refuted: [], notChecked: reviews.map(review => review.notChecked).filter(Boolean) }
}

phase('Verify')
const verdicts = await agent(
  `Findings ${recorded.join(', ')} were recorded against the change in the pack at ${input.pack}. Read them with \`dflow review list\`. For each one, try to refute it: read the cited code and its callers, and run its evidence command if it has one. Two findings that state the same defect count once: refute the later one as a duplicate. Record each verdict with \`dflow review judge <id> confirmed\` or \`dflow review judge <id> refuted "<why it is not a defect>"\`. Refute only what you can show is wrong; when you cannot tell, confirm. Do not record new findings.`,
  { label: 'verify', phase: 'Verify', agentType: 'dflow:reviewer', model: 'sonnet', effort: 'high', schema: VERDICTS },
)

if (!verdicts) log('Not verified: the verifier did not run. The findings stand as recorded.')

return {
  complete: missingLenses.length === 0 && Boolean(verdicts),
  missingLenses,
  recorded,
  confirmed: verdicts ? verdicts.confirmed : [],
  refuted: verdicts ? verdicts.refuted : [],
  notChecked: reviews.map(review => review.notChecked).filter(Boolean),
}
