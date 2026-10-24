# CivCityFix uninstaller
#
#   Uninstall.cmd              remove everything and restore what was there before
#   Uninstall.cmd -KeepDxvk    keep plain DXVK (crash fix only, no borderless window)
param(
    [string]$GamePath,
    [switch]$KeepDxvk
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$pkg = Split-Path $PSScriptRoot -Parent
Write-Host 'CivCityFix uninstaller' -ForegroundColor Cyan

$game = Find-GameFolder $GamePath $pkg
if (-not $game) {
    $game = Read-Host 'Could not find CivCity: Rome. Paste the game folder (the one with "CivCity Rome.exe")'
    $game = Find-GameFolder $game $pkg
    if (-not $game) { throw 'CivCity Rome.exe was not found in that folder.' }
}
Write-Host "Game folder: $game"
Assert-GameClosed
Assert-Writable $game

$manifestPath = Join-Path $game $ManifestName
$hasManifest = Test-Path -LiteralPath $manifestPath
$m = Read-Manifest $manifestPath

$names = $m.installed
if (-not $hasManifest) { $names = @('d3d9.dll', 'dxvk_d3d9.dll', 'dxvk.conf', 'CivCityFix.ini') }

foreach ($name in $names) {
    $p = Join-Path $game $name
    if (-not (Test-Path -LiteralPath $p)) { continue }
    # Without a manifest, only remove files that are recognisably ours.
    $ours = $true
    if (-not $hasManifest) {
        if ($name -eq 'd3d9.dll')  { $ours = Test-FileHasMarker $p 'CivCityFix' }
        if ($name -eq 'dxvk.conf') { $ours = Test-FileHasMarker $p 'installed by CivCityFix' }
    }
    if ($ours) { Remove-Item -LiteralPath $p; Write-Host "  removed $name" }
}

# Put back whatever was there before the fix was installed.
$backups = @{}
foreach ($k in $m.backups.Keys) { $backups[$k] = $m.backups[$k] }
if (-not $hasManifest) {
    Get-ChildItem -LiteralPath $game -Filter "*$BackupSuffix" | ForEach-Object {
        $backups[$_.Name.Substring(0, $_.Name.Length - $BackupSuffix.Length)] = $_.Name
    }
}
foreach ($name in $backups.Keys) {
    $bak = Join-Path $game $backups[$name]
    if (Test-Path -LiteralPath $bak) {
        Move-Item -LiteralPath $bak (Join-Path $game $name) -Force
        Write-Host "  restored $name"
    }
}

if ($KeepDxvk) {
    $d3d9 = Join-Path $game 'd3d9.dll'
    if (-not (Test-Path -LiteralPath $d3d9)) {
        Copy-Item (Join-Path $pkg 'files\dxvk_d3d9.dll') $d3d9
        Write-Host '  kept DXVK as d3d9.dll (crash fix only)'
    }
    $conf = Join-Path $game 'dxvk.conf'
    if (-not (Test-Path -LiteralPath $conf)) { Copy-Item (Join-Path $pkg 'files\dxvk.conf') $conf }
}

foreach ($log in @('CivCityFix.log', 'CivCity Rome_d3d9.log')) {
    if ($KeepDxvk -and $log -eq 'CivCity Rome_d3d9.log') { continue }
    $p = Join-Path $game $log
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p }
}

# Graphics settings: restore the backup, or remove the file if the installer created it
# (the game then writes its own defaults on the next start).
$settings = $m.settings.path
if ($settings) {
    if ($m.settings.backup -and (Test-Path -LiteralPath $m.settings.backup)) {
        Move-Item -LiteralPath $m.settings.backup $settings -Force
        Write-Host '  restored graphics settings'
    } elseif ($m.settings.created -and (Test-Path -LiteralPath $settings)) {
        Remove-Item -LiteralPath $settings
        Write-Host '  removed graphics settings created by the installer'
    }
}

if ($hasManifest) { Remove-Item -LiteralPath $manifestPath }

Write-Host ''
Write-Host 'CivCityFix removed.' -ForegroundColor Green
if (-not $KeepDxvk) {
    Write-Host 'Note: without the fix the game crashes on startup on most modern PCs.'
}
