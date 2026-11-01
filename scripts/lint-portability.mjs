import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

// No message or comment in this file may hold the text the rules look for:
// the file lies under scripts/, which the tree scan reads.
const MESSAGES = {
  'git-c-pwd': 'git.exe cannot open a POSIX $PWD path; pass it through dr_native_path (plugins/dforge/scripts/lib/native-path.sh)',
  'awk-v-backslash': 'awk -v expands a backslash in its value; pass the value through ENVIRON instead',
  'jq-pwd-file': 'jq.exe cannot open a POSIX path built from $PWD or $TMPDIR; feed the file on stdin',
  'import-path': 'a dynamic import of a path must go through pathToFileURL',
};

const EXEMPT = /(?:#|\/\/) portability: ok — +\S.*$/;
const GIT_C_PWD = /git -C\s+"?(?:\$PWD(?![\w])|\$\{PWD\}|\$\(pwd\))/;
const COMMAND_SUBSTITUTION = /\$\((?:[^()]|\([^()]*\))*\)/g;
const AWK_V_OPTION = /(?:^|\s)-v\s*[A-Za-z_]\w*=("(?:\\.|[^"\\])*"|'[^']*'|\S+)/g;
const MSYS_EXPORT = /^\s*export\b.*MSYS_NO_PATHCONV/m;
const PWD_OR_TMPDIR = /\$PWD(?![\w])|\$\{PWD\}|\$TMPDIR(?![\w])|\$\{TMPDIR\}/;
const DYNAMIC_IMPORT = /(?<![\w$.])import\(/g;

function gitCPwd(line) {
  return GIT_C_PWD.test(line) && !line.includes('dr_native_path');
}

function awkVBackslash(line) {
  const at = line.search(/\bawk\b/);
  if (at < 0) return false;
  const tail = line.slice(at).replace(COMMAND_SUBSTITUTION, '$()');
  return [...tail.matchAll(AWK_V_OPTION)].some(([, value]) => value.includes('\\'));
}

function jqPwdFile(line) {
  const at = line.search(/\bjq\b/);
  if (at < 0) return false;
  let rest = line.slice(at).replaceAll('$(pwd)', '$PWD').replace(/'[^']*'/g, "''")
    .replace(/"(?:\\.|[^"\\])*"/g, quoted => quoted.replace(/[|;&)]/g, ' '));
  const cut = rest.search(/\|\||&&|\||;|\)/);
  if (cut >= 0) rest = rest.slice(0, cut);
  rest = rest
    .replace(/<<<\s*(?:"(?:\\.|[^"\\])*"|\S+)/g, '')
    .replace(/<\s*(?:"(?:\\.|[^"\\])*"|\S+)/g, '')
    .replace(/--arg(?:json)?\s+\S+\s+(?:"(?:\\.|[^"\\])*"|\S+)/g, '');
  return PWD_OR_TMPDIR.test(rest);
}

// The argument text of the call whose opening parenthesis sits just before
// `start`, up to its matching closing parenthesis; quoted strings are skipped
// so a parenthesis inside one does not count.
function callArgument(text, start) {
  let depth = 1;
  for (let i = start; i < text.length; i++) {
    const c = text[i];
    if (c === '"' || c === "'" || c === '`') {
      for (i++; i < text.length && text[i] !== c; i++) if (text[i] === '\\') i++;
    } else if (c === '(') depth++;
    else if (c === ')' && --depth === 0) return text.slice(start, i);
  }
  return text.slice(start);
}

function importPathLines(text) {
  const lines = [];
  for (const match of text.matchAll(DYNAMIC_IMPORT)) {
    const arg = callArgument(text, match.index + match[0].length).trim();
    const safe = arg === '' || /^["']/.test(arg) || /^`\.\.?\//.test(arg) || arg.includes('pathToFileURL');
    if (!safe) lines.push(text.slice(0, match.index).split('\n').length);
  }
  return lines;
}

export function lintText(path, text) {
  const lines = text.split('\n').map(line => line.replace(/\r$/, ''));
  const exempt = index => EXEMPT.test(lines[index]);
  const msys = MSYS_EXPORT.test(lines.join('\n'));
  const hits = [];
  const hit = (line, rule) => hits.push({ line, rule, message: MESSAGES[rule] });
  lines.forEach((line, index) => {
    if (exempt(index)) return;
    if (gitCPwd(line)) hit(index + 1, 'git-c-pwd');
    if (awkVBackslash(line)) hit(index + 1, 'awk-v-backslash');
    if (msys && jqPwdFile(line)) hit(index + 1, 'jq-pwd-file');
  });
  for (const line of importPathLines(text)) if (!exempt(line - 1)) hit(line, 'import-path');
  return hits.sort((a, b) => a.line - b.line);
}

// statSync follows a symbolic link; a dangling one has no target to stat.
function isDirectory(path) {
  try { return statSync(path).isDirectory(); } catch { return false; }
}

function isFile(path) {
  try { return statSync(path).isFile(); } catch { return false; }
}

// A symbolic link to a file is linted as that file. Any other link is not
// followed, so a link cycle cannot loop, and is reported in `skipped`.
function filesUnder(dir, skipped) {
  if (!existsSync(dir)) return [];
  const files = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) { if (entry.name !== 'node_modules') files.push(...filesUnder(path, skipped)); }
    else if (entry.isFile()) files.push(path);
    else if (entry.isSymbolicLink()) { if (isFile(path)) files.push(path); else skipped.push(path); }
  }
  return files;
}

export function lintTree(root) {
  root = resolve(root);
  const plugins = join(root, 'plugins');
  const dirs = [join(root, 'scripts')];
  if (existsSync(plugins)) {
    for (const name of readdirSync(plugins)) {
      if (isDirectory(join(plugins, name))) dirs.push(join(plugins, name, 'scripts'), join(plugins, name, 'tests'));
    }
  }
  const skipped = [];
  const files = dirs.flatMap(dir => filesUnder(dir, skipped))
    .map(path => ({ path, name: relative(root, path).split(sep).join('/') }))
    .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  for (const path of skipped) console.error(`lint-portability: not linted, a symbolic link to no file: ${relative(root, path).split(sep).join('/')}`);
  const out = [];
  for (const { path, name } of files) {
    const text = readFileSync(path, 'utf8');
    if (text.includes('\u0000')) continue;
    for (const { line, rule, message } of lintText(name, text)) out.push(`${name}:${line} ${rule} ${message}`);
  }
  return out;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const hits = lintTree(process.argv[2] ?? fileURLToPath(new URL('../', import.meta.url)));
  if (hits.length) { console.log(hits.join('\n')); process.exitCode = 1; }
}
