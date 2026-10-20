// heredocOpener CMD I — the heredoc opener starting at CMD[I] as
// { length, word, tabs }, or null. The delimiter is the whole word after <<
// or <<-, quoted ('END-OF-DOC') or not; `tabs` marks <<-.
export function heredocOpener(cmd, i) {
  if (!cmd.startsWith('<<', i)) return null;
  const opener = /^<<(-)?[ \t]*(?:'([^'\n]*)'|"([^"\n]*)"|([^\s;&|<>()'"]+))/.exec(cmd.slice(i));
  return opener ? { length: opener[0].length, word: opener[2] ?? opener[3] ?? opener[4], tabs: opener[1] === '-' } : null;
}

// heredocEnd CMD I DOC — where DOC's body, starting at the newline CMD[I],
// ends: just past the line that is exactly its delimiter (tabs before it
// allowed for <<-), or CMD's length when no line closes it.
export function heredocEnd(cmd, i, { word, tabs }) {
  const quoted = word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const end = new RegExp(`\\n${tabs ? '\\t*' : ''}${quoted}(?=\\n|$)`).exec(cmd.slice(i));
  return end ? i + end.index + end[0].length : cmd.length;
}
