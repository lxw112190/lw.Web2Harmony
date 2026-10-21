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
$staging=Join-Path $root ('build/toolchain-import-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $staging | Out-Null
try {
    & tar.exe -xf $source -C $staging
    if ($LASTEXITCODE -ne 0) { throw 'Toolchain extraction failed' }
    $candidates=@(Get-ChildItem -LiteralPath $staging -Recurse -Filter hvigorw.bat -File |
        Where-Object { $_.Directory.Name -eq 'bin' })
    if ($candidates.Count -ne 1) { throw 'Expected one command-line-tools/bin/hvigorw.bat' }
    $tools=$candidates[0].Directory.Parent.FullName
    foreach ($file in @('bin/ohpm.bat','tool/node/node.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $tools $file) -PathType Leaf)) { throw "Toolchain missing $file" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $tools 'sdk') -PathType Container)) { throw 'Toolchain SDK missing' }
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
