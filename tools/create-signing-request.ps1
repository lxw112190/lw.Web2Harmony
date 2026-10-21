[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateLength(3,127)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$')][string]$BundleName,
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_.-]{0,63}$')][string]$KeyAlias='web2harmony',
    [ValidatePattern('^[\p{L}\p{N} ._-]{1,64}$')][string]$CommonName='Web2Harmony Developer',
    [ValidatePattern('^[\p{L}\p{N} ._-]{1,64}$')][string]$Organization='lw.Web2Harmony',
    [ValidatePattern('^[A-Z]{2}$')][string]$Country='CN',
    [string]$OutputDirectory,
    [string]$JavaHome
)
. ([IO.Path]::Combine($PSScriptRoot,'initialize-powershell.ps1'))
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Windows DPAPI is required'}
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$OutputEncoding=[Console]::OutputEncoding
$root=Split-Path -Parent $PSScriptRoot
if(-not $JavaHome){$JavaHome=Join-Path $root 'toolchain/jdk-21'}
$jdk=(Resolve-Path -LiteralPath $JavaHome).Path
$keytool=Join-Path $jdk 'bin/keytool.exe'
if(-not (Test-Path -LiteralPath $keytool -PathType Leaf)){throw 'JDK keytool is missing; run tools/setup-local-jdk.ps1 first.'}
$release=Get-Content -LiteralPath (Join-Path $jdk 'release') -Raw
if($release -notmatch 'JAVA_VERSION="21\.') {throw 'Use the supported JDK 21 for signing requests'}
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root ('signing/requests/'+$BundleName)}
$target=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $target){throw 'Signing request directory already exists; keep the original key and use a new directory if you intentionally need a different identity.'}
$utf8=[Text.UTF8Encoding]::new($false)
$log=Join-Path $root 'logs/signing-request.log'
$plain=$null;$password=$null;$confirmation=$null
$environmentName='LW_WEB2HARMONY_REQUEST_PASSWORD'
$previousPassword=[Environment]::GetEnvironmentVariable($environmentName,'Process')
function Write-RequestLog([string]$Text){
    if($script:plain){$Text=$Text.Replace($script:plain,'[redacted]')}
    $line=[DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff zzz')+' '+$Text
    Write-Host $line
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $log)|Out-Null
    if((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -ge 2MB){
        if(Test-Path -LiteralPath "$log.5"){Remove-Item -LiteralPath "$log.5" -Force}
        for($i=4;$i -ge 1;$i--){if(Test-Path -LiteralPath "$log.$i"){Move-Item -LiteralPath "$log.$i" -Destination "$log.$($i+1)" -Force}}
        Move-Item -LiteralPath $log -Destination "$log.1" -Force
    }
    [IO.File]::AppendAllText($log,$line+[Environment]::NewLine,$utf8)
}
function Invoke-RequestKeytool([string[]]$Arguments){
    $previous=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        & $keytool '-J-Dfile.encoding=UTF-8' '-J-Dstdout.encoding=UTF-8' '-J-Dstderr.encoding=UTF-8' @Arguments 2>&1 | ForEach-Object {Write-RequestLog $_.ToString()}
        $code=$LASTEXITCODE
    }finally{$ErrorActionPreference=$previous}
    if($code -ne 0){throw "keytool failed with exit code $code"}
}
function Get-RequestHash([string]$Path){
    $stream=[IO.File]::OpenRead($Path);$sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose();$stream.Dispose()}
}
try{
    Write-RequestLog "Signing request started; bundle=$BundleName; output=$target"
    $password=Read-Host 'New P12 password (at least 8 characters)' -AsSecureString
    $confirmation=Read-Host 'Confirm P12 password' -AsSecureString
    if($password.Length -lt 8){throw 'P12 password must contain at least 8 characters'}
    $first=[IntPtr]::Zero;$second=[IntPtr]::Zero
    try{
        $first=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
        $second=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmation)
        $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($first)
        if($plain -cne [Runtime.InteropServices.Marshal]::PtrToStringBSTR($second)){throw 'Password confirmation does not match'}
    }finally{
        if($first -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($first)}
        if($second -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($second)}
    }
    # Reserve a NEW directory atomically. No existing key may be overwritten.
    $parent=Split-Path -Parent $target
    New-Item -ItemType Directory -Force -Path $parent|Out-Null
    New-Item -ItemType Directory -Path $target -ErrorAction Stop|Out-Null
    $acl=New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl.SetOwner($sid)
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
    Set-Acl -LiteralPath $target -AclObject $acl
    $store=Join-Path $target 'developer.p12'
    $csr=Join-Path $target 'developer.csr'
    [Environment]::SetEnvironmentVariable($environmentName,$plain,'Process')
    # A PKCS12 store uses one password for store and private key. Never pass
    # plaintext passwords in command arguments, files, or logs.
    $subject="CN=$CommonName,O=$Organization,OU=Development,C=$Country"
    Invoke-RequestKeytool @('-genkeypair','-alias',$KeyAlias,'-keyalg','EC','-groupname','secp256r1',
        '-sigalg','SHA256withECDSA','-dname',$subject,'-keystore',$store,'-storetype','PKCS12',
        '-validity','9125','-storepass:env',$environmentName,'-keypass:env',$environmentName,'-noprompt')
    Invoke-RequestKeytool @('-certreq','-alias',$KeyAlias,'-sigalg','SHA256withECDSA','-keystore',$store,
        '-storetype','PKCS12','-file',$csr,'-storepass:env',$environmentName,'-keypass:env',$environmentName)
    Invoke-RequestKeytool @('-printcertreq','-file',$csr)
    if((Get-Item -LiteralPath $store).Length -eq 0 -or
        -not ([IO.File]::ReadAllText($csr)).Contains('BEGIN NEW CERTIFICATE REQUEST')){throw 'keytool did not produce a valid keystore/CSR'}
    $encrypted=$password|ConvertFrom-SecureString
    $credentials=@{schemaVersion=1;bundleName=$BundleName;storePassword=$encrypted;keyPassword=$encrypted}
    [IO.File]::WriteAllText((Join-Path $target 'credentials.dpapi.json'),($credentials|ConvertTo-Json),$utf8)
    $metadata=@{schemaVersion=1;bundleName=$BundleName;keyAlias=$KeyAlias;keyAlgorithm='EC';curve='secp256r1';signatureAlgorithm='SHA256withECDSA';storeFile='developer.p12';csrFile='developer.csr';storeSha256=(Get-RequestHash $store);csrSha256=(Get-RequestHash $csr);createdAtUtc=[DateTime]::UtcNow.ToString('o');huaweiCertificateIssued=$false;profileIssued=$false}
    # Commit completion marker last. Interrupted requests are never imported.
    [IO.File]::WriteAllText((Join-Path $target 'request.json'),($metadata|ConvertTo-Json),$utf8)
    Write-RequestLog 'Signing request completed. Upload ONLY developer.csr to request a Huawei certificate.'
    Write-RequestLog 'P12 contains a local placeholder certificate, not Huawei device authorization. No .cer or Profile was issued.'
    Write-Host "CSR: $csr"
    Write-Host 'Keep developer.p12, credentials.dpapi.json and the password private. Never upload the P12 to a certificate-request page.'
}catch{
    Write-RequestLog ('Signing request failed: '+$_.Exception.Message)
    throw
}finally{
    [Environment]::SetEnvironmentVariable($environmentName,$previousPassword,'Process')
    $plain=$null
    if($password){$password.Dispose()}
    if($confirmation){$confirmation.Dispose()}
}
