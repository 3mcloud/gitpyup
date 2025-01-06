<#
Copyright (c) 2024 3M Company
This script creates or updates the python applications configured in gitpyup.
#> 

param(
    [string]$Name = "",
    [string]$Path = "",
    [string]$EnvironmentFile = "",
    [string]$InstallType = "SingleUser",
    [string]$LocalConfigYaml = "gitpyup.yml"
)

# logging
. "./Utility-Functions.ps1"
Start-Logging

Write-Log "Setup-Application v1"

if ($Name) {
    $appName = $Name
} else {
    $appName = Split-Path (Get-Location).Path -Parent
}

if ($Path) {
    $appPath = $Path
} else {
    $appPath = (Get-Location).Path
}

# load repo config
$configYmlPath = Join-Path $appPath $LocalConfigYaml
if (Test-Path $configYmlPath) {
    Write-Log "Using config file $configYmlPath"
    # config file found
    $repoConfigRaw = Get-Content -Path $configYmlPath -Raw
    $repoConfig = ConvertFrom-Yaml $repoConfigRaw
} else {
    Write-Log "No config file found in $appPath"
    $repoConfig = @{}
}

### inspect appPath for environment file ###

# list of supported environment files in priority order
$envFiles = @(
    "environment.yml",
    "environment.yaml",
    "pyproject.toml",
    "setup.py",
    "requirements.txt"
)
# auto-detect environment file
foreach ($autoEnvFile in $envFiles) {
    #LINUX #MACOS make case insensitive
    if (Test-Path (Join-Path $appPath $autoEnvFile)) {
        Write-Log "Automatically found environment file $autoEnvFile"
        break
    }
}

# repo config has priority over auto-detection
if ($repoConfig.ContainsKey("environment_file")) {
    $envFile = $repoConfig["environment_file"]
}

# app config has priority over repo config
if ($EnvironmentFile) {
    $envFile = $EnvironmentFile
}

# if environment file exists continue if not return error
$envFilePath = Join-Path $appPath $envFile
$autoEnvFilePath = Join-Path $appPath $autoEnvFile
if (Test-Path $envFilePath -PathType Leaf) {
    Write-Log "Using environment file $envFilePath"
} elseif (Test-Path $autoEnvFilePath -PathType Leaf) {
    $envFilePath = $autoEnvFilePath
    Write-Log "Using automatically found environment file $autoEnvFilePath"
} else {
    $message = "No environment file found in $appPath"
    Write-Log "$message" -Level "ERROR"
    Exit 1
}

# set environment file type and condaEnvName
$envFile = Split-Path $envFilePath -Leaf
$condaEnvName = $appName

# configure install/update command
if ($envFile.Contains(".yml") -or $envFile.Contains(".yaml")) {
    $installCommand = "conda env update -n $condaEnvName --file $envFilePath --prune"
} elseif ($envFile -ieq "setup.py" -or $envFile -ieq "pyproject.toml") {
    $installCommand = "conda run -n $condaEnvName python -m pip install -e $appPath"
} elseif ($envFile -ieq "requirements.txt") {
    $installCommand = "conda run -n $condaEnvName python -m pip install -r $envFilePath"
} else {
    Write-Log "Unsupported environment file $envFile" -Level "ERROR"
    Exit 1
}

# check for existing conda environment, create if not found
$condaEnvList = conda env list
if ($condaEnvList | Select-String -Pattern $condaEnvName) {
    Write-Log "Conda environment $condaEnvName exists"
} else {
    Write-Log "Creating conda environment $condaEnvName"
    $response = conda create -n $condaEnvName
    Write-Log ($response | Out-String)
}

# install or update python into environment
if ($envFile -ieq "setup.py" -or $envFile -ieq "requirements.txt" -or $envFile -ieq "pyproject.toml") {
    # get version of python in base environment
    $response = conda run -n base python --version
    if ($response -match "Python (\d+\.\d+\.\d+)") {
        $basePythonVersion = $matches[1]
        Write-Log "base environment Python version: $basePythonVersion"
    } else {
        Write-Log "No Python found in base environment." -Level "ERROR"
        Exit 1
    }
    # get current version of python in environment, install if not found
    $response = conda run -n $condaEnvName python --version
    if ($response -match "Python (\d+\.\d+\.\d+)") {
        $pythonVersion = $matches[1]
        Write-Log "$condaEnvName environment Python version: $pythonVersion"
    } else {
        Write-Log "It is normal to see 'Python was not found' above this message."
        Write-Log "Installing Python=$basePythonVersion into $condaEnvName environment..."
        $response = conda install -n $condaEnvName python=$basePythonVersion -y
        Write-Log ($response | Out-String)
    }
    # if versions don't match update python
    if ($pythonVersion -ne $basePythonVersion) {
        Write-Log "Updating to Python=$basePythonVersion in $condaEnvName environment..."
        $response = conda install -n $condaEnvName python=$basePythonVersion -y
        Write-Log ($response | Out-String)
    }
}

# install dependencies, keeps trying if install fails
Write-Log "$appName python package installing or updating, duration depends on internet and computer speed."
$NumAttempts = 1
$Success = $False
While (!($Success) -and ($NumAttempts -lt 5)) {
    Write-Log "$appName python package install/update attempt $NumAttempts..."
    $response = Invoke-Expression $installCommand
    $installExitCode = $LASTEXITCODE

    # exit code based test
    if ($installExitCode -eq 0) {
        $Success = $True
    } else {
        $Success = $False
    }

    if ($Success) {
        Write-Log ($response | Out-String)
        Write-Log "Successfully installed or updated"
        # environment files have no permissions for 'Users' group
        if ($InstallType -eq "AllUsers") {
            Write-Log "Granting permissions to env folder. This can take over 30 minutes..."
            # inheritance, traversal, quiet
            icacls $EnvPath /grant:r "Users:(OI)(CI)F" /T /Q # full permissions
        }
    } else {
        Write-Log "Attempt $NumAttempts failed to install or update" -Level "ERROR"
        Write-Log ($response | Out-String) -Level "ERROR"
    }
    $NumAttempts++
}

# only wait if in debug mode
if ($Env:GITPYUP_DEPLOY_DEBUG) {
    Read-Host -Prompt "Press enter key to exit" | Out-Null
}

Exit $installExitCode