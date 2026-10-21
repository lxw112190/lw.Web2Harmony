[CmdletBinding()]
param(
    [ValidateSet('hello','remote')][string]$Sample='hello',
    [string]$SigningConfiguration,
    [switch]$SkipDesktopBuild
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $root
try {
    if (-not $SkipDesktopBuild) {
        & "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/build-desktop.ps1"
        if ($LASTEXITCODE -ne 0) { throw 'Desktop build/tests failed' }
    }
    $cli=Join-Path $root 'build/Release/lw.Web2Harmony.exe'
    if (-not (Test-Path -LiteralPath $cli)) { throw 'Build the desktop tools first.' }
    $export=Join-Path $root ('build/local/'+$Sample+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    & $cli export (Join-Path $root "samples/$Sample/project.json") $export
    if ($LASTEXITCODE -ne 0) { throw 'Project export failed' }
    $arguments=@{ProjectDirectory=$export;ToolchainDirectory=(Join-Path $root 'toolchain/command-line-tools');JavaHome=(Join-Path $root 'toolchain/jdk-21')}
    if ($SigningConfiguration) { $arguments.SigningConfiguration=$SigningConfiguration }
    & "$PSScriptRoot/build-hap.ps1" @arguments
    Write-Host "Local sample output: $export/dist"
} finally { Pop-Location }
