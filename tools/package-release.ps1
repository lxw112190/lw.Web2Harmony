[CmdletBinding()]
param([string]$BuildDirectory='build/Release',[string]$HapDirectory,[string]$OutputDirectory='build/releases')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$lock=Get-Content -Raw -LiteralPath (Join-Path $root 'toolchain.lock.json')|ConvertFrom-Json
$name="lw-Web2Harmony-v$($lock.productVersion)-windows-x64"
$package=Join-Path (Join-Path $root $OutputDirectory) $name
if (Test-Path -LiteralPath $package) { throw 'Release package directory already exists; use a fresh build directory.' }
New-Item -ItemType Directory -Force -Path "$package/bin" | Out-Null
foreach ($exe in @('lw.Web2Harmony.exe','lw.Web2Harmony.GUI.exe')) {
    $file=Join-Path $root "$BuildDirectory/$exe"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Binary missing: $file" }
    if ((Get-Item -LiteralPath $file).VersionInfo.ProductVersion -ne $lock.productVersion) { throw 'Binary version mismatch' }
    Copy-Item -LiteralPath $file -Destination "$package/bin"
}
foreach ($dir in @('assets','samples','tools','docs','third_party')) {
    Copy-Item -LiteralPath (Join-Path $root $dir) -Destination $package -Recurse
}
& "$PSScriptRoot/copy-runtime-source.ps1" -Destination "$package/runtime"
New-Item -ItemType Directory -Force -Path "$package/packer"|Out-Null
Copy-Item -LiteralPath (Join-Path $root 'packer/templates') -Destination "$package/packer/templates" -Recurse
foreach ($file in @('LICENSE','README.md','README_EN.md','THIRD-PARTY-NOTICES.md','toolchain.lock.json')) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $package
}
if ($HapDirectory) { Copy-Item -LiteralPath $HapDirectory -Destination "$package/demo-haps" -Recurse }
$utf8=[Text.UTF8Encoding]::new($false)
$metadata=@{name='lw.Web2Harmony';version=$lock.productVersion;buildTimeUtc=[DateTime]::UtcNow.ToString('o');commit=$env:GITHUB_SHA;harmonySdkIncluded=$false;demoHapsIncluded=[bool]$HapDirectory}
[IO.File]::WriteAllText("$package/release.json",($metadata|ConvertTo-Json),$utf8)
$checks=Get-ChildItem -LiteralPath $package -Recurse -File | Sort-Object FullName | ForEach-Object {
    $relative=$_.FullName.Substring($package.Length+1).Replace('\','/')
    (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()+"  $relative"
}
[IO.File]::WriteAllLines("$package/SHA256SUMS.txt",[string[]]$checks,$utf8)
$zip="$package.zip"
Compress-Archive -LiteralPath $package -DestinationPath $zip
(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()+"  $name.zip" | Set-Content -LiteralPath "$zip.sha256" -Encoding ascii
Write-Host $zip
