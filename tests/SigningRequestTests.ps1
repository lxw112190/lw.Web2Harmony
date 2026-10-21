param([Parameter(Mandatory=$true)][string]$RepositoryRoot,[Parameter(Mandatory=$true)][string]$JavaHome)
. ([IO.Path]::Combine($RepositoryRoot,'tools','initialize-powershell.ps1'))
$ErrorActionPreference='Stop'
$work=Join-Path $RepositoryRoot ('build/request-test-'+[guid]::NewGuid().ToString('N'))
$password='Fixture-only-Aa1!'
$previousRequestPassword=$env:LW_WEB2HARMONY_REQUEST_PASSWORD
$previousProbePassword=$env:LW_SIGNING_TEST_PASSWORD
$global:LwRequestTestMismatch=$false
function Read-Host {
    param([string]$Prompt,[switch]$AsSecureString)
    if($global:LwRequestTestMismatch -and $Prompt.StartsWith('Confirm')){return ConvertTo-SecureString 'Mismatch-only-Aa1!' -AsPlainText -Force}
    return ConvertTo-SecureString 'Fixture-only-Aa1!' -AsPlainText -Force
}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action){$rejected=$false;try{& $Action}catch{$rejected=$true};Require $rejected 'Invalid operation was accepted'}
try{
    New-Item -ItemType Directory -Force -Path "$work/tools","$work/logs","$work/input"|Out-Null
    foreach($name in @('initialize-powershell.ps1','create-signing-request.ps1','configure-signing.ps1')){
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot "tools/$name") -Destination "$work/tools/$name"
    }
    [IO.File]::WriteAllText("$work/logs/signing-request.log",('x'*(2MB+1)))
    $unicode=-join [char[]](0x6D4B,0x8BD5,0x5F00,0x53D1,0x8005)
    $target=Join-Path $work ('request '+$unicode)
    $arguments=@{BundleName='com.lw.requesttest';KeyAlias='request-key';CommonName=$unicode;OutputDirectory=$target;JavaHome=$JavaHome}
    $env:LW_WEB2HARMONY_REQUEST_PASSWORD='existing-environment-sentinel'
    & "$work/tools/create-signing-request.ps1" @arguments
    Require ($env:LW_WEB2HARMONY_REQUEST_PASSWORD -eq 'existing-environment-sentinel') 'Caller password environment was not restored'
    $request=Get-Content -LiteralPath "$target/request.json" -Raw|ConvertFrom-Json
    Require ($request.keyAlgorithm -eq 'EC' -and $request.curve -eq 'secp256r1') 'Wrong key algorithm'
    Require (-not $request.huaweiCertificateIssued -and -not $request.profileIssued) 'Local request incorrectly claims platform authorization'
    Require (-not (Test-Path -LiteralPath "$target/developer.cer") -and -not (Test-Path -LiteralPath "$target/developer.p7b")) 'Request issued fake Huawei signing material'
    Require (Test-Path -LiteralPath "$work/logs/signing-request.log.1") 'Request logs did not rotate'
    $acl=Get-Acl -LiteralPath $target
    Require $acl.AreAccessRulesProtected 'Request directory ACL is not private'
    $env:LW_SIGNING_TEST_PASSWORD=$password
    & (Join-Path $JavaHome 'bin/java.exe') (Join-Path $RepositoryRoot 'tests/SigningRequestProbe.java') "$target/developer.p12" "$target/developer.csr" 'request-key' $unicode
    Require ($LASTEXITCODE -eq 0) 'JDK CSR/P12 cryptographic verification failed'
    Require ([IO.File]::ReadAllText("$work/logs/signing-request.log")).Contains('CN='+$unicode) 'Unicode keytool output was corrupted in request log'
    $originalP12=[IO.File]::ReadAllBytes("$target/developer.p12")
    Reject {& "$work/tools/create-signing-request.ps1" @arguments}
    Require ([Convert]::ToBase64String($originalP12) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes("$target/developer.p12"))) 'Existing P12 was overwritten'
    $global:LwRequestTestMismatch=$true
    $arguments.OutputDirectory="$work/password-mismatch"
    Reject {& "$work/tools/create-signing-request.ps1" @arguments}
    Require (-not (Test-Path -LiteralPath $arguments.OutputDirectory)) 'Password mismatch created private material'
    $global:LwRequestTestMismatch=$false
    $arguments.BundleName='../unsafe'
    Reject {& "$work/tools/create-signing-request.ps1" @arguments}
    # Inert fixture files: import tests storage behavior, NOT Huawei authorization.
    [IO.File]::WriteAllBytes("$work/input/debug.cer",[byte[]](1,2,3))
    [IO.File]::WriteAllBytes("$work/input/debug.p7b",[byte[]](4,5,6))
    $originalCsr=[IO.File]::ReadAllBytes("$target/developer.csr")
    [IO.File]::AppendAllText("$target/developer.csr",'tamper')
    Reject {& "$work/tools/configure-signing.ps1" -BundleName com.lw.requesttest -RequestDirectory $target -Certificate "$work/input/debug.cer" -Profile "$work/input/debug.p7b"}
    Require (-not (Test-Path "$work/signing/com.lw.requesttest")) 'Tampered request was committed'
    [IO.File]::WriteAllBytes("$target/developer.csr",$originalCsr)
    & "$work/tools/configure-signing.ps1" -BundleName com.lw.requesttest -RequestDirectory $target -Certificate "$work/input/debug.cer" -Profile "$work/input/debug.p7b"
    $config=Get-Content -Raw "$work/signing/com.lw.requesttest/signing.local.json"|ConvertFrom-Json
    Require ($config.keyAlias -eq 'request-key') 'Generated request alias was not preserved'
    $credentials=Get-Content -Raw "$work/signing/com.lw.requesttest/credentials.dpapi.json"|ConvertFrom-Json
    $secure=ConvertTo-SecureString $credentials.storePassword
    $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try{Require ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) -ceq $password) 'Imported DPAPI password does not match generated P12'}
    finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer);$secure.Dispose()}
    foreach($file in (Get-ChildItem -LiteralPath $work -Recurse -File|Where-Object {$_.Extension -eq '.json' -or $_.Name -like '*.log*'})){
        Require (-not ([IO.File]::ReadAllText($file.FullName)).Contains($password)) 'Password leaked into metadata/logs'
    }
    Write-Host 'Real EC P12/CSR, signature, Unicode paths, DPAPI, rotation, no-overwrite, tamper and request import tests passed.'
}finally{
    $env:LW_WEB2HARMONY_REQUEST_PASSWORD=$previousRequestPassword
    $env:LW_SIGNING_TEST_PASSWORD=$previousProbePassword
    Remove-Variable -Name LwRequestTestMismatch -Scope Global -ErrorAction SilentlyContinue
    $boundary=[IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'build'))+[IO.Path]::DirectorySeparatorChar
    $resolved=[IO.Path]::GetFullPath($work)
    if(-not $resolved.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected signing request test cleanup target'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
