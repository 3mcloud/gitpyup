<#
This script installs Miniforge3 for the 3M corporate environment.
It can be run standalone or as part of gitpyup.
#> 

# check if Utility-Functions.ps1 is present
. "./Utility-Functions.ps1"
Start-Logging

function Write-LogOrHost {
    param(
        [string]$Message
    )
    # check if Logging is available
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $Message
    } else {
        Write-Host $Message
    }
}

Write-LogOrHost "Setup-Python v1"

# check if admin and warn
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$RunningAsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($RunningAsAdmin) {
    if (Test-Path "$Env:TEMP\gitpyup-as-admin") {
        Remove-Item -Force "$Env:TEMP\gitpyup-as-admin"
    } else {
        Write-LogOrHost "Please run this script as a regular user"
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
    Write-LogOrHost "Miniforge install folder not found."
}
if ($MiniforgeInstallPath) {
    Write-LogOrHost "Miniforge install path: $MiniforgeInstallPath"
    # check if install location matches expected location
    if ($MiniforgeInstallPath -ne $ExpectedInstallPath) {
        Write-LogOrHost "Miniforge install path does not match expected path.  Uninstalling..." 
        # allways uninstall with elevation to avoid permission issues
        Start-Process $MiniforgeInstallPath\Uninstall-Miniforge3.exe -Wait -ArgumentList "/S" -Verb RunAs
        # waiting doesn't work, sleep for 20 seconds to allow uninstall to complete
        Start-Sleep -Seconds 20
    }
}

$MiniforgeInstallPath = $ExpectedInstallPath
$Conda = @{
    FilePath = "$MiniforgeInstallPath\condabin\conda.bat"
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
        Write-LogOrHost "Miniforge folder found, removing..."
        Remove-Item -Recurse -Force $MiniforgeInstallPath
        Write-LogOrHost "...Miniforge folder removed"
    }

    Write-LogOrHost "Miniforge not installed, downloading..."
    $Link = "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Windows-x86_64.exe"
    Invoke-WebRequest $Link -OutFile "$env:UserProfile\Downloads\Miniforge3-Windows-x86_64.exe"
    Write-LogOrHost "...Miniforge downloaded"
    Write-LogOrHost "Installing Miniforge..."
    $Installer = "$env:UserProfile\Downloads\Miniforge3-Windows-x86_64.exe"
    $ArgumentList = "/InstallationType=JustMe /RegisterPython=1 /AddToPath=0 /S /D=$MiniforgeInstallPath"
    $Proc = Start-Process $Installer -Wait -ArgumentList $ArgumentList -PassThru
    if ($Proc.ExitCode -ne 0) {
        Write-LogOrHost "Miniforge installation failed" -Level "ERROR"
    } else {
        Write-LogOrHost "...Miniforge installed"
        # 20240905 Miniforge Users need full permissions to run conda
        if ($InstallType -eq "AllUsers") {
            Write-LogOrHost "Granting permissions to Miniforge folder. This can take over 30 minutes..."
            # inheritance, traversal, quiet
            icacls $MiniforgeInstallPath /grant:r "Users:(OI)(CI)F" /T /Q # full permissions
        }
    }
    $Proc = Start-Process @Conda -ArgumentList init
    Write-LogOrHost "...Miniforge initialized"
    Write-LogOrHost "updating conda base env..."
    $Proc = Start-Process @Conda -ArgumentList "update -n base -c conda-forge conda -y"
}

# Check if miniforge's conda.bat runs
$CondaVersion = conda --version
if (!($CondaVersion)) {
    & $MiniforgeInstall $MiniforgeInstallPath $InstallType $Conda
} else {
    Write-LogOrHost "Miniforge3 already available"
    Write-LogOrHost "version: $CondaVersion"
}

$EnvSetupScript = {
    param(
        [string]$Repo,
        [string]$MiniforgeInstallPath,
        [string]$InstallType
    )

    # logging
    . "./Utility-Functions.ps1"
    Start-Logging

    $BundlePath = "$env:ProgramData\tls-ca-bundle.pem"
    if (Test-Path $BundlePath) {
        Remove-Item -Force $BundlePath
    }

    # this is needed if corporation uses a SSL inspection aka MitM attack
    # this bundle is for our corporation
    $URL = "https://raw.githubusercontent.com/nikolarobottesla/bacon/main/bits.txt"
    Write-LogOrHost "downloading tls bundle..."
    Invoke-WebRequest $URL -OutFile $BundlePath
    # are these redundant because setting the .condarc file?
    conda config --set ssl_verify True
    conda config --set ssl_verify $BundlePath

    # Check for existing conda environment
    # TODO get any existing conda environment directories

    # configure path to save environments depending on installation type
    if ($InstallType -eq "AllUsers") {
        $EnvDir = "$env:ProgramData\.conda\envs"
    } else {
        $EnvDir = "$env:UserProfile\.conda\envs"
    }

    # Create a .condarc file in the root dir of the MiniForge installation
    $CondarcPath = "$MiniforgeInstallPath\.condarc"
    $CondarcContent = 
"channels:
    - conda-forge
ssl_verify: $BundlePath
envs_dirs:
    - $EnvDir
"
    Set-Content -Force -Path $CondarcPath -Value $CondarcContent

    # function to check if pip has SSL errors, return true if error detected
    function Test-PipTlsError {
        # Define the command
        $Command = "conda run -n $Repo python -m pip install --dry-run tiny"
        Write-LogOrHost "Running SSL test command: $Command"
        # Create a temporary file for output
        $TempFile = [System.IO.Path]::GetTempFileName()
        # Execute the command and redirect output to the temporary file
        Start-Process -FilePath "powershell.exe" -ArgumentList "-Command", $Command -RedirectStandardOutput $TempFile -NoNewWindow -Wait
        # Read the output from the temporary file
        $TlsTest = Get-Content -Path $TempFile
        # Clean up the temporary file
        Remove-Item -Path $TempFile

        # $TlsTest = conda run -n $Repo python -m pip install --dry-run tiny
        if ($TlsTest | Select-String -Pattern "SSL: CERTIFICATE_VERIFY_FAILED") {
            Write-LogOrHost "pip SSL error detected"
            return $true
        } else {
            Write-LogOrHost "pip SSL error not detected"
            return $false
        }
    }

    # check if pip has SSL errors, install or uninstall pip-system-certs
    if (Test-PipTlsError) {
        # check if pip-system-certs is installed
        if (!(conda run -n $Repo python -m pip list | Select-String -Pattern pip-system-certs)) {
            # patch pip and requests to use system certs
            Write-LogOrHost "installing pip-system-certs..."
            conda install -n $Repo pip-system-certs -y
            # conda run -n $Repo python -m pip install --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org pip-system-certs
        }

        # check if pip still has SSL errors, set pip to use the tls-ca-bundle.pem
        if (Test-PipTlsError) {
            Write-LogOrHost "pip still has SSL errors, setting pip to use tls-ca-bundle.pem"
            conda run -n $Repo python -m pip config set global.cert $BundlePath
        }
    }

    # only wait if in debug mode
    if ($Env:GITPYUP_DEPLOY_DEBUG) {
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