[CmdletBinding(DefaultParameterSetName='Existing')]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$')][string]$BundleName,
    [Parameter(Mandatory=$true,ParameterSetName='Existing')][string]$StoreFile,
    [Parameter(Mandatory=$true)][string]$Certificate,
    [Parameter(Mandatory=$true)][string]$Profile,
    [Parameter(Mandatory=$true,ParameterSetName='Existing')][string]$KeyAlias,
    [Parameter(Mandatory=$true,ParameterSetName='Request')][string]$RequestDirectory
)
. ([IO.Path]::Combine($PSScriptRoot,'initialize-powershell.ps1'))
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Windows DPAPI is required for local credential storage'}
$root=Split-Path -Parent $PSScriptRoot
$target=Join-Path $root ('signing/'+$BundleName)
if(Test-Path -LiteralPath $target){throw 'Signing directory already exists; back it up outside this project before replacing the configuration.'}
if($PSCmdlet.ParameterSetName -eq 'Request'){
    $requestRoot=(Resolve-Path -LiteralPath $RequestDirectory).Path
    $request=Get-Content -LiteralPath (Join-Path $requestRoot 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($request.schemaVersion -ne 1 -or $request.bundleName -ne $BundleName -or
        $request.storeFile -ne 'developer.p12' -or $request.csrFile -ne 'developer.csr' -or
        [string]::IsNullOrWhiteSpace($request.keyAlias)){throw 'Signing request is incomplete or does not match the application'}
    $StoreFile=Join-Path $requestRoot 'developer.p12'
    $KeyAlias=$request.keyAlias
    foreach($pair in @(@('developer.p12','storeSha256'),@('developer.csr','csrSha256'))){
        $stream=[IO.File]::OpenRead((Join-Path $requestRoot $pair[0]));$sha=[Security.Cryptography.SHA256]::Create()
        try{$hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}
        finally{$sha.Dispose();$stream.Dispose()}
        if($hash -ne $request.($pair[1])){throw 'Signing request files changed; refusing to import a different identity'}
    }
}
$store=(Resolve-Path -LiteralPath $StoreFile).Path
$certificate=(Resolve-Path -LiteralPath $Certificate).Path
$profilePath=(Resolve-Path -LiteralPath $Profile).Path
foreach($path in @($store,$certificate,$profilePath)){
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw 'A signing material is not a regular file'}
}
# No passwords on the command line, in project JSON, or in logs.
if($PSCmdlet.ParameterSetName -eq 'Request'){
    $saved=Get-Content -LiteralPath (Join-Path $requestRoot 'credentials.dpapi.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($saved.schemaVersion -ne 1 -or $saved.bundleName -ne $BundleName){throw 'Request credentials do not match the application'}
    $storePassword=ConvertTo-SecureString $saved.storePassword
    $keyPassword=ConvertTo-SecureString $saved.keyPassword
}else{
    $storePassword=Read-Host 'P12 store password' -AsSecureString
    $keyPassword=Read-Host 'Private key password' -AsSecureString
}
if($storePassword.Length -eq 0 -or $keyPassword.Length -eq 0){throw 'Signing passwords must not be empty'}
New-Item -ItemType Directory -Force -Path $target | Out-Null
try {
    $acl=New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl.SetOwner($sid)
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
    Set-Acl -LiteralPath $target -AclObject $acl
    Copy-Item -LiteralPath $store -Destination (Join-Path $target 'developer.p12')
    Copy-Item -LiteralPath $certificate -Destination (Join-Path $target 'developer.cer')
    Copy-Item -LiteralPath $profilePath -Destination (Join-Path $target 'developer.p7b')
    $config=@{bundleName=$BundleName;storeFile='developer.p12';keyAlias=$KeyAlias;certpath='developer.cer';profile='developer.p7b'}
    $credentials=@{schemaVersion=1;bundleName=$BundleName;storePassword=($storePassword|ConvertFrom-SecureString);keyPassword=($keyPassword|ConvertFrom-SecureString)}
    $utf8=[Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $target 'credentials.dpapi.json'),($credentials|ConvertTo-Json),$utf8)
    # Commit discovery marker last; an interrupted import is never auto-selected.
    [IO.File]::WriteAllText((Join-Path $target 'signing.local.json'),($config|ConvertTo-Json),$utf8)
    Write-Host "Signing configuration imported for $BundleName. Passwords are Windows DPAPI-protected for this user."
    Write-Host 'The certificate/Profile must match this application and authorize the test device; import alone does not verify device eligibility.'
} finally {
    $storePassword.Dispose();$keyPassword.Dispose()
}
