[CmdletBinding()]
param([ValidateSet('Release','Debug')][string]$Configuration='Release')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$cmake=(Get-Command cmake.exe -ErrorAction Stop).Source
$build=Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path "$build/temp","$build/logs"|Out-Null
# Clean Windows child environment avoids the inherited PATH/Path duplicate bug.
# Explicit TEMP/TMP avoids falling back to a restricted Windows system Temp.
$scriptBody=@'
$ErrorActionPreference='Stop'
$env:TEMP='@BUILD@/temp'
$env:TMP='@BUILD@/temp'
$env:MSBUILDDISABLENODEREUSE='1'
Set-Location -LiteralPath '@ROOT@'
& '@CMAKE@' -S '@ROOT@' -B '@BUILD@' -A x64 -DBUILD_TESTING=ON
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& '@CMAKE@' --build '@BUILD@' --config '@CONFIG@' --parallel 4 -- /nodeReuse:false
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& '@CTEST@' --test-dir '@BUILD@' -C '@CONFIG@' --output-on-failure
exit $LASTEXITCODE
'@
$ctest=[IO.Path]::Combine([IO.Path]::GetDirectoryName($cmake),'ctest.exe')
$scriptBody=$scriptBody.Replace('@ROOT@',$root.Replace("'","''")).Replace('@BUILD@',$build.Replace("'","''")).Replace('@CMAKE@',$cmake.Replace("'","''")).Replace('@CTEST@',$ctest.Replace("'","''")).Replace('@CONFIG@',$Configuration)
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptBody))
$process=Start-Process -FilePath "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -ArgumentList @('-NoProfile','-EncodedCommand',$encoded) -WorkingDirectory $root -UseNewEnvironment -WindowStyle Hidden -PassThru -RedirectStandardOutput "$build/logs/desktop-build.out.log" -RedirectStandardError "$build/logs/desktop-build.err.log"
# Wait for this build process only; Start-Process -Wait can also wait for
# persistent COM descendants created by the GUI smoke test.
$process.WaitForExit()
Get-Content -LiteralPath "$build/logs/desktop-build.out.log"
Get-Content -LiteralPath "$build/logs/desktop-build.err.log"
exit $process.ExitCode
