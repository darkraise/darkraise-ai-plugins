// Generated from services.json: edit that file, then run the command in tests/repository-layout.test.mjs.
export default {
  "services": [
    "^(npm|pnpm|yarn|bun)( run)? (dev|start|serve|preview|watch)(:(?!build\\b)|\\s|$)",
    "^((npx|bunx|pnpm exec) )?(vite(?! build)(\\s|$)|next (dev|start)|nuxt dev|astro dev|webpack serve|ng serve|nodemon)",
    "^python3? -m http\\.server",
    "^(uvicorn|flask run|rails (s|server))(\\s|$)",
    "^docker(-| )compose up(?!.*\\s(-d|--detach)(\\s|$))",
    "^tail -[fF](\\s|$)",
    "^cargo watch(\\s|$)",
    "\\s--watch(All)?(=(?!(false|0)(\\s|$))|\\s|$)"
  ],
  "timer": "^sleep\\s+[0-9]+(\\.[0-9]+)?[smhd]?$"
}
