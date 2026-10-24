# Shared helpers for install.ps1 / uninstall.ps1 (Windows PowerShell 5.1 compatible).

$GameExe      = 'CivCity Rome.exe'
$ManifestName = 'CivCityFix.install.json'
$BackupSuffix = '.civcityfix-backup'

# Game defaults as written by CivCity Rome on first start; only resolution and the
# startup dialog differ.
$DefaultSettings = @'
<graphicssettings>
	<resolution width="__W__" height="__H__" format="X8R8G8B8" refreshRate="60"/>
	<multiSamples value="0"/>
	<Ansiotropy value="0"/>
	<drawDistance value="1.000000"/>
	<nPatchLevel value="0.000000"/>
	<levelOfDetail value="1.000000"/>
	<modelDetail value="2"/>
	<textureDetail value="1"/>
	<drawGroundShadows enabled="true"/>
	<bloomEnabled enabled="false"/>
	<drawRealTimeShadows enabled="false"/>
	<drawReflections enabled="false"/>
	<drawArrowTrails enabled="false"/>
	<drawParticles enabled="true"/>
	<drawGrass enabled="true"/>
	<earlyCulling enabled="false"/>
	<enhancedWater enabled="false"/>
	<normalMaps enabled="true"/>
	<multipassShaders enabled="false"/>
	<settingsDialog enabled="__DIALOG__"/>
	<shaderVersion value="3.0"/>
	<gfxLevel value="3"/>
	<cloudShadow enabled="true"/>
	<particleLevel value="1"/>
	<snow enabled="true"/>
	<waterSetting value="1"/>
</graphicssettings>
'@

function Find-GameFolder([string]$hint, [string]$pkg) {
    if ($hint) {
        $hint = $hint.Trim().Trim('"')
        if ($hint -and (Test-Path -LiteralPath (Join-Path $hint $GameExe))) { return (Resolve-Path -LiteralPath $hint).Path }
        return $null
    }

    # Package unpacked somewhere inside the game folder?
    $p = $pkg
    while ($p) {
        if (Test-Path -LiteralPath (Join-Path $p $GameExe)) { return $p }
        $p = Split-Path $p -Parent
    }

    # Steam libraries
    $steam = $null
    $k = Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
    if ($k -and $k.SteamPath) { $steam = $k.SteamPath -replace '/', '\' }
    if (-not $steam) {
        $k = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue
        if ($k) { $steam = $k.InstallPath }
    }
    if (-not $steam) { return $null }

    $libs = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
            $libs += ($m.Groups[1].Value -replace '\\\\', '\')
        }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        $g = Join-Path $lib 'steamapps\common\CivCity Rome'
        if (Test-Path -LiteralPath (Join-Path $g $GameExe)) { return $g }
    }
    return $null
}

function Assert-GameClosed {
    if (Get-Process 'CivCity Rome' -ErrorAction SilentlyContinue) {
        throw 'CivCity: Rome is running. Close the game and try again.'
    }
}

function Assert-Writable([string]$dir) {
    $probe = Join-Path $dir ('civcityfix-write-test-' + [guid]::NewGuid().ToString('N'))
    try {
        Set-Content -LiteralPath $probe -Value '' -ErrorAction Stop
        Remove-Item -LiteralPath $probe
    } catch {
        throw "No write access to '$dir'. Right-click the .cmd file and choose 'Run as administrator'."
    }
}

function Read-Manifest([string]$path) {
    $m = @{ version = ''; installed = @(); backups = @{}; settings = @{ path = $null; backup = $null; created = $false } }
    if (Test-Path -LiteralPath $path) {
        $j = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ($j.version) { $m.version = $j.version }
        if ($j.installed) { $m.installed = @($j.installed) }
        if ($j.backups) { foreach ($p in $j.backups.PSObject.Properties) { $m.backups[$p.Name] = $p.Value } }
        if ($j.settings) {
            $m.settings.path = $j.settings.path
            $m.settings.backup = $j.settings.backup
            $m.settings.created = [bool]$j.settings.created
        }
    }
    return $m
}

function Write-Manifest([string]$path, $m) {
    $m | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8
}

# True if the file contains the marker as ASCII or UTF-16 text.
function Test-FileHasMarker([string]$path, [string]$marker) {
    $latin1 = [Text.Encoding]::GetEncoding(28591)
    $s = $latin1.GetString([IO.File]::ReadAllBytes($path))
    if ($s.Contains($marker)) { return $true }
    return $s.Contains($latin1.GetString([Text.Encoding]::Unicode.GetBytes($marker)))
}

# 4:3 mode that fills the primary monitor's height (or its width on narrow screens).
# Must match AutoMode() in CivCityFix.cpp.
function Get-AutoMode {
    if (-not ('CcfDisplay' -as [type])) {
        Add-Type @'
using System; using System.Runtime.InteropServices;
public static class CcfDisplay {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
    public short dmLogPixels;
    public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency, dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  public static int[] Current() {
    var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    if (!EnumDisplaySettings(null, -1, ref dm)) return new int[] { 1920, 1080 };
    return new int[] { dm.dmPelsWidth, dm.dmPelsHeight };
  }
}
'@
    }
    $cur = [CcfDisplay]::Current()
    $mw = $cur[0]; $mh = $cur[1]
    $h = $mh
    $w = [int][math]::Floor($h * 4 / 3); $w -= $w % 8
    if ($w -gt $mw) {
        $w = $mw - ($mw % 8)
        $h = [int][math]::Floor($w * 3 / 4); $h -= $h % 8
    }
    return @{ Width = $w; Height = $h }
}

function Get-DefaultSettingsFile {
    Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CivCity Rome\CivCityRome.GraphicsSettings.xml'
}

# The game's startup dialog lists at most 1600x1200 and would overwrite anything larger,
# so it is turned off for bigger resolutions.
function Set-GameResolution([string]$file, [int]$w, [int]$h) {
    $dialog = 'false'
    if ($w -le 1600 -and $h -le 1200) { $dialog = 'true' }
    if (Test-Path -LiteralPath $file) {
        [xml]$x = Get-Content -LiteralPath $file -Raw
        $r = $x.graphicssettings.resolution
        $r.SetAttribute('width', "$w")
        $r.SetAttribute('height', "$h")
        $r.SetAttribute('refreshRate', '60')
        $d = $x.graphicssettings.SelectSingleNode('settingsDialog')
        if (-not $d) {
            $d = $x.CreateElement('settingsDialog')
            [void]$x.graphicssettings.AppendChild($d)
        }
        $d.SetAttribute('enabled', $dialog)
        $x.Save($file)
    } else {
        New-Item -ItemType Directory -Force (Split-Path $file -Parent) | Out-Null
        $text = $DefaultSettings -replace '__W__', "$w" -replace '__H__', "$h" -replace '__DIALOG__', $dialog
        Set-Content -LiteralPath $file -Value $text -Encoding ASCII
    }
}
