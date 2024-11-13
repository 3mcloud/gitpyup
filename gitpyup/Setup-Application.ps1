<#
This script creates or updates the python applications configured in gitpyup.
#> 

param(
    [hashtable]$AppConfig = @{},
    $InstallType = "SingleUser"
)

# logging
. "./Utility-Functions.ps1"
Start-Logging

Write-Log "Setup-Application v1"

if ($AppConfig.ContainsKey("name")) {
    $appName = $AppConfig["name"]
} else {
    $appName = Split-Path (Get-Location).Path -Parent
}

if ($AppConfig.ContainsKey("path")) {
    $appPath = $AppConfig["path"]
} else {
    $appPath = (Get-Location).Path
}

### inspect appPath for environment file ###

# list of supported environment files in priority order
$envFiles = @(
    "environment.yml",
    "environment.yaml",
    "setup.py",
    "requirements.txt"
)

foreach ($envFile in $envFiles) {
    if (Test-Path (Join-Path $appPath $envFile)) {
        break
    }
}

if ($AppConfig.ContainsKey("environment_file")) {
    $envFile = $AppConfig["environment_file"]
}

# if environment file exists continue if not return error
$envFilePath = Join-Path $appPath $envFile
if (Test-Path $envFilePath) {
    Write-Log "Using environment file $envFilePath"
} else {
    Write-Log "No environment file found in $appPath" -Level "ERROR"
    Return 1
}

# attempt to update conda base environment
Write-Log "updating conda base env..."
$response = conda update -n base -c conda-forge conda -y
Write-Log ($response | Out-String)

# check for existing conda environment, create if not found
$condaEnvName = $appName
$condaEnvList = conda env list
if ($condaEnvList | Select-String -Pattern $condaEnvName) {
    Write-Log "Conda environment $condaEnvName already exists"
} else {
    Write-Log "Creating conda environment $condaEnvName"
    $response = conda create -n $condaEnvName
    Write-Log ($response | Out-String)
}

# configure install/update command
if ($envFile -ieq "environment.yml" -or $envFile -ieq "environment.yaml") {
    $installCommand = "conda env update -n $condaEnvName --file $envFilePath --prune"
    $successString = "Successfully installed "
} elseif ($envFile -ieq "setup.py") {
    $installCommand = "conda run -n $condaEnvName python -m pip install -e $appPath"
} elseif ($envFile -eq "requirements.txt") {
    $installCommand = "conda run -n $condaEnvName python -m pip install -r $envFilePath"
} else {
    Write-Log "Unsupported environment file $envFile" -Level "ERROR"
    Return 1
}

# install dependencies, keeps trying if install failed
Write-Log "$appName python package installing or updating, duration depends on internet and computer speed."
$NumAttempts = 1
$Success = $False
While (!($Success) -and ($NumAttempts -lt 5)) {
    Write-Log "$appName python package install/update attempt $NumAttempts..."
    $response = Invoke-Expression $installCommand
    $Success = $response | Select-String -Pattern $successString
    if ($successString -and !($Success)) {
        Write-Log ($response | Out-String) -Level "ERROR"
    } else {
        Write-Log ($response | Out-String)
        Write-Log "Successfully installed or updated"
        # environment files have no permissions for 'Users' group
        if ($InstallType -eq "AllUsers") {
            Write-Log "Granting permissions to env folder. This can take over 30 minutes..."
            # inheritance, traversal, quiet
            icacls $EnvPath /grant:r "Users:(OI)(CI)F" /T /Q # full permissions
        }
    }
    $NumAttempts++
}

# only wait if in debug mode
if ($Env:GITPYUP_DEPLOY_DEBUG) {
    Read-Host -Prompt "Press enter key to exit" | Out-Null
}

# remove current shortcut
$ToRemove = @(
    "$env:CLARKE_SHORTCUT_PARENT_USER\$Repo-jupyter.lnk",
    "$env:CLARKE_SHORTCUT_PARENT_ALL\$Repo-jupyter.lnk"
)
# shortcut creation
$ToAdd = @(
    @{ "shortcut_path" = "$env:CLARKE_SHORTCUT_PARENT\$Repo-jupyter.lnk";
       "script_name" = Convert-Path "run-jupyter.ps1";
       "target_path" = "powershell.exe";
       "working_directory" = "."}
)
$ShortcutArgs = $ToRemove, $ToAdd
$EncodedShortcutArgs = ConvertTo-Base64String -Arguments $ShortcutArgs
if ($InstallType -eq "AllUsers") {
    Start-Process -FilePath "powershell" -Verb RunAs -Wait -ArgumentList (
        "-EncodedCommand $EncodedShortcutScript",
        "-EncodedArguments $EncodedShortcutArgs"
    )
} else {
    Start-Process -FilePath "powershell" -Wait -NoNewWindow -ArgumentList (
        "-EncodedCommand $EncodedShortcutScript",
        "-EncodedArguments $EncodedShortcutArgs"
    )
}

Return $LASTEXITCODE