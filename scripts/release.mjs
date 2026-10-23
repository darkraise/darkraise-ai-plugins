import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const { values: options } = parseArgs({ options: { 'dry-run': { type: 'boolean' } } });
const isDryRun = options['dry-run'] ?? false;
const root = fileURLToPath(new URL('../', import.meta.url));
const run = (command, args) => execFileSync(command, args, { cwd: root, encoding: 'utf8', timeout: 120_000, stdio: ['ignore', 'pipe', 'inherit'] }).trim();
const git = (...args) => run('git', args);

const names = JSON.parse(readFileSync(resolve(root, '.claude-plugin/marketplace.json'), 'utf8')).plugins.map(plugin => plugin.name);
const tagOf = (name, version) => `${name}-v${version}`;
const manifestPaths = name => ['.claude-plugin', '.codex-plugin'].map(dir => resolve(root, `plugins/${name}/${dir}/plugin.json`)).filter(existsSync);

// The commits that changed the Claude manifest's version line, newest first: a
// release commit, CI's or a hand bump, ends the range the next release covers.
const versionCommits = name => git('log', '--format=%H', '-G"version"', '--', `plugins/${name}/.claude-plugin/plugin.json`).split('\n').filter(Boolean);

function commitsIn(name, from, to) {
  const out = git('log', '--no-merges', '--format=%H%x1f%s%x1f%b%x1e', from ? `${from}..${to}` : to, '--', `plugins/${name}/`);
  return out.split('\x1e').map(record => record.trim()).filter(Boolean).map(record => {
    const [hash, subject, body = ''] = record.split('\x1f');
    return { hash, subject, body };
  });
}

const isBreaking = commit => /^\w+(\([^)]*\))?!:/.test(commit.subject) || /^BREAKING[ -]CHANGE:/m.test(commit.body);
const isFeature = commit => /^feat(\([^)]*\))?:/.test(commit.subject);
function bumped(version, commits) {
  const [major, minor, patch] = version.split(/[-+]/)[0].split('.').map(Number);
  if (commits.some(isBreaking)) return `${major + 1}.0.0`;
  if (commits.some(isFeature)) return `${major}.${minor + 1}.0`;
  return `${major}.${minor}.${patch + 1}`;
}
const notesOf = commits => commits.length === 0 ? 'No changes to this plugin since its previous version.' : commits.map(commit => `- ${commit.subject} (${commit.hash.slice(0, 7)})`).join('\n');

function setVersion(path, from, to) {
  const text = readFileSync(path, 'utf8');
  const match = /("version"\s*:\s*")([^"]*)(")/.exec(text);
  if (match?.[2] !== from) throw new Error(`${path}: expected version ${from}, found ${match?.[2] ?? 'none'}`);
  writeFileSync(path, text.slice(0, match.index) + match[1] + to + match[3] + text.slice(match.index + match[0].length));
}

const tags = [];
const bumps = [];
for (const name of names) {
  const version = JSON.parse(readFileSync(manifestPaths(name)[0], 'utf8')).version;
  const [base, previous] = versionCommits(name);
  if (!base) throw new Error(`${name}: no commit sets its version`);
  // The version on main before automated releases, or a hand bump, has no tag yet.
  if (git('tag', '--list', tagOf(name, version)) === '') tags.push({ name, version, commit: base, notes: notesOf(commitsIn(name, previous, base)) });
  const pending = commitsIn(name, base, 'HEAD');
  if (pending.length > 0) bumps.push({ name, from: version, to: bumped(version, pending), notes: notesOf(pending) });
}

for (const tag of tags) console.log(`tag ${tagOf(tag.name, tag.version)} at ${tag.commit.slice(0, 7)}`);
for (const bump of bumps) console.log(`release ${bump.name} ${bump.from} -> ${bump.to}\n${bump.notes}`);
if (tags.length === 0 && bumps.length === 0) console.log('Nothing to tag or release.');

if (!isDryRun) {
  for (const bump of bumps) {
    const paths = manifestPaths(bump.name);
    for (const path of paths) setVersion(path, bump.from, bump.to);
    const scriptVersion = resolve(root, `plugins/${bump.name}/scripts/VERSION`);
    if (existsSync(scriptVersion)) {
      writeFileSync(scriptVersion, readFileSync(scriptVersion, 'utf8').replace(bump.from, bump.to));
      paths.push(scriptVersion);
    }
    git('add', '--', ...paths);
    git('commit', '--quiet', '-m', `chore(${bump.name}): release ${bump.to}`);
    tags.push({ name: bump.name, version: bump.to, commit: git('rev-parse', 'HEAD'), notes: bump.notes });
  }
  if (bumps.length > 0) run(process.execPath, ['scripts/validate-repository.mjs']);
  for (const tag of tags) git('tag', '-a', tagOf(tag.name, tag.version), tag.commit, '-m', tag.notes);
  // One atomic push: main never carries a release commit without its tag.
  const refs = tags.map(tag => `refs/tags/${tagOf(tag.name, tag.version)}`);
  if (bumps.length > 0) refs.unshift('HEAD:refs/heads/main');
  if (refs.length > 0) git('push', '--atomic', 'origin', ...refs);

  // Every plugin tag gets a release, so a run that pushed tags but failed
  // before its releases is completed by the next one.
  const released = new Set(JSON.parse(run('gh', ['release', 'list', '--limit', '1000', '--json', 'tagName'])).map(release => release.tagName));
  for (const name of names) {
    for (const tag of git('tag', '--list', `${name}-v*`, '--sort=v:refname').split('\n').filter(Boolean)) {
      if (released.has(tag)) continue;
      run('gh', ['release', 'create', tag, '--verify-tag', '--notes-from-tag', '--title', `${name} ${tag.slice(name.length + 2)}`]);
      console.log(`released ${tag}`);
    }
  }
}
