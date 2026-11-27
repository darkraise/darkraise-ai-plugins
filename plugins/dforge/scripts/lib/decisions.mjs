// One request to OpenAI's Decisions API for scripts/decide.
// stdin: {"question", "options": [text…], "evidence": [{"label", "path"}…],
//         "floor": <0..1>, "timeout": <seconds>, "limit": <evidence bytes>}
// The key comes from DFORGE_OPENAI_API_KEY and is never printed.
// stdout: one JSON object, the outcome and the answer fields of a decisions
// log line plus input_tokens.
import { closeSync, constants, fstatSync, lstatSync, openSync, readFileSync } from 'node:fs'

const QUESTIONS = ['ruling', 'ruling_reversed', 'needs_more', 'guarded']
const NEEDS_MORE_LIMIT = 0.15
const GUARDED_LIMIT = 0.10
const EVIDENCE_LIMIT = 400000

const blank = {
  outcome: 'error', choice: null, choice_reversed: null, confidence: null,
  confidence_reversed: null, needs_more: null, guarded: null, input_tokens: null,
}

function finish(result) {
  process.stdout.write(`${JSON.stringify(result)}\n`)
  process.exit(0)
}

// An evidence file's text. decide checked the path it sends; a link, or
// anything but a regular file, put there since is refused, as is a total over
// the limit.
function evidenceText(path, left) {
  if (!lstatSync(path).isFile()) throw new Error('evidence is not a regular file')
  const fd = openSync(path, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0))
  try {
    const stat = fstatSync(fd)
    if (!stat.isFile()) throw new Error('evidence is not a regular file')
    if (stat.size > left) throw new Error('evidence over the limit')
    return readFileSync(fd, 'utf8')
  } finally {
    closeSync(fd)
  }
}

function buildRequest(req) {
  const listed = req.options.map((text, i) => ({ value: `option_${i + 1}`, description: text }))
  const other = { value: 'other', description: 'None of the listed options fits.' }
  const lines = [req.question, '', 'Options:', ...req.options.map((text, i) => `${i + 1}. ${text}`)]
  let left = Number.isFinite(req.limit) ? req.limit : EVIDENCE_LIMIT
  for (const file of req.evidence) {
    const text = evidenceText(file.path, left)
    left -= Buffer.byteLength(text)
    lines.push('', `--- ${file.label} ---`, text)
  }
  const ask = 'Choose the option that best answers the question in the input.'
  return {
    model: 'gpt-6-luna',
    input: lines.join('\n'),
    questions: [
      { type: 'choice', name: 'ruling', instructions: ask, choices: [...listed, other] },
      { type: 'choice', name: 'ruling_reversed', instructions: ask, choices: [...listed.slice().reverse(), other] },
      { type: 'predicate', name: 'needs_more', instructions: 'Choosing correctly needs information that is not in the input, such as reading source files or running code.' },
      { type: 'predicate', name: 'guarded', instructions: 'One of the options involves an irreversible or destructive operation, a security-sensitive action, or a change outside the working directory.' },
    ],
  }
}

function judge(body, req) {
  const tokens = typeof body?.usage?.input_tokens === 'number' ? body.usage.input_tokens : null
  const answers = Array.isArray(body?.answers) ? body.answers : []
  const by = Object.fromEntries(QUESTIONS.map(name => [name, answers.find(a => a?.name === name)]))
  if (QUESTIONS.some(name => !by[name])) return { ...blank, input_tokens: tokens }
  const text = new Map(req.options.map((t, i) => [`option_${i + 1}`, t]))
  text.set('other', 'other')
  const refused = a => a.type === 'refusal'
  for (const name of ['ruling', 'ruling_reversed']) {
    const a = by[name]
    if (!refused(a) && !text.has(a.choice)) return { ...blank, input_tokens: tokens }
  }
  const field = (a, key) => (refused(a) || a[key] === undefined ? null : a[key])
  const result = {
    outcome: 'ruled',
    choice: refused(by.ruling) ? null : text.get(by.ruling.choice),
    choice_reversed: refused(by.ruling_reversed) ? null : text.get(by.ruling_reversed.choice),
    confidence: field(by.ruling, 'confidence'),
    confidence_reversed: field(by.ruling_reversed, 'confidence'),
    needs_more: field(by.needs_more, 'probability'),
    guarded: field(by.guarded, 'probability'),
    input_tokens: tokens,
  }
  if (QUESTIONS.some(name => refused(by[name]))) return { ...result, outcome: 'refusal' }
  const num = v => (typeof v === 'number' ? v : NaN)
  let outcome = 'ruled'
  if (result.choice === 'other' || result.choice_reversed === 'other') outcome = 'needs-more'
  else if (result.choice !== result.choice_reversed) outcome = 'disagree'
  else if (!(num(result.confidence) >= req.floor) || !(num(result.confidence_reversed) >= req.floor)) outcome = 'low-confidence'
  else if (!(num(result.needs_more) <= NEEDS_MORE_LIMIT)) outcome = 'needs-more'
  else if (!(num(result.guarded) <= GUARDED_LIMIT)) outcome = 'guarded'
  return { ...result, outcome }
}

let req
try {
  req = JSON.parse(readFileSync(0, 'utf8'))
} catch {
  finish(blank)
}

let payload
try {
  payload = JSON.stringify(buildRequest(req))
} catch {
  finish(blank)
}

const url = process.env.DFORGE_DECISIONS_URL || 'https://api.openai.com/v1/decisions'
try {
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${process.env.DFORGE_OPENAI_API_KEY ?? ''}`,
      'content-type': 'application/json',
    },
    body: payload,
    signal: AbortSignal.timeout(Math.max(1, Number(req.timeout) || 30) * 1000),
  })
  const text = await res.text()
  let body = null
  try { body = JSON.parse(text) } catch { body = null }
  if (res.status !== 200) {
    const tokens = typeof body?.usage?.input_tokens === 'number' ? body.usage.input_tokens : null
    finish({ ...blank, input_tokens: tokens })
  }
  // A 200 answer, or a request that timed out once sent, may be billed: with
  // no usage reported, decide charges an estimate for these two only.
  finish({ ...judge(body, req), estimate: true })
} catch (err) {
  finish({ ...blank, estimate: err?.name === 'TimeoutError' })
}
