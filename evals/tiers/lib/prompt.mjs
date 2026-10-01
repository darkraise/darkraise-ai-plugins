import { readFileSync } from 'node:fs';

// template FILE — the prompt body of a dispatch template: the lines after
// `prompt: |` inside the file's first top-level fence, with the four-space
// YAML indent removed. Nested fences are indented, so only a fence at column
// 0 opens or closes the block.
export function template(file) {
  const lines = readFileSync(file, 'utf8').split('\n');
  const open = lines.findIndex(l => /^```\s*$/.test(l));
  const close = lines.findIndex((l, i) => i > open && /^```\s*$/.test(l));
  const at = lines.findIndex((l, i) => i > open && i < close && /^\s*prompt: \|\s*$/.test(l));
  if (open < 0 || close < 0 || at < 0) throw new Error(`${file}: no "prompt: |" block in its first fence`);
  return lines.slice(at + 1, close).map(l => l.replace(/^ {4}/, '')).join('\n');
}

// fill BODY VALUES — BODY with every key of VALUES replaced by its value. A
// key the body lacks is an error: the template changed under the harness.
export function fill(body, values) {
  let out = body;
  for (const [key, value] of Object.entries(values)) {
    if (!out.includes(key)) throw new Error(`the template has no ${key}`);
    out = out.replaceAll(key, value);
  }
  return out;
}
