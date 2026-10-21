# Dot-source before invoking module cmdlets. A Windows PowerShell 5.1 child
# may inherit PowerShell 7's PSModulePath from Actions/pwsh/native launchers.
# Resolve shared inbox modules from THIS engine, never by inherited name lookup.
# Only this process's environment is changed; user/system settings stay intact.
& {
    $nativeRoot=[IO.Path]::Combine($PSHOME,'Modules')
    $modulePaths=@($nativeRoot)
    foreach($entry in ([string]$env:PSModulePath).Split([IO.Path]::PathSeparator)){
        if($entry -and $entry -ne $nativeRoot){$modulePaths+=$entry}
    }
    $env:PSModulePath=$modulePaths -join [IO.Path]::PathSeparator
    foreach($name in @('Microsoft.PowerShell.Management','Microsoft.PowerShell.Utility','Microsoft.PowerShell.Security')){
        $manifest=[IO.Path]::Combine($nativeRoot,$name,$name+'.psd1')
        if(-not [IO.File]::Exists($manifest)){throw "Required inbox module is missing: $manifest"}
        Import-Module -Name $manifest -Global -Force -ErrorAction Stop
    }
}
