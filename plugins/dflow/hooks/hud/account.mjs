// Who the session runs as, which model, and Remote Control, ported from the
// dforge cockpit's lib.ts: plugins never import each other.

function slashes(path) {
  return path.replace(/\\/g, '/').replace(/\/+$/, '');
}

/** The account's key: its config directory, "~"-relative under home. */
export function accountKey(configDir, home) {
  const dir = slashes(configDir);
  const base = slashes(home);
  if (dir === base) return '~';
  return base !== '' && dir.startsWith(`${base}/`) ? `~${dir.slice(base.length)}` : dir;
}

// Frame colors that read on light and dark terminals alike.
const ACCOUNT_COLORS = ['#af87ff', '#5fafff', '#5fd7af', '#ffaf5f', '#ff87af', '#87d75f', '#d787ff', '#5fd7ff'];

/** The account's frame color: one of eight, picked from its key, so each account keeps its own. */
export function accountColor(key) {
  let hash = 0;
  for (const ch of key) hash = (hash * 31 + (ch.codePointAt(0) ?? 0)) >>> 0;
  return ACCOUNT_COLORS[hash % ACCOUNT_COLORS.length];
}

/** Claude's billing type, "stripe_subscription" → "subscription". */
export function billingLabel(billing) {
  if (billing === null || billing === undefined || billing === '') return null;
  return billing.replace(/^(stripe|apple|google)_/, '').replace(/_/g, ' ');
}

/** "claude-opus-5-5[1m]" → "Opus 5.5". */
export function modelName(id, isShort = false) {
  const bare = id.replace(/\[.*?\]$/, '').replace(/^claude-/, '').replace(/-\d{8}$/, '');
  const [family = bare, ...rest] = bare.split('-');
  const name = family.charAt(0).toUpperCase() + family.slice(1);
  const version = rest.filter(part => /^\d+$/.test(part)).join('.');
  return isShort || version === '' ? name : `${name} ${version}`;
}

/** A remote client's surface as a person names the device. */
export function deviceName(surface) {
  return surface === 'mobile' ? 'phone' : surface === 'desktop' ? 'desktop app' : surface === 'vscode' ? 'VS Code' : surface;
}

/** Remote Control as the HUD can see it: the devices attached, or the startup setting. */
export function remoteRuns(clients, setting) {
  if (clients.length > 0) {
    const names = [...new Set(clients.map(one => deviceName(one.surface)))];
    const what = clients.length === 1 ? names[0] : names.length === 1 ? `${clients.length} ${names[0]}s` : `${clients.length} devices`;
    return [{ text: '● ', color: 'green', bold: true }, { text: 'connected' }, { text: ' · ', dim: true }, { text: what, color: 'green' }];
  }
  if (setting === 'true') return [{ text: '○ ', color: 'green' }, { text: 'on', color: 'green' }, { text: ' · no device yet', dim: true }];
  return [{ text: '○ not connected', dim: true }];
}

/** The account from its .claude.json (CLAUDE_CONFIG_DIR's, else the home one), every missing string null. */
export function accountFrom(claudeJson, configDir, home) {
  const oauth = claudeJson?.oauthAccount ?? {};
  const text = value => (typeof value === 'string' && value !== '' ? value : null);
  const key = accountKey(configDir || `${home}/.claude`, home);
  return {
    email: text(oauth.emailAddress),
    name: text(oauth.displayName),
    organization: text(oauth.organizationName),
    role: text(oauth.organizationRole),
    billing: text(oauth.billingType),
    key,
    color: accountColor(key),
  };
}
