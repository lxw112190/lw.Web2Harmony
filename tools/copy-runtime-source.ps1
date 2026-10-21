[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference='Stop'
$source=Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime'
$profile=Get-Content -LiteralPath (Join-Path $source 'build-profile.json5') -Raw -Encoding UTF8 | ConvertFrom-Json
if(@($profile.app.signingConfigs).Count -gt 0){throw 'Base runtime contains signing material/configuration; refusing public packaging.'}
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
foreach($name in @('.gitignore','build-profile.json5','oh-package.json5','hvigorfile.ts','README.md',
    'entry/build-profile.json5','entry/oh-package.json5','entry/hvigorfile.ts')){
    $target=Join-Path $Destination $name
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)|Out-Null
    Copy-Item -LiteralPath (Join-Path $source $name) -Destination $target
}
# Source roots only: never include build/, dist/, .hvigor/, local.properties,
# oh_modules, certificates, profiles or temporary signing configurations.
foreach($directory in @('AppScope','hvigor','entry/src/main')){
    $base=Join-Path $source $directory
    foreach($file in (Get-ChildItem -LiteralPath $base -Recurse -File)){
        if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Runtime source reparse point detected'}
        if($file.Extension -in @('.p12','.pfx','.p7b','.cer','.csr','.key') -or
            $file.Name -in @('signing.local.json','credentials.dpapi.json','.env') -or $file.Name.StartsWith('.env.')){continue}
        $relative=$file.FullName.Substring($source.Length+1)
        $target=Join-Path $Destination $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)|Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
    }
}
