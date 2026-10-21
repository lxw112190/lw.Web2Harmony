param([Parameter(Mandatory=$true)][string]$RepositoryRoot)
$ErrorActionPreference='Stop'
$work=Join-Path $RepositoryRoot ('build/signing-test-'+[guid]::NewGuid().ToString('N'))
$password='test-only-'+[guid]::NewGuid().ToString('N')
# Mock only interactive input; exercise the actual import/ACL/DPAPI code.
function Read-Host { param([string]$Prompt,[switch]$AsSecureString) ConvertTo-SecureString $password -AsPlainText -Force }
try {
    New-Item -ItemType Directory -Force -Path "$work/tools","$work/input" | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'tools/configure-signing.ps1') -Destination "$work/tools/configure-signing.ps1"
    # These are inert fixture bytes, not real certificates or signing identities.
    foreach($name in @('store.p12','cert.cer','profile.p7b')){[IO.File]::WriteAllBytes("$work/input/$name",[byte[]](1,2,3,4))}
    $arguments=@{BundleName='com.lw.signingtest';StoreFile="$work/input/store.p12";Certificate="$work/input/cert.cer";Profile="$work/input/profile.p7b";KeyAlias='test-alias'}
    & "$work/tools/configure-signing.ps1" @arguments
    $directory="$work/signing/com.lw.signingtest"
    $json=[IO.File]::ReadAllText("$directory/credentials.dpapi.json")
    if($json.Contains($password)){throw 'Signing password was stored as plaintext'}
    $credentials=$json|ConvertFrom-Json
    foreach($field in @('storePassword','keyPassword')){
        $secure=ConvertTo-SecureString $credentials.$field
        $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try{if([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) -ne $password){throw 'DPAPI round-trip failed'}}
        finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer);$secure.Dispose()}
    }
    $acl=Get-Acl -LiteralPath $directory
    if(-not $acl.AreAccessRulesProtected){throw 'Private signing directory inherits access rules'}
    $config=Get-Content -Raw -LiteralPath "$directory/signing.local.json"|ConvertFrom-Json
    if($config.bundleName -ne 'com.lw.signingtest' -or $config.PSObject.Properties.Name -contains 'password'){throw 'Unexpected signing configuration'}
    $rejected=$false
    try{& "$work/tools/configure-signing.ps1" @arguments}catch{$rejected=$true}
    if(-not $rejected){throw 'Existing signing identity was overwritten'}
    $arguments.BundleName='../unsafe'
    $rejected=$false
    try{& "$work/tools/configure-signing.ps1" @arguments}catch{$rejected=$true}
    if(-not $rejected){throw 'Bundle traversal was accepted'}
    Write-Host 'Signing import, current-user DPAPI, ACL, no-overwrite and traversal tests passed (fixture data only).'
} finally {
    $boundary=[IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'build'))+[IO.Path]::DirectorySeparatorChar
    $resolved=[IO.Path]::GetFullPath($work)
    if(-not $resolved.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected signing test cleanup path'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
