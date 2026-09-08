import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync, rmSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

const readSkill = name => readFileSync(new URL(`../plugins/dcc-${name}/skills/${name}/SKILL.md`, import.meta.url), 'utf8');
test('documented Win32 discovery finds centrally managed versions', () => {
  const skill = readSkill('darkraise-win32ui');
  const section = skill.split('## Current Project Context')[1];
  const command = section.match(/```(?:bash)?\r?\n([\s\S]*?)```/)[1].trim().replace(/^!`|`$/g, '');
  const fixture = mkdtempSync(resolve(tmpdir(), 'dr-ui-'));
  try {
    writeFileSync(resolve(fixture, 'Directory.Packages.props'), '<Project><ItemGroup><PackageVersion Include="Darkraise.Win32UI" Version="1.2.3" /></ItemGroup></Project>');
    writeFileSync(resolve(fixture, 'App.csproj'), '<Project><ItemGroup><PackageReference Include="Darkraise.Win32UI" /></ItemGroup></Project>');
    const output = execFileSync(process.env.DR_TEST_BASH ?? 'bash', ['-c', command], { cwd: fixture, encoding: 'utf8', timeout: 10000 });
    assert.match(output, /PackageVersion[^\n]*1\.2\.3/);
    assert.match(output, /PackageReference/);
  } finally { rmSync(fixture, { recursive: true, force: true }); }
});
test('UI skill context does not require Claude inline preprocessing', () => {
  for (const name of ['darkraise-ui', 'darkraise-win32ui']) assert.equal(/^\s*!`/m.test(readSkill(name)), false, `${name} requires inline preprocessing`);
});
test('documented restore lookup selects the chosen framework version', () => {
  const section = readSkill('darkraise-win32ui').split('## Current Project Context')[1];
  const commands = [...section.matchAll(/```bash\r?\n([\s\S]*?)```/g)];
  const fixture = mkdtempSync(resolve(tmpdir(), 'dr-assets-'));
  try {
    mkdirSync(resolve(fixture, 'obj'));
    writeFileSync(resolve(fixture, 'obj/project.assets.json'), JSON.stringify({
      targets: { 'net10.0-windows': { 'Darkraise.Win32UI/1.2.3': {} }, 'net9.0-windows': { 'Darkraise.Win32UI/9.9.9': {} } },
      libraries: { 'Darkraise.Win32UI/1.2.3': { path: 'darkraise.win32ui/1.2.3' }, 'Darkraise.Win32UI/9.9.9': { path: 'darkraise.win32ui/9.9.9' } },
      packageFolders: { '/fixture/packages/': {} },
    }));
    const output = execFileSync(process.env.DR_TEST_BASH ?? 'bash', ['-c', commands[1][1]], {
      cwd: fixture, encoding: 'utf8', timeout: 10000, env: { ...process.env, tfm: 'net10.0-windows' },
    });
    assert.equal(JSON.parse(output).path, 'darkraise.win32ui/1.2.3');
  } finally { rmSync(fixture, { recursive: true, force: true }); }
});
