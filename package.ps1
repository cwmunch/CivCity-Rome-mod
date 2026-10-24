# Builds release\CivCityFix-<version>.zip from this folder.
#   pwsh -File package.ps1 [-SkipBuild]
param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$version = [regex]::Match((Get-Content "$root\src\version.h" -Raw), 'CCF_VERSION_STR\s+"([^"]+)"').Groups[1].Value
if (-not $version) { throw 'CCF_VERSION_STR not found in src\version.h' }

if (-not $SkipBuild) {
    cmd /c "`"$root\build.cmd`""
    if ($LASTEXITCODE -ne 0) { throw 'build.cmd failed' }
}

# DXVK is not kept in git: fetch the official release once and check its hash.
$dxvk = "$root\third_party\dxvk-3.1.1\d3d9.dll"
if (-not (Test-Path $dxvk)) {
    $url = 'https://github.com/doitsujin/dxvk/releases/download/v3.1.1/dxvk-3.1.1.tar.gz'
    $sha = '40565B4A724AADC4433FA4E010B4B23916D9B1F1BAEEE64E17186DB94F54E608'
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('civcityfix-dxvk-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $tmp | Out-Null
    try {
        "Downloading $url"
        Invoke-WebRequest $url -OutFile "$tmp\dxvk.tar.gz" -UseBasicParsing
        if ((Get-FileHash "$tmp\dxvk.tar.gz" -Algorithm SHA256).Hash -ne $sha) { throw 'DXVK download does not match the expected SHA-256' }
        tar -xzf "$tmp\dxvk.tar.gz" -C $tmp
        Copy-Item "$tmp\dxvk-3.1.1\x32\d3d9.dll" $dxvk
    } finally {
        Remove-Item $tmp -Recurse -Force
    }
}

$name  = "CivCityFix-$version"
$rel   = Join-Path $root 'release'
$stage = Join-Path $rel $name
$zip   = Join-Path $rel "$name.zip"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force $stage, "$stage\source\src" | Out-Null

Copy-Item "$root\package\*" $stage -Recurse
Copy-Item "$root\dist\d3d9.dll" "$stage\files\d3d9.dll"
Copy-Item "$root\third_party\dxvk-3.1.1\d3d9.dll" "$stage\files\dxvk_d3d9.dll"
Copy-Item "$root\src\*" "$stage\source\src"
Copy-Item "$root\build.cmd" "$stage\source\build.cmd"
Set-Content "$stage\VERSION.txt" $version -NoNewline -Encoding ascii

# Text files: version placeholder, CRLF line endings (cmd.exe needs them), UTF-8 without BOM.
# Windows PowerShell 5.1 reads BOM-less scripts as ANSI, so scripts must stay ASCII.
$utf8 = New-Object System.Text.UTF8Encoding($false)
Get-ChildItem $stage -Recurse -File -Include *.cmd, *.txt, *.ps1, *.ini, *.conf, *.h, *.rc, *.cpp | ForEach-Object {
    $text = [IO.File]::ReadAllText($_.FullName).Replace('__VERSION__', $version)
    if ($_.Extension -in '.ps1', '.cmd' -and $text -match '[^\x00-\x7F]') { throw "Non-ASCII character in $($_.Name)" }
    $text = $text -replace "`r`n", "`n" -replace "`n", "`r`n"
    [IO.File]::WriteAllText($_.FullName, $text, $utf8)
}

if (Test-Path $zip) { Remove-Item $zip }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)

$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
Set-Content "$zip.sha256.txt" "$hash  $name.zip" -Encoding ascii
"Built $zip"
"SHA-256 $hash"
