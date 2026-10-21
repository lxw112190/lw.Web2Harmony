[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$')][string]$BundleName,
    [Parameter(Mandatory=$true)][string]$StoreFile,
    [Parameter(Mandatory=$true)][string]$Certificate,
    [Parameter(Mandatory=$true)][string]$Profile,
    [Parameter(Mandatory=$true)][string]$KeyAlias
)
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Windows DPAPI is required for local credential storage'}
$root=Split-Path -Parent $PSScriptRoot
$target=Join-Path $root ('signing/'+$BundleName)
if(Test-Path -LiteralPath $target){throw 'Signing directory already exists; back it up outside this project before replacing the configuration.'}
$store=(Resolve-Path -LiteralPath $StoreFile).Path
$certificate=(Resolve-Path -LiteralPath $Certificate).Path
$profilePath=(Resolve-Path -LiteralPath $Profile).Path
foreach($path in @($store,$certificate,$profilePath)){
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw 'A signing material is not a regular file'}
}
# No passwords on the command line, in project JSON, or in logs.
$storePassword=Read-Host 'P12 store password' -AsSecureString
$keyPassword=Read-Host 'Private key password' -AsSecureString
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
