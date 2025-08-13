<#
Copyright (c) 2024 3M Company
This script installs Miniforge3.
It can be run as part of gitpyup for now.
#> 

# run Utility-Functions.ps1 to get the utility functions
. "./Utility-Functions.ps1"
Start-Logging

# check if admin and exit if true
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$RunningAsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($RunningAsAdmin) {
    if (Test-Path "$Env:TEMP\gitpyup-as-admin") {
        Remove-Item -Force "$Env:TEMP\gitpyup-as-admin"
    } else {
        Write-Log "Please run this script as a regular user"
        Wait-Logging
        Read-Host -Prompt "Press enter key to exit" | Out-Null
        exit
    }
}

# determine expected Miniforge3 install path
if ($env:GITPYUP_INSTALL_PARENT | Select-String -Pattern "ProgramData") {
    $ExpectedInstallPath = "$env:GITPYUP_INSTALL_PARENT\Miniforge3"
    $InstallType = "AllUsers"
} else {
    $ExpectedInstallPath = "$env:UserProfile\Miniforge3"  # single user install
    $InstallType = "JustMe"
}

# find Miniforge install paths
if (Test-Path $ExpectedInstallPath) {
    $MiniforgeInstallPath = $ExpectedInstallPath
} elseif (Test-Path "$env:ProgramData\Miniforge3") {
    $MiniforgeInstallPath = "$env:ProgramData\Miniforge3"
} elseif (Test-Path "$env:UserProfile\Miniforge3") {
    $MiniforgeInstallPath = "$env:UserProfile\Miniforge3"
} else {
    Write-Log "Miniforge install folder not found."
}
if ($MiniforgeInstallPath) {
    Write-Log "Miniforge install path: $MiniforgeInstallPath"
    # check if install location matches expected location
    if ($MiniforgeInstallPath -ne $ExpectedInstallPath) {
        Write-Log "Miniforge install path does not match expected path.  Uninstalling..." 
        # allways uninstall with elevation to avoid permission issues
        Start-Process $MiniforgeInstallPath\Uninstall-Miniforge3.exe -Wait -ArgumentList "/S" -Verb RunAs
        # waiting doesn't work, sleep for 20 seconds to allow uninstall to complete
        Start-Sleep -Seconds 20
    }
}

$MiniforgeInstallPath = $ExpectedInstallPath
$CondaBat = "$MiniforgeInstallPath\condabin\conda.bat"
$Conda = @{
    FilePath = $CondaBat
    NoNewWindow = $true
    Wait = $true
}

$MiniforgeInstall = {
    param(
        [string]$MiniforgeInstallPath,
        [string]$InstallType,
        [hashtable]$Conda
    )

    . "./Utility-Functions.ps1"
    Start-Logging

    # remove Miniforge3 folder if it exists
    if (Test-Path "$MiniforgeInstallPath") {
        Write-Log "Miniforge folder found, removing..."
        Remove-Item -Recurse -Force $MiniforgeInstallPath
        Write-Log "...Miniforge folder removed"
    }

    # check current folder for Miniforge exe
    $InstallerName = "Miniforge3-Windows-x86_64.exe"
    $DownloadLocation = "$env:UserProfile\Downloads\$InstallerName"

    if (Test-Path $InstallerName) {
        Write-Log "Miniforge already downloaded"
        $Installer = "$PWD\$InstallerName"
    } else {
        if (Test-Path $DownloadLocation) {
            Write-Log "Miniforge already downloaded"
        } else {
            Write-Log "Miniforge downloading..."
            $Link = "https://github.com/conda-forge/miniforge/releases/latest/download/$InstallerName"
            Invoke-WebRequest $Link -OutFile $DownloadLocation
    Write-Log "...Miniforge downloaded"
        }
        $Installer = $DownloadLocation
    }

    # unblock the installer
    Unblock-File $Installer
    
    Write-Log "Installing Miniforge..."
    $ArgumentList = "/InstallationType=JustMe /RegisterPython=1 /AddToPath=0 /S /D=$MiniforgeInstallPath"
    $Proc = Start-Process $Installer -Wait -ArgumentList $ArgumentList -PassThru
    if ($Proc.ExitCode -ne 0) {
        Write-Log "Miniforge installation failed" -Level "ERROR"
    } else {
        Write-Log "...Miniforge installed"
        # 20240905 Miniforge Users need full permissions to run conda
        if ($InstallType -eq "AllUsers") {
            Write-Log "Granting permissions to Miniforge folder. This can take over 30 minutes..."
            # inheritance, traversal, quiet
            icacls $MiniforgeInstallPath /grant:r "Users:(OI)(CI)F" /T /Q # full permissions
        }
    }
    $Proc = Start-Process @Conda -ArgumentList init
    Write-Log "...Miniforge initialized"
}
$MiniforgeInstallArgs = $MiniforgeInstallPath, $InstallType, $Conda
$MiniforgeInstallEncoded, $MiniforgeInstallArgsEncoded = ConvertTo-Base64String $MiniforgeInstall $MiniforgeInstallArgs

# Check if miniforge's conda.bat runs
$CondaVersion = Get-StandardOutput -Command "$CondaBat --version"
if ($CondaVersion | Select-String -Pattern "CommandNotFoundException") {
    if ($InstallType -eq "AllUsers") {
        # Start-Process -FilePath "powershell" -Verb RunAs -Wait -ArgumentList (
        Start-Process -FilePath "powershell" -Wait -NoNewWindow -ArgumentList (
            "-EncodedCommand $MiniforgeInstallEncoded",
            "-EncodedArguments $MiniforgeInstallArgsEncoded"
        )
    } else {
    & $MiniforgeInstall $MiniforgeInstallPath $InstallType $Conda
    }
} else {
    Write-Log "Miniforge3 already available"
    Write-Log "version: $CondaVersion"
}

# in case installed but not initialized
$Proc = Start-Process @Conda -ArgumentList init
Write-Log "...Miniforge initialized"

$EnvSetupScript = {
    param(
        [string]$EnvName,
        [string]$MiniforgeInstallPath,
        [string]$InstallType
    )

    # logging
    . "./Utility-Functions.ps1"
    Start-Logging

    # this prevents a halts due to an interactive conda message about reporting errors
    conda config --set report_errors false   

    # set conda to use the system truststore
    conda config --set ssl_verify truststore

    # Check for existing conda environment
    # configure path to save environments depending on installation type
    if ($InstallType -eq "AllUsers") {
        $EnvDir = "$env:ProgramData\.conda\envs"
    } else {
        $EnvDir = "$env:UserProfile\.conda\envs"
    }
    
    # make sure the envs directory exists
    New-Item -Path $EnvDir -ItemType Directory -Force
    # Create a .condarc file in the root dir of the MiniForge installation
    $CondarcPath = "$MiniforgeInstallPath\.condarc"
    $CondarcContent = 
"channels:
    - conda-forge
ssl_verify: truststore
envs_dirs:
        - $EnvDir
    "
    Set-Content -Force -Path $CondarcPath -Value $CondarcContent

    # attempt to update conda base environment
    Write-Log "updating conda base env..."
    $response = conda update -n base -c conda-forge conda -y
    Write-Log ($response | Out-String)

    # only wait if in debug mode
    if ($Env:GITPYUP_DEPLOY_DEBUG) {
        Wait-Logging
        Read-Host -Prompt "Press enter key to exit" | Out-Null
    }
}
$EnvSetupArgs = "base", $MiniforgeInstallPath, $InstallType
$EncodedEnvSetup, $EncodedEnvSetupArgs = ConvertTo-Base64String $EnvSetupScript $EnvSetupArgs

# needs to be a new process to have access to conda command
Start-Process -FilePath "powershell" -Wait -NoNewWindow -ArgumentList (
    "-EncodedCommand $EncodedEnvSetup",
    "-EncodedArguments $EncodedEnvSetupArgs"
)

Return $LASTEXITCODE