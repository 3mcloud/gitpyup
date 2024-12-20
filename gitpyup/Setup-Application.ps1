<#
Copyright (c) 2024 3M Company
This script creates or updates the python applications configured in gitpyup.
#> 

param(
    [hashtable]$AppConfig = @{},
    [string]$InstallType = "SingleUser",
    [string]$LocalConfigYaml = "gitpyup.yml"
)

# logging
. "./$ENV:GITPYUPUTILSNAME"
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

# load repo config
$configYmlPath = Join-Path $appPath $LocalConfigYaml
if (Test-Path $configYmlPath) {
    # config file found
    $repoConfigRaw = Get-Content -Path $configYmlPath -Raw
    $repoConfig = ConvertFrom-Yaml $repoConfigRaw
} else {
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
    if (Test-Path (Join-Path $appPath $autoEnvFile)) {
        break
    }
}

# repo config has priority over auto-detection
if ($repoConfig.ContainsKey("environment_file")) {
    $envFile = $repoConfig["environment_file"]
}

# app config has priority over repo config
if ($AppConfig.ContainsKey("environment_file")) {
    $envFile = $AppConfig["environment_file"]
}

# if environment file exists continue if not return error
$envFilePath = Join-Path $appPath $envFile
$autoEnvFilePath = Join-Path $appPath $autoEnvFile
if (Test-Path $envFilePath -PathType Leaf) {
    Write-Log "Using environment file $envFilePath"
} elseif (Test-Path $autoEnvFilePath -PathType Leaf) {
    $envFilePath = $autoEnvFilePath
    Write-Log "Automatically found environment file $envFilePath"
} else {
    Write-Log "No environment file found in $appPath" -Level "ERROR"
    Return 1
}

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
} elseif ($envFile -ieq "setup.py" -or $envFile -ieq "pyproject.toml") {
    $installCommand = "conda run -n $condaEnvName python -m pip install -e $appPath"
} elseif ($envFile -ieq "requirements.txt") {
    $installCommand = "conda run -n $condaEnvName python -m pip install -r $envFilePath"
} else {
    Write-Log "Unsupported environment file $envFile" -Level "ERROR"
    Return 1
}

# install or update python into environment
if ($envFile -ieq "setup.py" -or $envFile -ieq "requirements.txt") {
    # get version of python in base environment
    $response = conda run -n base python --version
    if ($response -match "Python (\d+\.\d+\.\d+)") {
        $basePythonVersion = $matches[1]
        Write-Log "base environment Python version: $basePythonVersion"
    } else {
        Write-Log "No Python found in base environment." -Level "ERROR"
        return 1
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

    # success string based test overrides exit code
    if ($successString) {
        $Success = $response | Select-String -Pattern $successString
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
        Write-Log ($response | Out-String) -Level "ERROR"
    }
    $NumAttempts++
}

# only wait if in debug mode
if ($Env:GITPYUP_DEPLOY_DEBUG) {
    Read-Host -Prompt "Press enter key to exit" | Out-Null
}

Return $LASTEXITCODE