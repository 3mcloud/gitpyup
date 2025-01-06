<#
Copyright (c) 2025 3M Company
This script tests the Setup-Application.ps1 script.
!!! need to manually run Deploy-gitpyup once to generate Utility-Functions.ps1
#> 

# change path to gitpyup
Set-Location "$PSScriptRoot\..\gitpyup"

. "./Utility-Functions.ps1"
Start-Logging

$install = @{
    'type' = "SingleUser"
}

# set the application path to the tests directory
$appPath = $PSScriptRoot

$application = @{
    'name' = "gitpyup-test"
    'path' = $appPath
    'environment_file' = "gitpyup-test-env.yml"
}

$name = $application.name

$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = "powershell"
$pinfo.RedirectStandardError = $true
$pinfo.RedirectStandardOutput = $false
$pinfo.UseShellExecute = $false
$pinfo.CreateNoWindow = $false  # doesn't seem to open a window but when false does output to console
$pinfo.WorkingDirectory = (Get-Location).Path
$pinfo.Arguments = "-Command & './Setup-Application.ps1' " + 
    "-Name $($application.name) " +
    "-Path $($application.path) " +
    "-EnvironmentFile $($application.environment_file) " +
    "-InstallType $($install.type)"
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $pinfo
$p.Start() | Out-Null
$p.WaitForExit()
if ($p.ExitCode -ne 0) {
    Write-Log "Python environment setup failed for $name, Run $gpun-update shortcut to try again!" -Level 'ERROR'
    Write-Log "exit code: $($p.ExitCode)"  -Level 'ERROR'
    $stderr = $p.StandardError.ReadToEnd()
    if ($stderr) {
        Write-Log "stderr: $stderr" -Level 'ERROR'
    }
} else {
    Write-Log "Python environment setup complete for $name."
}
