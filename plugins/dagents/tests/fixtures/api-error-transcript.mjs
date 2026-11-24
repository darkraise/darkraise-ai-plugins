// Records copied from a session transcript (2026-11-20) around a turn that
// ended on an API error: the last model record, the synthetic record with
// isApiErrorMessage, and the record written after it. Long text is cut.
export default [
  {
    "parentUuid": "5d458c39-19df-4831-9544-ab40d9d7a695",
    "isSidechain": false,
    "message": {
      "model": "claude-opus-5-5",
      "id": "msg_011ChEzFuSYdp13MeSJdQBCe",
      "type": "message",
      "role": "assistant",
      "content": [
        {
          "type": "thinking",
          "thinking": "All five socket tests fail on the base, "
        }
      ],
      "container": null,
      "stop_reason": "end_turn",
      "stop_sequence": null,
      "stop_details": null,
      "usage": {
        "input_tokens": 2,
        "cache_creation_input_tokens": 2702,
        "cache_read_input_tokens": 290239,
        "output_tokens": 10,
        "output_tokens_details": {
          "thinking_tokens": 0
        },
        "server_tool_use": {
          "web_search_requests": 0,
          "web_fetch_requests": 0
        },
        "service_tier": "standard",
        "cache_creation": {
          "ephemeral_1h_input_tokens": 2702,
          "ephemeral_5m_input_tokens": 0
        },
        "inference_geo": "global",
        "iterations": [],
        "speed": "standard",
        "fallback_credit": null
      },
      "input_transformations": [],
      "diagnostics": null,
      "context_management": null
    },
    "thinkingDurationMs": 8,
    "thinkingDisplay": "updates",
    "apiBlockIndex": 1,
    "requestId": "req_011ChEzFuDQryoBBSh9Ha3nU",
    "requestRef": "600c0664-2491-43ff-b7bd-b185d37febc6",
    "requestedModel": "claude-opus-5-5",
    "promptCacheRequested": "1h",
    "type": "assistant",
    "uuid": "c81c2882-e15b-4669-a771-0487d18be66a",
    "timestamp": "2026-11-20T22:43:00.687Z",
    "advisorModel": "claude-fable-5-2",
    "effort": "high",
    "perTurnEffort": "high",
    "madeBy": "model",
    "session_id": "33b4cf25-e5a5-46eb-92e3-967140ef2bf1",
    "sessionId": "a44a4fba-64b2-4d34-906e-d92bf3571b6d"
  },
  {
    "parentUuid": "c81c2882-e15b-4669-a771-0487d18be66a",
    "isSidechain": false,
    "type": "assistant",
    "uuid": "8c49e7d2-f004-4df3-916b-7325b837f5a5",
    "timestamp": "2026-11-20T22:43:07.751Z",
    "message": {
      "diagnostics": null,
      "id": "94730d19-df19-4964-aeb6-0a9a171db455",
      "container": null,
      "model": "<synthetic>",
      "role": "assistant",
      "stop_details": null,
      "stop_reason": "stop_sequence",
      "stop_sequence": "",
      "type": "message",
      "usage": {
        "output_tokens_details": null,
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_creation_input_tokens": 0,
        "cache_read_input_tokens": 0,
        "server_tool_use": {
          "web_search_requests": 0,
          "web_fetch_requests": 0
        },
        "service_tier": null,
        "cache_creation": {
          "ephemeral_1h_input_tokens": 0,
          "ephemeral_5m_input_tokens": 0
        },
        "inference_geo": null,
        "iterations": null,
        "speed": null,
        "fallback_credit": null
      },
      "content": [
        {
          "type": "text",
          "text": "API Error: Connection lost mid-response. The response above may be incomplete."
        }
      ],
      "context_management": null
    },
    "apiError": "connection_failed",
    "error": "server_error",
    "truncatedAfterOutput": true,
    "isApiErrorMessage": true,
    "streamCutCause": "stale_connection",
    "madeBy": "model",
    "session_id": "33b4cf25-e5a5-46eb-92e3-967140ef2bf1",
    "sessionId": "a44a4fba-64b2-4d34-906e-d92bf3571b6d"
  },
  {
    "type": "last-prompt",
    "lastPrompt": "Continue the auto run.",
    "leafUuid": "8c49e7d2-f004-4df3-916b-7325b837f5a5",
    "sessionId": "a44a4fba-64b2-4d34-906e-d92bf3571b6d"
  }
]
