// Generated from service-commands.json: edit that file, then run the command in tests/repository-layout.test.mjs.
export default [
  {
    "command": "npm run dev",
    "role": "service"
  },
  {
    "command": "pnpm dev",
    "role": "service"
  },
  {
    "command": "yarn start",
    "role": "service"
  },
  {
    "command": "npm run dev:api",
    "role": "service"
  },
  {
    "command": "vite --port 3000",
    "role": "service"
  },
  {
    "command": "npx next dev",
    "role": "service"
  },
  {
    "command": "python3 -m http.server 8000",
    "role": "service"
  },
  {
    "command": "docker compose up",
    "role": "service"
  },
  {
    "command": "tail -f app.log",
    "role": "service"
  },
  {
    "command": "jest --watch",
    "role": "service"
  },
  {
    "command": "jest --watchAll",
    "role": "service"
  },
  {
    "command": "cargo watch -x run",
    "role": "service"
  },
  {
    "command": "cd web && npm run dev",
    "role": "service"
  },
  {
    "command": "PORT=3000 npm start",
    "role": "service"
  },
  {
    "command": "npm test",
    "role": "work"
  },
  {
    "command": "npm run build",
    "role": "work"
  },
  {
    "command": "vite build",
    "role": "work"
  },
  {
    "command": "vitest",
    "role": "work"
  },
  {
    "command": "docker compose up -d",
    "role": "work"
  },
  {
    "command": "npm run start:build",
    "role": "work"
  },
  {
    "command": "node codex-companion.mjs review",
    "role": "work"
  },
  {
    "command": "echo \"npm run dev\"",
    "role": "work"
  },
  {
    "command": "make\nnpm run dev",
    "role": "work"
  },
  {
    "command": "sleep 1200",
    "role": "timer"
  },
  {
    "command": "sleep 30m",
    "role": "timer"
  },
  {
    "command": "sleep 5 && npm test",
    "role": "work"
  }
]
