// Generated from cases.json: edit that file, then run the command in tests/repository-layout.test.mjs.
export default [
  {
    "name": "plain fast in this request",
    "before": [],
    "after": [
      "Process: fast — a one-line fix"
    ],
    "on": true
  },
  {
    "name": "plain fast in an earlier request",
    "before": [
      "Process: fast — a one-line fix"
    ],
    "after": [
      "Done."
    ],
    "on": false
  },
  {
    "name": "session fast in an earlier request",
    "before": [
      "Process: fast (session) — spikes all day"
    ],
    "after": [
      "ok"
    ],
    "on": true
  },
  {
    "name": "an expired plain line keeps the session scope",
    "before": [
      "Process: fast (session) — spikes",
      "Process: fast — again"
    ],
    "after": [
      "ok"
    ],
    "on": true
  },
  {
    "name": "a full-flow line ends the session scope",
    "before": [
      "Process: fast (session) — spikes",
      "Process: bounded — no trigger"
    ],
    "after": [
      "ok"
    ],
    "on": false
  },
  {
    "name": "no turn stamp: plain fast is on",
    "before": [
      "Process: fast — a one-line fix"
    ],
    "after": null,
    "on": true
  },
  {
    "name": "a full-flow line in this request",
    "before": [
      "Process: fast (session) — spikes"
    ],
    "after": [
      "Process: architectural, depth full — risk"
    ],
    "on": false
  }
]
