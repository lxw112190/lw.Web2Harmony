[CmdletBinding()]
param(
    [string]$SigningConfiguration,
    [string]$ToolchainDirectory,
    [string]$JavaHome
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$runtime=Join-Path $root 'runtime'
if(-not $ToolchainDirectory){$ToolchainDirectory=Join-Path $root 'toolchain/command-line-tools'}
if(-not $JavaHome){$JavaHome=Join-Path $root 'toolchain/jdk-21'}
$utf8=[Text.UTF8Encoding]::new($false)
$app=(Get-Content -LiteralPath (Join-Path $runtime 'AppScope/app.json5') -Raw -Encoding UTF8 | ConvertFrom-Json).app
$lock=Get-Content -LiteralPath (Join-Path $root 'toolchain.lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$web=Join-Path $runtime 'entry/src/main/resources/rawfile/www'
$files=@(Get-ChildItem -LiteralPath $web -Recurse -File | Sort-Object FullName)
$checks=@(); $mappings=@()
foreach($file in $files){
    if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse points are not allowed in runtime Web assets'}
    $relative=$file.FullName.Substring($web.Length+1).Replace('\','/')
    $stream=[IO.File]::OpenRead($file.FullName);$sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose();$stream.Dispose()}
    $checks+=$hash+'  entry/src/main/resources/rawfile/www/'+$relative
    $url=('/'+$relative)|ConvertTo-Json -Compress
    $raw=('www/'+$relative)|ConvertTo-Json -Compress
    $mappings+='  ['+$url+', '+$raw+'],'
}
$template=[IO.File]::ReadAllText((Join-Path $root 'packer/templates/entry/src/main/ets/common/WebAssets.ets.in'))
[IO.File]::WriteAllText((Join-Path $runtime 'entry/src/main/ets/common/WebAssets.ets'),$template.Replace('{{ASSET_MAP}}',($mappings -join "`n")),$utf8)
[IO.File]::WriteAllLines((Join-Path $runtime 'WEB-SHA256SUMS.txt'),[string[]]$checks,$utf8)
$metadata=@{schemaVersion=1;generatorVersion=$lock.productVersion;bundleName=$app.bundleName;mode='local';webFileCount=$files.Count}
[IO.File]::WriteAllText((Join-Path $runtime 'lw-export.json'),($metadata|ConvertTo-Json),$utf8)
if(-not $SigningConfiguration){
    $candidate=Join-Path $root ('signing/'+$app.bundleName+'/signing.local.json')
    if(Test-Path -LiteralPath $candidate -PathType Leaf){$SigningConfiguration=$candidate}
}
$arguments=@{ProjectDirectory=$runtime;ToolchainDirectory=$ToolchainDirectory;JavaHome=$JavaHome}
if($SigningConfiguration){$arguments.SigningConfiguration=$SigningConfiguration}
& "$PSScriptRoot/build-hap.ps1" @arguments
Write-Host "Base runtime output: $runtime/dist"
