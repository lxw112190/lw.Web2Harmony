[CmdletBinding()]
param([string]$Archive)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$target=Join-Path $root 'toolchain/jdk-21'
if (Test-Path -LiteralPath (Join-Path $target 'bin/javac.exe')) {
    Write-Host "Local JDK already available: $target"
    exit 0
}
if (Test-Path -LiteralPath $target) { throw 'Incomplete JDK directory exists; preserve it and use a new application directory.' }
# Pinned Microsoft Build of OpenJDK. Keep its legal/LICENSE/NOTICE files.
# SHA256 source: https://aka.ms/download-jdk/microsoft-jdk-21.0.12.1-windows-x64.zip.sha256sum.txt
$name='microsoft-jdk-21.0.12.1-windows-x64.zip'
$sha='192441a9d27da813bada974bb88b4cf64d37a9589ed37f204374d411ca5ce07f'
$url='https://aka.ms/download-jdk/'+$name
if (-not $Archive) {
    $downloads=Join-Path $root 'build/downloads'
    New-Item -ItemType Directory -Force -Path $downloads | Out-Null
    $Archive=Join-Path $downloads $name
    if (-not (Test-Path -LiteralPath $Archive)) {
        & curl.exe --proto '=https' --proto-redir '=https' -L --fail --retry 3 --connect-timeout 30 --max-time 900 --silent --show-error -o $Archive $url
        if ($LASTEXITCODE -ne 0) { throw 'JDK download failed; retry with a verified local archive via -Archive.' }
    }
}
$source=(Resolve-Path -LiteralPath $Archive).Path
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $sha) { throw 'Official JDK SHA256 mismatch' }
$staging=Join-Path $root ('build/jdk-import-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $staging | Out-Null
try {
    & tar.exe -xf $source -C $staging
    if ($LASTEXITCODE -ne 0) { throw 'JDK extraction failed' }
    $candidates=@(Get-ChildItem -LiteralPath $staging -Directory | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName 'bin/javac.exe') -PathType Leaf
    })
    if ($candidates.Count -ne 1) { throw 'Expected exactly one JDK root' }
    $release=Get-Content -Raw -LiteralPath (Join-Path $candidates[0].FullName 'release')
    if ($release -notmatch 'JAVA_VERSION="21\.') { throw 'Expected Java 21' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Move-Item -LiteralPath $candidates[0].FullName -Destination $target
    Write-Host "Local JDK ready: $target (no system environment changes)"
} finally {
    $resolved=[IO.Path]::GetFullPath($staging)
    $boundary=[IO.Path]::GetFullPath((Join-Path $root 'build'))+[IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected JDK staging cleanup target' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
