[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectDirectory,
    [Parameter(Mandatory=$true)][string]$ToolchainDirectory,
    [Parameter(Mandatory=$true)][string]$JavaHome,
    [string]$SigningConfiguration
)
$ErrorActionPreference = 'Stop'
$applicationRoot = Split-Path -Parent $PSScriptRoot
$project = [IO.Path]::GetFullPath($ProjectDirectory)
$tools = [IO.Path]::GetFullPath($ToolchainDirectory)
$jdk = [IO.Path]::GetFullPath($JavaHome)
$log = Join-Path $applicationRoot 'logs/hap-build.log'
$utf8 = [Text.UTF8Encoding]::new($false)
$stage = 'preflight'
$secretValues = @()
function Write-BuildLog([string]$Text) {
    foreach ($secret in $script:secretValues) {
        if ($secret) { $Text = $Text.Replace($secret,'[redacted]') }
    }
    $line = [DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff zzz') + " [$script:stage] $Text"
    Write-Host $line
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $log) | Out-Null
        if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 2MB) {
            if (Test-Path -LiteralPath "$log.5") { Remove-Item -LiteralPath "$log.5" -Force }
            for ($i=4; $i -ge 1; $i--) {
                if (Test-Path -LiteralPath "$log.$i") { Move-Item -LiteralPath "$log.$i" -Destination "$log.$($i+1)" -Force }
            }
            Move-Item -LiteralPath $log -Destination "$log.1" -Force
        }
        [IO.File]::AppendAllText($log,$line+[Environment]::NewLine,$utf8)
    } catch { [Diagnostics.Debug]::WriteLine($_.Exception.Message) }
}
function Require-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file missing: $Path" }
}
function Invoke-Tool([string]$File,[string[]]$Arguments) {
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $File @Arguments 2>&1 | ForEach-Object { Write-BuildLog $_.ToString() }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw "Tool failed with exit code $code : $([IO.Path]::GetFileName($File))" }
}
$profilePath = Join-Path $project 'build-profile.json5'
$originalProfile = $null
$savedAcl = $null
$previousEnvironment = @{}
$locationPushed = $false
try {
    Write-BuildLog "Preflight; project=$project; toolchain=$tools; javaHome=$jdk"
    foreach ($directory in @($project,$tools,$jdk)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Required directory missing: $directory" }
    }
    Require-File (Join-Path $project 'lw-export.json')
    if (Test-Path -LiteralPath (Join-Path $project '.lw-export-incomplete')) { throw 'Project export did not complete; export to a new empty directory.' }
    Require-File $profilePath
    Require-File (Join-Path $tools 'bin/hvigorw.bat')
    Require-File (Join-Path $tools 'bin/ohpm.bat')
    Require-File (Join-Path $tools 'tool/node/node.exe')
    Require-File (Join-Path $jdk 'bin/java.exe')
    if (-not (Test-Path -LiteralPath (Join-Path $tools 'sdk') -PathType Container)) { throw 'HarmonyOS SDK missing under command-line-tools/sdk' }
    foreach ($name in @('JAVA_HOME','NODE_HOME','DEVECO_SDK_HOME','PATH')) {
        $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
    }
    $env:JAVA_HOME = $jdk
    $env:NODE_HOME = Join-Path $tools 'tool/node'
    $env:DEVECO_SDK_HOME = Join-Path $tools 'sdk'
    $env:PATH = (Join-Path $tools 'bin')+';'+$env:NODE_HOME+';'+(Join-Path $jdk 'bin')+';'+$previousEnvironment['PATH']
    $sdkProperty = $env:DEVECO_SDK_HOME.Replace('\','/')
    [IO.File]::WriteAllText((Join-Path $project 'local.properties'),"sdk.dir=$sdkProperty"+[Environment]::NewLine,$utf8)
    $export = Get-Content -Raw -LiteralPath (Join-Path $project 'lw-export.json') | ConvertFrom-Json
    $originalProfile = [IO.File]::ReadAllText($profilePath)
    $profile = $originalProfile | ConvertFrom-Json
    $signed = -not [string]::IsNullOrWhiteSpace($SigningConfiguration)
    if ($signed) {
        $stage = 'configure-signing'
        $signPath = (Resolve-Path -LiteralPath $SigningConfiguration).Path
        $sign = Get-Content -Raw -LiteralPath $signPath | ConvertFrom-Json
        foreach ($field in @('bundleName','storeFile','keyAlias','certpath','profile')) {
            if ([string]::IsNullOrWhiteSpace([string]$sign.$field)) { throw "Signing configuration is missing $field" }
        }
        if ($sign.bundleName -ne $export.bundleName) { throw 'Signing configuration bundleName does not match exported application' }
        if (-not $env:HARMONY_STORE_PASSWORD -or -not $env:HARMONY_KEY_PASSWORD) {
            throw 'Set HARMONY_STORE_PASSWORD and HARMONY_KEY_PASSWORD in the environment; passwords must not be stored in project JSON.'
        }
        $secretValues = @($env:HARMONY_STORE_PASSWORD,$env:HARMONY_KEY_PASSWORD)
        $base = Split-Path -Parent $signPath
        $paths = @{}
        foreach ($field in @('storeFile','certpath','profile')) {
            $paths[$field] = [IO.Path]::GetFullPath((Join-Path $base $sign.$field))
            Require-File $paths[$field]
        }
        $profile.app.signingConfigs = @(@{
            name='local'; type='HarmonyOS'; material=@{
                storeFile=$paths.storeFile; storePassword=$env:HARMONY_STORE_PASSWORD
                keyAlias=$sign.keyAlias; keyPassword=$env:HARMONY_KEY_PASSWORD
                certpath=$paths.certpath; profile=$paths.profile; signAlg='SHA256withECDSA'
            }
        })
        $profile.app.products[0] | Add-Member -NotePropertyName signingConfig -NotePropertyValue 'local' -Force
        # Restrict the temporary signing-bearing profile to the current Windows user.
        $savedAcl = Get-Acl -LiteralPath $profilePath
        $restrictedAcl = New-Object Security.AccessControl.FileSecurity
        $restrictedAcl.SetAccessRuleProtection($true,$false)
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $restrictedAcl.SetOwner($sid)
        $restrictedAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','Allow')))
        Set-Acl -LiteralPath $profilePath -AclObject $restrictedAcl
        [IO.File]::WriteAllText($profilePath,($profile | ConvertTo-Json -Depth 20),$utf8)
    }
    Push-Location -LiteralPath $project
    $locationPushed = $true
    $stage = 'dependencies'
    Write-BuildLog "Building bundle=$($export.bundleName); signed=$signed"
    Invoke-Tool (Join-Path $tools 'bin/ohpm.bat') @('install')
    $stage = 'assemble-hap'
    Invoke-Tool (Join-Path $tools 'bin/hvigorw.bat') @('--mode','module','-p','product=default','-p','module=entry@default','-p','buildMode=debug','assembleHap','--no-daemon')
    $stage = 'verify-hap'
    $suffix = if ($signed) {'-signed.hap'} else {'-unsigned.hap'}
    $haps = @(Get-ChildItem -LiteralPath (Join-Path $project 'entry/build') -Recurse -Filter '*.hap' -File |
        Where-Object { $_.Name.EndsWith($suffix,[StringComparison]::OrdinalIgnoreCase) })
    if ($haps.Count -ne 1) { throw "Expected exactly one $suffix output, found $($haps.Count)" }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($haps[0].FullName)
    try {
        $names = @($archive.Entries | ForEach-Object FullName)
        if ('module.json' -notin $names -or 'ets/modules.abc' -notin $names) { throw 'HAP is missing module.json or ets/modules.abc' }
        if ($export.mode -eq 'local' -and -not ($names | Where-Object { $_ -like 'resources/rawfile/www/*' })) { throw 'Local HAP is missing Web assets' }
        if ($export.mode -eq 'remote' -and ($names | Where-Object { $_ -like 'resources/rawfile/www/*' })) { throw 'Remote HAP unexpectedly contains local Web assets' }
        if (@($names | Select-Object -Unique).Count -ne $names.Count -or ($names | Where-Object { $_.Contains('\') })) { throw 'HAP contains duplicate or noncanonical entries' }
        foreach ($line in (Get-Content -LiteralPath (Join-Path $project 'WEB-SHA256SUMS.txt') -Encoding UTF8)) {
            if ($line -notmatch '^([a-f0-9]{64})  (entry/src/main/resources/rawfile/.+)$') { throw 'Invalid Web asset checksum manifest' }
            $expectedHash=$Matches[1]
            $entryName=$Matches[2].Substring('entry/src/main/'.Length)
            $entry=$archive.GetEntry($entryName)
            if ($null -eq $entry) { throw "HAP is missing Web asset: $entryName" }
            $stream=$entry.Open()
            $sha=[Security.Cryptography.SHA256]::Create()
            try { $actualHash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
            finally { $sha.Dispose(); $stream.Dispose() }
            if ($actualHash -ne $expectedHash) { throw "HAP Web asset bytes changed: $entryName" }
        }
        if ($signed) {
            $stage = 'verify-signature'
            $signers = @(Get-ChildItem -LiteralPath (Join-Path $tools 'sdk') -Filter 'hap-sign-tool.jar' -File -Recurse)
            if ($signers.Count -eq 0) { throw 'hap-sign-tool.jar missing; refusing to label an unverified package as signed' }
            Invoke-Tool (Join-Path $jdk 'bin/java.exe') @('-jar',$signers[0].FullName,'verify-app','-inFile',$haps[0].FullName)
        }
    } finally { $archive.Dispose() }
    $stage = 'publish'
    $output = Join-Path $project 'dist'
    New-Item -ItemType Directory -Force -Path $output | Out-Null
    $artifact = Join-Path $output ($export.bundleName+$suffix)
    Copy-Item -LiteralPath $haps[0].FullName -Destination $artifact -Force
    $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText("$artifact.sha256","$hash  $([IO.Path]::GetFileName($artifact))"+[Environment]::NewLine,$utf8)
    $metadata = @{schemaVersion=1;generatorVersion=$export.generatorVersion;bundleName=$export.bundleName;mode=$export.mode;signed=$signed;hapSha256=$hash;buildTimeUtc=[DateTime]::UtcNow.ToString('o')}
    [IO.File]::WriteAllText("$artifact.release.json",($metadata|ConvertTo-Json),$utf8)
    Write-BuildLog "HAP ready: $artifact; SHA256=$hash"
} catch {
    Write-BuildLog "FAILED: $($_.Exception.Message)"
    throw
} finally {
    if ($locationPushed) { Pop-Location }
    if ($null -ne $originalProfile) {
        [IO.File]::WriteAllText($profilePath,$originalProfile,$utf8)
        if ($null -ne $savedAcl) { Set-Acl -LiteralPath $profilePath -AclObject $savedAcl }
    }
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name,$previousEnvironment[$name],'Process')
    }
}
