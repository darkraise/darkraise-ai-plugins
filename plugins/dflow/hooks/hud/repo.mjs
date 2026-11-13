// The git reading for the Repo card, ported from the dforge cockpit's lib.ts:
// plugins never import each other.

function slashes(path) {
  return path.replace(/\\/g, '/').replace(/\/+$/, '');
}

/** Reads `git status --porcelain=v2 --branch`. */
export function repoFromPorcelain(text) {
  const state = { branch: '', ahead: 0, behind: 0, changed: 0, untracked: 0 };
  let oid = '';
  // Git for Windows can end its lines with \r.
  for (const line of text.split(/\r?\n/)) {
    if (line.startsWith('# branch.oid ')) oid = line.slice(13).trim();
    else if (line.startsWith('# branch.head ')) state.branch = line.slice(14).trim();
    else if (line.startsWith('# branch.ab ')) {
      const match = /\+(\d+) -(\d+)/.exec(line);
      if (match) {
        state.ahead = Number(match[1]);
        state.behind = Number(match[2]);
      }
    } else if (line.startsWith('? ')) state.untracked += 1;
    else if (/^[12u] /.test(line)) state.changed += 1;
  }
  if (state.branch === '') return null;
  if (state.branch === '(detached)') state.branch = oid === '' ? 'detached' : `@${oid.slice(0, 7)}`;
  return state;
}

/**
 * The repository's name: `owner/name` from its origin remote (scp-style or
 * URL, `.git` dropped), else the root folder's name.
 */
export function repoName(remote, root) {
  const path = (remote ?? '')
    .trim()
    .replace(/\.git\/?$/, '')
    .replace(/\/+$/, '')
    .replace(/^[a-z][a-z0-9+.-]*:\/\/[^/]*\//i, '')
    .replace(/^[^@/]+@[^:/]+:/, '');
  const parts = path.split('/').filter(Boolean);
  if (parts.length >= 2) return parts.slice(-2).join('/');
  if (parts.length === 1) return parts[0];
  const top = slashes(root);
  return top.slice(top.lastIndexOf('/') + 1) || top;
}

/** The working folder, "~"-relative under home. */
export function shortDir(cwd, home) {
  const dir = slashes(cwd);
  const base = slashes(home ?? '');
  if (base !== '' && dir === base) return '~';
  return base !== '' && dir.startsWith(`${base}/`) ? `~${dir.slice(base.length)}` : cwd;
}
