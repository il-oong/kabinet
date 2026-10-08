param(
  [string]$PluginRoot = (Join-Path $env:APPDATA 'SketchUp/SketchUp 2022/SketchUp/Plugins')
)
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path $PSScriptRoot -Parent
$resolvedRoot = (Resolve-Path -LiteralPath $PluginRoot).Path
if ((Get-Item -LiteralPath $resolvedRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) {
  throw 'Plugin root must not be a linked directory.'
}
$parent = Split-Path $resolvedRoot -Parent
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$stage = Join-Path $parent ('kabinet-stage-' + $stamp)
$backup = Join-Path $parent ('RemovedPluginsBackup/kabinet-' + $stamp)
$files = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ep_release_files.txt') | Where-Object { $_ }
New-Item -ItemType Directory -Path $stage | Out-Null
foreach ($relative in $files) {
  if ($relative -match '\.\.' -or [IO.Path]::IsPathRooted($relative)) { throw 'Invalid release manifest' }
  $from = Join-Path $sourceRoot $relative
  $to = Join-Path $stage $relative
  New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force | Out-Null
  Copy-Item -LiteralPath $from -Destination $to
  if ((Get-FileHash -LiteralPath $from).Hash -ne (Get-FileHash -LiteralPath $to).Hash) { throw 'Staging verification failed' }
}
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$movedOld = @()
$movedNew = @()
try {
  foreach ($name in @('kabinet', 'kabinet_loader.rb')) {
    $target = [IO.Path]::GetFullPath((Join-Path $resolvedRoot $name))
    if ((Split-Path $target -Parent) -ne $resolvedRoot) { throw 'Target outside plugin directory' }
    if (Test-Path -LiteralPath $target) {
      Move-Item -LiteralPath $target -Destination (Join-Path $backup $name)
      $movedOld += $name
    }
    Move-Item -LiteralPath (Join-Path $stage $name) -Destination $target
    $movedNew += $name
  }
  foreach ($relative in $files) {
    if ((Get-FileHash -LiteralPath (Join-Path $sourceRoot $relative)).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $resolvedRoot $relative)).Hash) { throw 'Installed file verification failed' }
  }
} catch {
  foreach ($name in $movedNew) {
    $target = Join-Path $resolvedRoot $name
    if ((Split-Path ([IO.Path]::GetFullPath($target)) -Parent) -ne $resolvedRoot) { throw 'Unsafe rollback target' }
    Move-Item -LiteralPath $target -Destination (Join-Path $backup ('failed-new-' + $name))
  }
  foreach ($name in $movedOld) {
    Move-Item -LiteralPath (Join-Path $backup $name) -Destination (Join-Path $resolvedRoot $name)
  }
  throw
}
[PSCustomObject]@{ Installed=$resolvedRoot; Backup=$backup; VerifiedFiles=$files.Count; RestartRequired=$true } | ConvertTo-Json
