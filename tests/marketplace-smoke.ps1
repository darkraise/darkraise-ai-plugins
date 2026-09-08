param(
  [Parameter(Mandatory)][string]$Claude,
  [Parameter(Mandatory)][string]$Codex,
  [Parameter(Mandatory)][string]$FixtureRoot
)
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixtureParent = [IO.Path]::GetFullPath($FixtureRoot)
if (-not $fixtureParent.StartsWith("$repository\.superpowers\", [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture root must be inside this repository .superpowers directory' }
$fixture = Join-Path $fixtureParent ([Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $fixture -Force)
$evidence = [Collections.Generic.List[object]]::new()
$previousEnvironment = @{}
foreach ($name in @('CODEX_HOME','CLAUDE_CONFIG_DIR','HOME','USERPROFILE','APPDATA','LOCALAPPDATA','GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0','GIT_CONFIG_KEY_1','GIT_CONFIG_VALUE_1')) {
  $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
function Invoke-Client([string]$Executable, [string[]]$Arguments, [switch]$AllowFailure) {
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = $Executable
  $info.WorkingDirectory = $fixture
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $info
  try {
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(60000)) {
      $process.Kill($true)
      if (-not $process.WaitForExit(10000)) { throw 'Owned CLI tree failed to terminate' }
      throw "CLI timed out: $Executable $($Arguments -join ' ')"
    }
    $result = @{exit=$process.ExitCode; stdout=$stdout.GetAwaiter().GetResult(); stderr=$stderr.GetAwaiter().GetResult()}
    $evidence.Add(@{command=([IO.Path]::GetFileName($Executable) + ' ' + ($Arguments -join ' ')); result=$result})
    if ($result.exit -ne 0 -and -not $AllowFailure) { throw "$Executable failed: $($result.stderr) $($result.stdout)" }
    return $result
  } finally {
    if ($process.Id -and -not $process.HasExited) { $process.Kill($true); [void]$process.WaitForExit(10000) }
    $process.Dispose()
  }
}
function Write-Json([string]$Path, $Value) {
  [void](New-Item -ItemType Directory -Path (Split-Path $Path) -Force)
  [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 30) + "`n"))
}
function Check([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
  Write-Output "PASS: $Message"
}
try {
  foreach ($name in @('CODEX_HOME','CLAUDE_CONFIG_DIR','HOME','USERPROFILE','APPDATA','LOCALAPPDATA')) {
    $path = Join-Path $fixture $name
    [void](New-Item -ItemType Directory -Path $path -Force)
    [Environment]::SetEnvironmentVariable($name, $path, 'Process')
  }
  $env:GIT_CONFIG_COUNT = '1'
  $env:GIT_CONFIG_KEY_0 = 'core.longpaths'
  $env:GIT_CONFIG_VALUE_0 = 'true'
  Invoke-Client $Claude @('--version') | Out-Null
  Invoke-Client $Codex @('--version') | Out-Null
  $market = Join-Path $fixture 'market'
  [void](New-Item -ItemType Directory -Path $market)
  foreach ($path in @('.claude-plugin','.agents/plugins','plugins/dr-status','plugins/dr-superpowers','plugins/dcc-darkraise-ui','plugins/dcc-darkraise-win32ui')) {
    $destination = Join-Path $market $path
    [void](New-Item -ItemType Directory -Path (Split-Path $destination) -Force)
    Copy-Item -LiteralPath (Join-Path $repository $path) -Destination $destination -Recurse
  }
  Invoke-Client $Codex @('plugin','marketplace','add',$market,'--json') | Out-Null
  $listing = (Invoke-Client $Codex @('plugin','list','--marketplace','darkraise','--available','--json')).stdout | ConvertFrom-Json
  Check ((@($listing.available.name | Sort-Object) -join ',') -eq 'dcc-darkraise-ui,dcc-darkraise-win32ui,dr-superpowers') 'Codex root catalog has exactly three supported entries'
  $rejected = Invoke-Client $Codex @('plugin','add','dr-status@darkraise','--json') -AllowFailure
  Check ($rejected.exit -ne 0) 'Codex rejects statusline installation by name'
  foreach ($name in @('dr-superpowers','dcc-darkraise-ui','dcc-darkraise-win32ui')) {
    $installed = (Invoke-Client $Codex @('plugin','add',"$name@darkraise",'--json')).stdout | ConvertFrom-Json
    $sourceManifest = Get-Content (Join-Path $market "plugins/$name/.codex-plugin/plugin.json") -Raw
    $installedManifest = Get-Content (Join-Path $installed.installedPath '.codex-plugin/plugin.json') -Raw
    Check ($sourceManifest -eq $installedManifest) "Codex installed manifest bytes match $name"
  }
  $uiRoot = Join-Path $market 'plugins/dcc-darkraise-ui'
  $uiManifest = Get-Content (Join-Path $uiRoot '.codex-plugin/plugin.json') -Raw | ConvertFrom-Json
  $uiManifest.version = '0.1.0'
  Write-Json (Join-Path $uiRoot '.codex-plugin/plugin.json') $uiManifest
  [IO.File]::WriteAllText((Join-Path $uiRoot 'skills/darkraise-ui/SKILL.md'), "---`nname: darkraise-ui`ndescription: Old fixture skill`n---`nOld fixture bytes.`n")
  Invoke-Client $Codex @('plugin','remove','dcc-darkraise-ui@darkraise') | Out-Null
  $oldUi = (Invoke-Client $Codex @('plugin','add','dcc-darkraise-ui@darkraise','--json')).stdout | ConvertFrom-Json
  Check ($oldUi.version -eq '0.1.0') 'Codex seeds an old UI cache version'
  Copy-Item -LiteralPath (Join-Path $repository 'plugins/dcc-darkraise-ui/.codex-plugin/plugin.json') -Destination (Join-Path $uiRoot '.codex-plugin/plugin.json') -Force
  Copy-Item -LiteralPath (Join-Path $repository 'plugins/dcc-darkraise-ui/skills/darkraise-ui/SKILL.md') -Destination (Join-Path $uiRoot 'skills/darkraise-ui/SKILL.md') -Force
  $newUi = (Invoke-Client $Codex @('plugin','add','dcc-darkraise-ui@darkraise','--json')).stdout | ConvertFrom-Json
  Check ($newUi.version -eq '0.2.0') 'Codex upgrades UI cache version'
  Check ((Get-Content (Join-Path $newUi.installedPath 'skills/darkraise-ui/SKILL.md') -Raw) -eq (Get-Content (Join-Path $uiRoot 'skills/darkraise-ui/SKILL.md') -Raw)) 'Codex upgrade refreshes actual skill bytes'

  Invoke-Client $Claude @('plugin','marketplace','add','https://github.com/anthropics/claude-plugins-official.git') | Out-Null
  Invoke-Client $Claude @('plugin','marketplace','add',$market) | Out-Null
  foreach ($name in @('dr-status','dr-superpowers','dcc-darkraise-ui','dcc-darkraise-win32ui')) {
    Invoke-Client $Claude @('plugin','install',"$name@darkraise") | Out-Null
  }
  $claudeList = (Invoke-Client $Claude @('plugin','list','--json')).stdout | ConvertFrom-Json
  $ownEntries = @($claudeList | Where-Object { $_.id -like '*@darkraise' })
  Check ($ownEntries.Count -eq 4) 'Claude installs four repository plugins'
  Check (@($claudeList | Where-Object { $_.id -eq 'superpowers@claude-plugins-official' }).Count -eq 1) 'Claude resolves the declared cross-marketplace dependency'

  Invoke-Client git @('-C',$market,'init','-q','-b','main') | Out-Null
  Invoke-Client git @('-C',$market,'config','user.email','fixture@example.com') | Out-Null
  Invoke-Client git @('-C',$market,'config','user.name','Fixture') | Out-Null
  Invoke-Client git @('-C',$market,'config','core.autocrlf','false') | Out-Null
  Invoke-Client git @('-C',$market,'add','.') | Out-Null
  Invoke-Client git @('-C',$market,'commit','-qm','test: marketplace fixture') | Out-Null
  $env:GIT_CONFIG_COUNT = '2'
  $env:GIT_CONFIG_KEY_1 = 'url.' + ([Uri]($market + '/')).AbsoluteUri + '.insteadOf'
  $env:GIT_CONFIG_VALUE_1 = 'https://fixture.invalid/market'
  Invoke-Client $Codex @('plugin','marketplace','remove','darkraise') | Out-Null
  Invoke-Client $Codex @('plugin','marketplace','add','https://fixture.invalid/market/','--json') | Out-Null
  $gitListing = (Invoke-Client $Codex @('plugin','list','--marketplace','darkraise','--available','--json')).stdout | ConvertFrom-Json
  $gitNames = @($gitListing.available.name) + @($gitListing.installed | Where-Object marketplaceName -eq 'darkraise' | ForEach-Object name)
  Check ((@($gitNames | Sort-Object -Unique) -join ',') -eq 'dcc-darkraise-ui,dcc-darkraise-win32ui,dr-superpowers') 'Codex Git-source registration selects the dedicated catalog'

  $nativeCatalogPath = Join-Path $market '.agents/plugins/marketplace.json'
  $nativeCatalogBytes = [IO.File]::ReadAllText($nativeCatalogPath)
  $claudeCatalogPath = Join-Path $market '.claude-plugin/marketplace.json'
  $claudeCatalogBytes = [IO.File]::ReadAllText($claudeCatalogPath)
  Remove-Item -LiteralPath $nativeCatalogPath
  $legacyCatalog = $claudeCatalogBytes | ConvertFrom-Json
  $legacyCatalog.plugins += @{name='dcc-telegram-notify'; source='./plugins/dcc-telegram-notify'; description='Retired cache fixture'}
  Write-Json $claudeCatalogPath $legacyCatalog
  $retiredManifest = Join-Path $market 'plugins/dcc-telegram-notify/.claude-plugin/plugin.json'
  Write-Json $retiredManifest @{name='dcc-telegram-notify'; version='1.2.0'; description='Retired cache fixture without hooks'}
  Invoke-Client git @('-C',$market,'add','.') | Out-Null
  Invoke-Client git @('-C',$market,'commit','-qm','test: legacy catalog fixture') | Out-Null
  $legacyRef = (Invoke-Client git @('-C',$market,'rev-parse','HEAD')).stdout.Trim()
  Invoke-Client $Codex @('plugin','marketplace','upgrade','darkraise','--json') | Out-Null
  $legacyStatus = (Invoke-Client $Codex @('plugin','add','dr-status@darkraise','--json')).stdout | ConvertFrom-Json
  $legacyTelegram = (Invoke-Client $Codex @('plugin','add','dcc-telegram-notify@darkraise','--json')).stdout | ConvertFrom-Json
  Check (Test-Path -LiteralPath $legacyStatus.installedPath) 'Legacy Claude fallback can leave statusline installed in Codex'
  [IO.File]::WriteAllText($nativeCatalogPath, $nativeCatalogBytes)
  [IO.File]::WriteAllText($claudeCatalogPath, $claudeCatalogBytes)
  Remove-Item -LiteralPath $retiredManifest
  Invoke-Client git @('-C',$market,'add','.') | Out-Null
  Invoke-Client git @('-C',$market,'commit','-qm','test: revised catalog fixture') | Out-Null
  Invoke-Client $Codex @('plugin','marketplace','upgrade','darkraise','--json') | Out-Null
  $rejected = Invoke-Client $Codex @('plugin','add','dr-status@darkraise','--json') -AllowFailure
  Check ($rejected.exit -ne 0) 'Refreshing an old Git registration selects the new Codex catalog'
  Check ((Test-Path -LiteralPath $legacyStatus.installedPath) -and (Test-Path -LiteralPath $legacyTelegram.installedPath)) 'Catalog refresh preserves retired installed caches until explicit uninstall'
  Invoke-Client $Codex @('plugin','remove','dr-status@darkraise') | Out-Null
  Invoke-Client $Codex @('plugin','remove','dcc-telegram-notify@darkraise') | Out-Null
  Check (-not (Test-Path -LiteralPath $legacyStatus.installedPath) -and -not (Test-Path -LiteralPath $legacyTelegram.installedPath)) 'Explicit removal clears retired Codex caches'

  Invoke-Client $Codex @('plugin','marketplace','remove','darkraise') | Out-Null
  $pinned = (Invoke-Client $Codex @('plugin','marketplace','add','https://fixture.invalid/market','--ref',$legacyRef,'--json')).stdout | ConvertFrom-Json
  Check (-not (Test-Path -LiteralPath (Join-Path $pinned.installedRoot '.agents/plugins/marketplace.json'))) 'Pinned legacy revision uses its old catalog'
  Invoke-Client $Codex @('plugin','marketplace','upgrade','darkraise','--json') | Out-Null
  Check (-not (Test-Path -LiteralPath (Join-Path $pinned.installedRoot '.agents/plugins/marketplace.json'))) 'Refresh does not silently move a pinned revision'
  Invoke-Client $Codex @('plugin','marketplace','remove','darkraise') | Out-Null
  $repinned = (Invoke-Client $Codex @('plugin','marketplace','add','https://fixture.invalid/market','--ref','main','--json')).stdout | ConvertFrom-Json
  Check (Test-Path -LiteralPath (Join-Path $repinned.installedRoot '.agents/plugins/marketplace.json')) 'Explicit revision change selects the revised catalog'
  $conflict = Invoke-Client $Codex @('plugin','marketplace','add',$market,'--json') -AllowFailure
  Check ($conflict.exit -ne 0) 'Codex detects a changed source with the same marketplace name'
  Invoke-Client $Codex @('plugin','marketplace','remove','darkraise') | Out-Null
  Invoke-Client $Codex @('plugin','marketplace','add',$market,'--json') | Out-Null
  $reinstalled = (Invoke-Client $Codex @('plugin','add','dr-superpowers@darkraise','--json')).stdout | ConvertFrom-Json
  $expectedVersion = (Get-Content (Join-Path $market 'plugins/dr-superpowers/.codex-plugin/plugin.json') -Raw | ConvertFrom-Json).version
  Check ($reinstalled.version -eq $expectedVersion) 'Supported remove/add/reinstall recovers a Codex source change'
  Invoke-Client $Codex @('plugin','marketplace','remove','darkraise') | Out-Null
  $direct = Invoke-Client $Codex @('plugin','marketplace','add',$claudeCatalogPath,'--json') -AllowFailure
  if ($direct.exit -eq 0) {
    $directList = (Invoke-Client $Codex @('plugin','list','--marketplace','darkraise','--available','--json')).stdout | ConvertFrom-Json
    Check (@($directList.available | Where-Object name -eq 'dr-status').Count -eq 1) 'Direct Claude catalog registration bypasses root discovery'
    Invoke-Client $Codex @('plugin','marketplace','remove','darkraise') | Out-Null
  } else { Write-Output 'OBSERVED: this Codex CLI rejects direct catalog-file registration; root registration is supported.' }
  Invoke-Client $Codex @('plugin','marketplace','add',$market,'--json') | Out-Null
} finally {
  [IO.File]::WriteAllText((Join-Path $fixtureParent 'latest-evidence.json'), (($evidence | ConvertTo-Json -Depth 35) + "`n"))
  foreach ($entry in $previousEnvironment.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
  $resolvedFixture = [IO.Path]::GetFullPath($fixture)
  if ($resolvedFixture.StartsWith($fixtureParent + '\', [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
