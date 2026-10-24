# CivCityFix installer
#
#   Install.cmd                          auto-detect game folder and resolution
#   Install.cmd -Resolution 1600x1200    pick a resolution yourself
#   Install.cmd -GamePath "D:\Games\CivCity Rome"
param(
    [string]$GamePath,
    [string]$Resolution = 'auto',
    [string]$SettingsFile   # defaults to Documents\CivCity Rome\CivCityRome.GraphicsSettings.xml
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$pkg = Split-Path $PSScriptRoot -Parent
$src = Join-Path $pkg 'files'
$version = (Get-Content (Join-Path $pkg 'VERSION.txt') -Raw).Trim()

Write-Host "CivCityFix $version installer" -ForegroundColor Cyan

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
$manifest = Read-Manifest $manifestPath

# --- game folder files ------------------------------------------------------
function Install-File([string]$from, [string]$name, [string]$ourMarker) {
    $to = Join-Path $game $name
    if ((Test-Path $to) -and -not (Test-FileHasMarker $to $ourMarker)) {
        $bak = "$name$BackupSuffix"
        if (-not (Test-Path (Join-Path $game $bak))) {
            Copy-Item $to (Join-Path $game $bak)
            $manifest.backups[$name] = $bak
            Write-Host "  backed up existing $name -> $bak"
        }
    }
    Copy-Item $from $to -Force
    if ($manifest.installed -notcontains $name) { $manifest.installed += $name }
}

Install-File (Join-Path $src 'd3d9.dll')      'd3d9.dll'      'CivCityFix'
Install-File (Join-Path $src 'dxvk_d3d9.dll') 'dxvk_d3d9.dll' 'DXVK'
Install-File (Join-Path $src 'dxvk.conf')     'dxvk.conf'     'installed by CivCityFix'

$ini = Join-Path $game 'CivCityFix.ini'
if (-not (Test-Path $ini)) { Copy-Item (Join-Path $src 'CivCityFix.ini') $ini }
if ($manifest.installed -notcontains 'CivCityFix.ini') { $manifest.installed += 'CivCityFix.ini' }
Write-Host '  installed d3d9.dll (CivCityFix), dxvk_d3d9.dll (DXVK 3.1.1), dxvk.conf, CivCityFix.ini'

# --- resolution ---------------------------------------------------------------
if ($Resolution -eq 'auto') {
    $mode = Get-AutoMode
} elseif ($Resolution -match '^(\d{3,5})x(\d{3,5})$') {
    $mode = @{ Width = [int]$Matches[1]; Height = [int]$Matches[2] }
    $iniText = Get-Content $ini -Raw
    if ($iniText -notmatch "(?m)^ExtraModes=.*\b$Resolution\b") {
        $iniText = $iniText -replace '(?m)^ExtraModes=(.*)$', "ExtraModes=$Resolution,`$1"
        Set-Content $ini $iniText -NoNewline
    }
} else {
    throw "Resolution must be 'auto' or WIDTHxHEIGHT, e.g. 1920x1440 (got '$Resolution')."
}

if (-not $SettingsFile) { $SettingsFile = Get-DefaultSettingsFile }
if (-not $manifest.settings.path) {
    $manifest.settings.path = $SettingsFile
    if (Test-Path $SettingsFile) {
        $bak = "$SettingsFile$BackupSuffix"
        Copy-Item $SettingsFile $bak -Force
        $manifest.settings.backup = $bak
    } else {
        $manifest.settings.created = $true
    }
}
Set-GameResolution $SettingsFile $mode.Width $mode.Height
Write-Host ("  resolution: {0}x{1} (centered, borderless)" -f $mode.Width, $mode.Height)
if ($mode.Width -gt 1600 -or $mode.Height -gt 1200) {
    Write-Host '  the game''s startup dialog is turned off (it cannot show resolutions above 1600x1200)'
}

$manifest.version = $version
Write-Manifest $manifestPath $manifest

Write-Host ''
Write-Host 'Done. Start CivCity: Rome from Steam as usual.' -ForegroundColor Green
Write-Host 'To remove the fix again, run Uninstall.cmd.'
