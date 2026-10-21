[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Archive,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$Sha256,
    [switch]$AcceptHuaweiLicense
)
$ErrorActionPreference='Stop'
if (-not $AcceptHuaweiLicense) { throw 'Read and accept the official Huawei toolchain license before importing with -AcceptHuaweiLicense.' }
$root=Split-Path -Parent $PSScriptRoot
$target=Join-Path $root 'toolchain/command-line-tools'
if (Test-Path -LiteralPath $target) { throw 'Toolchain already exists; select a new application directory for another version.' }
$source=(Resolve-Path -LiteralPath $Archive).Path
$actual=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
if ($actual -ne $Sha256) { throw 'Official toolchain archive SHA256 mismatch' }
$lock=Get-Content -Raw -LiteralPath (Join-Path $root 'toolchain.lock.json') | ConvertFrom-Json
if ($actual -ne $lock.commandLineToolsSha256) { throw 'Archive does not match the project-pinned CLT SHA256' }
$staging=Join-Path $root ('build/toolchain-import-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $staging | Out-Null
try {
    & tar.exe -xf $source -C $staging
    if ($LASTEXITCODE -ne 0) { throw 'Toolchain extraction failed' }
    # CLT contains both bin/hvigorw.bat and hvigor/bin/hvigorw.bat.
    # Identify a complete toolchain root, not an arbitrary nested launcher.
    $candidates=@(Get-ChildItem -LiteralPath $staging -Recurse -Filter hvigorw.bat -File |
        Where-Object { $_.Directory.Name -eq 'bin' -and
            (Test-Path -LiteralPath (Join-Path $_.Directory.Parent.FullName 'bin/ohpm.bat') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $_.Directory.Parent.FullName 'tool/node/node.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $_.Directory.Parent.FullName 'sdk/default/sdk-pkg.json') -PathType Leaf) })
    if ($candidates.Count -ne 1) { throw 'Expected exactly one complete command-line-tools root (bin + tool/node + sdk/default).' }
    $tools=$candidates[0].Directory.Parent.FullName
    foreach ($file in @('bin/ohpm.bat','tool/node/node.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $tools $file) -PathType Leaf)) { throw "Toolchain missing $file" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $tools 'sdk') -PathType Container)) { throw 'Toolchain SDK missing' }
    $version=Get-Content -Raw -LiteralPath (Join-Path $tools 'version.txt')
    if ($version -notmatch ('(?m)^# Version: '+[regex]::Escape($lock.commandLineToolsVersion)+'\s*$')) { throw 'Unexpected Command Line Tools version' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Move-Item -LiteralPath $tools -Destination $target
    Write-Host "Toolchain imported: $target"
} finally {
    $resolved=[IO.Path]::GetFullPath($staging)
    $boundary=[IO.Path]::GetFullPath((Join-Path $root 'build'))+[IO.Path]::DirectorySeparatorChar
    if ($resolved.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
