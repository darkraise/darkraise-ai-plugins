#!/usr/bin/env node
// Stand-in for POST /v1/decisions. argv: <port file> <reply file> <request log>.
// The reply file is read on every request: {"status": 200, "delayMs": 0, "body": {…}}.
// Each request is logged as one JSON line; the key is compared, never written.
import { createServer } from 'node:http'
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs'

const [portFile, replyFile, logFile] = process.argv.slice(2)
const server = createServer((req, res) => {
  let text = ''
  req.on('data', chunk => {
    text += chunk
  })
  req.on('end', () => {
    const reply = JSON.parse(readFileSync(replyFile, 'utf8'))
    const authorized = req.headers.authorization === `Bearer ${process.env.STUB_DECISIONS_KEY}`
    appendFileSync(logFile, `${JSON.stringify({ method: req.method, url: req.url, authorized, body: JSON.parse(text) })}\n`)
    setTimeout(() => {
      res.writeHead(reply.status ?? 200, { 'content-type': 'application/json' })
      res.end(JSON.stringify(reply.body ?? {}))
    }, reply.delayMs ?? 0)
  })
})
server.listen(0, '127.0.0.1', () => writeFileSync(portFile, String(server.address().port)))
