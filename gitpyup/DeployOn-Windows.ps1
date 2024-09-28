param(
    # '-debugMode' switch to enable debug mode
    [switch]$DebugMode = $false,
    # -UseDev switch to checkout dev branch instead of main
    [switch]$UseDev = $false
)

# variables
$scriptVersion = "v1"
$repo = "gitpyup"
$Env:REPO = $repo

# shortcut parent depends on installation type
$env:GITPYUP_SHORTCUT_PARENT_USER = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$repo"
$env:GITPYUP_SHORTCUT_PARENT_ALL = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\$repo"
$toRemove = @(
    "$env:GITPYUP_SHORTCUT_PARENT_USER\$repo-update.lnk",
    "$env:GITPYUP_SHORTCUT_PARENT_USER\$repo-uninstall.lnk"
    "$env:GITPYUP_SHORTCUT_PARENT_ALL\$repo-update.lnk",
    "$env:GITPYUP_SHORTCUT_PARENT_ALL\$repo-uninstall.lnk"
)

# setup logging
$sharepath  = $env:USERPROFILE + "\Downloads"
$username   = $env:USERNAME
$hostname   = hostname
$datetime   = Get-Date -f 'yyyyMMddHHmmss'
$filename   = "Log-${username}-${hostname}-${datetime}.txt"
$logPath    = Join-Path -Path $sharepath -ChildPath $filename

$shortcutScript = {
    param(
        [array]$toRemove,
        [array]$toAdd
    )

    . "./Utility-Functions.ps1"
    Start-Logging

    # TODO: check if have permissions to remove, if needed get permissions, ideally from existing elevated process
    # remove old shortcuts
    foreach ($shortcut in $toRemove) {
        if (Test-Path $shortcut) {
            Write-Log "Removing start menu shortcut '$shortcut'"
            Remove-Item -Force $shortcut
        }
    }

    # create shortcut's parent directory if it does not exist
    $shortcutParent = Split-Path -Path $toAdd[0]['shortcut_path'] -Parent
    if (!(Test-Path $shortcutParent)) {
        New-Item -Path $shortcutParent -ItemType "directory" -Force
    }

    # initialize shortcut creation
    $shell = New-Object -ComObject WScript.Shell
    
    # loop through each shortcut in $toAdd
    foreach ($item in $toAdd) {
        $shortcutPath = $item['shortcut_path']
        Write-Log "Creating or updating start menu shortcut '$shortcutPath'"
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.WorkingDirectory = Convert-Path $item['working_directory']
        $shortcut.TargetPath = $item['target_path']
        if ($shortcut.TargetPath | Select-String -Pattern "powershell") {
            $scriptPath = Convert-Path $item['script_name']
            $shortcut.Arguments = "-File $scriptPath"
        }
        $shortcut.Save()
    }
    
    # Write-Log "shortcut path is $updateShortcutPath"
    Write-Log "When needed use start menu shortcut '$repo-update' to update this application."

    # TODO comment out for production
    # Read-Host -Prompt "Press enter key to close this window" | Out-Null
}
function ConvertTo-Base64String {
    param(
        $Script = $null,
        $Arguments = @()
    )
    
    if ($Script) {
        $encodedScript = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($Script))
    }

    $encodedArgs = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
        [System.Management.Automation.PSSerializer]::Serialize($Arguments)
    ))

    if ($Script -and $Arguments) {
        return $encodedScript, $encodedArgs
    } elseif ($Script) {
        # Write-Host "Returning encoded script"
        return $encodedScript
    } elseif ($Arguments) {
        # Write-Host "Returning encoded arguments"
        return $encodedArgs
    } else {
        Write-Error "No script or arguments provided"
    }
}

function Start-Logging {
    param(
        [switch]$PrintVersion = $false
    )
    Import-Module Logging
    Set-LoggingDefaultLevel -Level "INFO"
    Add-LoggingTarget -Name Console
    Add-LoggingTarget -Name File -Configuration @{Path = $logPath}
    if ($PrintVersion) {
        $version = $PSVersionTable.PSVersion.ToString()
        Write-Log "PSVersion: $version"
    }
}

function Reset-Path {
    # reload path from machine and user
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") +
    ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

$encodedShortcutScript = ConvertTo-Base64String -Script $shortcutScript

# literal string defining variables and functions needed in other scripts
$utilityString = '$logPath = "' + $logPath + '"
function Start-Logging {
' + ${function:Start-Logging} + '
}
$encodedShortcutScript = "' + $encodedShortcutScript + '"
$ProgressPreference = "SilentlyContinue"  # speeds up Invoke-WebRequest
function ConvertTo-Base64String {
' + ${function:ConvertTo-Base64String} + '
}
function Reset-Path {
' + ${function:Reset-Path} + '
}
'

# save the Start-Logging function to a file
# define the path to the file
$utilityFunctionsPath = Join-Path -Path (Get-Location).Path -ChildPath "Utility-Functions.ps1"
# Write the function to the file
Set-Content -Force -Path $utilityFunctionsPath -Value $utilityString

. $utilityFunctionsPath

if (Get-Module -ListAvailable -Name Logging) {
    Start-Logging -PrintVersion
    $startLoggingLater = $false
} else {
    $startLoggingLater = $true
}

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

Write-LogOrHost "DeployOn-Windows version: $scriptVersion"
if ($DebugMode) {
    Write-LogOrHost "Debug mode is enabled"
    $Env:GITPYUP_DEPLOY_DEBUG = $true
} else {
    $Env:GITPYUP_DEPLOY_DEBUG = $false
}

# check if we have internet access exit if false
$internet = Test-Connection -ComputerName github.com -Count 1 -Quiet
if (!$internet) {
    Write-LogOrHost "Internet connectivity is required to run this script. Connect to the internet and run this script again."
    Read-Host -Prompt "Press enter key to exit" | Out-Null
    exit
}

function Save-ToTemp {
    param(
        [string]$Filename,
        [string]$Content = $null
    )
    Return New-Item -Path $Env:TEMP -Name $Filename -ItemType "file" -Force `
        -Value $Content
}

# check if admin and prompt to confirm if you are
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$runningAsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($runningAsAdmin) {
    Write-LogOrHost "Admin/elevated priveleges detected!
Please run this script as the user that will use it.
On most devices this means rigth click and select 'run with PowerShell'"
    $confirm = Read-Host -Prompt "Do you want to continue anyway? (y/n)"
    if ($confirm -eq "y") {
        Write-LogOrHost "Proceding as Admin"
        $return = Save-ToTemp -Filename "$repo-as-admin"
    } else {
        exit
    }
}

# determine install type
$installedAll = Test-Path "$env:ProgramData\$repo"
if ($installedAll) {
    $installType = "AllUsers"
    $installPath = "$env:ProgramData\$repo"
    $shortcutParent = $env:GITPYUP_SHORTCUT_PARENT_ALL
} else {
    # single user install
    $installType = "SingleUser"
    $installPath = "$env:APPDATA\$repo"
    $shortcutParent = $env:GITPYUP_SHORTCUT_PARENT_USER
}

# if installed, make sure running script from the installed location
$updateShortcutPath = "$shortcutParent\$repo-update.lnk"
$shortcutExists = Test-Path $updateShortcutPath
$runFromInstalled = (Get-Location).Path -eq "$installPath\$repo"
$installed = Test-Path "$installPath\$repo"  # the gitpyup/gitpyup directory
if ($installed -and $shortcutExists -and !($runFromInstalled)) {
    Write-LogOrHost "Error: $repo allready installed.
Must run the startmenu shortcut '$repo-update' to update.
You should delete this copy of the scripts and the deploy key."
# TODO, users don't appear to follow the directions of this message, automatically jump to the update shortcut
    Read-Host -Prompt "Press enter key to exit" | Out-Null
    # jump to shortcut? 
    exit
}

function Get-SupportStatus {
    $loggingInstalled = Get-Command Write-Log -ErrorAction SilentlyContinue
    $psYamlInstalled = Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue
    $gitInstalled = Get-Command git -ErrorAction SilentlyContinue
    $sshInstalled = Get-Command ssh -ErrorAction SilentlyContinue
    if ($gitInstalled -and $sshInstalled -and $loggingInstalled -and $psYamlInstalled) {
        return $True
    } else {
        return $False
    }
}

# script to install support software
$installSupportSoftware = {
    #NOTE: environment variables made by the user are not availble in the admin script block

    # make sure NuGet provider is installed
    Install-PackageProvider -Name "NuGet" -Force

    # Trust the PSGallery
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

    $requiredModules = @("Logging", "powershell-yaml")

    # install required modules if not installed
    foreach ($module in $requiredModules) {
        if (!(Get-Module -ListAvailable -Name $module)) {
            Write-Host "installing $module module..."
            Install-Module $module
        }
    }

    . "./Utility-Functions.ps1"
    Start-Logging -PrintVersion
    
    function Install-ViaWinget {
        param(
            [string]$AppTestCommand,
            [string]$AppId
        )

        $Installed = $false        
        $NumAttempts = 1
        # install app if it is not installed
        While (!($Installed) -and ($NumAttempts -lt 4)) {
            if (!(Get-Command $AppTestCommand -ErrorAction SilentlyContinue)) {
                Write-Log "Installing $AppId attempt $NumAttempts."
                $Result = winget install --id=$AppId -e --source winget --accept-source-agreements
                Write-Log "$Result.Trim()"
                Reset-Path
            }

            if (Get-Command $AppTestCommand -ErrorAction SilentlyContinue) {
                Write-Log "$AppTestCommand found."
                $Installed = $true
            } else {
                if ($NumAttempts -eq 1) {
                    # Published by Microsoft
                    $Result = Install-Module -Name Microsoft.WinGet.Client -force
                    Write-Log "$Result.Trim()"
                } elseif ($NumAttempts -eq 2) {
                    # # install 
                    # Install-Script -Name winget-install -Force
                    # # Install/update winget
                    # winget-install -CheckForUpdate
    
                    $Result = Repair-WinGetPackageManager -Latest -Force
                    Write-Log "$Result.Trim()"
                    # https://github.com/microsoft/winget-cli/issues/1826
                }
            }
            $NumAttempts ++
        }

    }

    Install-ViaWinget -AppTestCommand "git" -AppId Git.Git

    Install-ViaWinget -AppTestCommand "ssh" -AppId Microsoft.OpenSSH.Beta

    Write-Log "elevated script complete"
    # Read-Host -Prompt "Press enter key to close this window" | Out-Null
    Start-Sleep -Seconds 2
}
$encodedCommand = ConvertTo-Base64String -Script $installSupportSoftware

if (!(Get-SupportStatus) -or $DebugMode) {
    Write-LogOrHost "Installing support software (git, ssh, etc)."
    # run the admin script block as administrator
    Start-Process -FilePath "powershell" -Verb RunAs -Wait -ArgumentList "-EncodedCommand $encodedCommand"
    Reset-Path
}
if ($startLoggingLater) {
    Start-Logging
}
if (!(Get-SupportStatus)) {
    Write-Log "Winget failed to install Git, openSSH, Logging or powershell-yaml."
    Write-Log "You may install them manually and re-run DeployOn-Windows.ps1"
    Read-Host -Prompt "Press enter key to exit" | Out-Null
    exit
} else {
    Write-Log "Support software installed or allready available."
}

<# The code related to the known_hosts file prevents a confusing prompt the 
prompt can be confusing because it doesn't show the user's output when they
respond #>

# create empty known_hosts file if it does not exist
$knownHosts = "$env:USERPROFILE\.ssh\known_hosts"
if (!(Test-Path $knownHosts)) {
    Write-Log "creating known_hosts file..."
    New-Item -Path $knownHosts -ItemType File -Force
}
# update known_hosts file with github.com and github.mmm.com keys
$knownHostsContent = Get-Content $knownHosts
$sites = @("github.com", "github.mmm.com")
foreach ($site in $sites){
    $knownHostsContent = $knownHostsContent | Select-String -Pattern $site -NotMatch | Select-Object -expa line
    Write-Log "adding $site to known_hosts file."
    $siteKeys = ssh-keyscan $site
    $knownHostsContent = $knownHostsContent + $siteKeys
}
Set-Content -Path $knownHosts -Value $knownHostsContent

<# load <application>.yml file(s) #>

# find all .yml files in the current directory
$ymlFiles = @(Get-ChildItem -Path "." -Filter "*.yml")
$yamlFiles = @(Get-ChildItem -Path "." -Filter "*.yaml")

# combine the two arrays
$allYmlFiles = $ymlFiles + $yamlFiles

# load the yml files
foreach ($file in $allYmlFiles) {
    # read the file into a string
    $fileContent = Get-Content -Path $file.FullName -Raw
    $appConfig = ConvertFrom-Yaml $fileContent

    # extract any deploy keys to temp location
    foreach ($key in $appConfig.Keys) {
        $value = $appConfig[$key]
        if ($key.ToLower().Contains("deploy_key")) {
            $deployKeyPath = Save-ToTemp -Filename $key -Content $value
        }

        # make git use deploy key
        $deployKeyPath = Convert-Path $deployKeyPath
        $Env:GIT_SSH_COMMAND = "ssh -i '$deployKeyPath' -o IdentitiesOnly=yes"
        
        # clone the repo

        # remove temp deploy key
        Remove-Item -Path $deployKeyPath

        # remove the GIT_SSH_COMMAND environment variable
        $Env:GIT_SSH_COMMAND = $null
    }

    

}
# applications = @{
#     "clarke" = @{
#         "name" = "clarke"
#         "repo" = ""
#         "app_type" = "python"
#         "app_path" = ""
#         "shortcut_name" = "clarke-jupyter"
#         "shortcut_path" = ""
#         "install_path" = ""
#     }
# }


# functionalize the following code so it can be called for gitpyup and each application
function Set-DeployKeyPermissions {
    param(
        [string]$Key
    )
    
    if (Test-Path $Key) {
        # Reset Users (removes most including UNKNOWN SID)
        Write-Log (Icacls $Key /T /Q /C /RESET)
        # Remove Inheritance:
        Icacls $Key /c /t /Inheritance:d
        # Set Ownership to Owner:
            # Key's within $env:UserProfile:
            Icacls $Key /c /t /Grant ${env:UserName}:F
            # Key's outside of $env:UserProfile:
            TakeOwn /F $Key
            Icacls $Key /c /t /Grant:r ${env:UserName}:F
        # Remove All Users, except for Owner:
        Icacls $Key /c /t /Remove:g Administrator "Authenticated Users" BUILTIN\Administrators BUILTIN Everyone System Users
    } else {
        # check if git remote is reachable
        git ls-remote
        if ($LASTEXITCODE -eq 0) {
            Write-Log "No deploy key found, but git remote is reachable."
        } else {
            Write-Log "Missing $($repo)_deploy_key file. Place it in the same folder as this script. 
            It can be downloaded from Project Edith->Documents->Technical->Software"
            Read-Host -Prompt "Press enter key to exit" | Out-Null
            exit
        }
    }
}

# check if in a git repo
if (git rev-parse --is-inside-work-tree) {
    Write-Log "in a git repo, pulling"
    git pull
# elseif in repo scripts directory but not a git repo
} elseif ((Get-Item ".").Parent.Name -ceq $repo) {
    # move to repo root if in scripts directory
    Set-Location "../."
    Write-Log "converting to git repo"    
    git init
    git remote add origin git@github.com:3M-Cloud/$repo.git
    git fetch
    git reset origin/main  # Required when the versioned files existed in path before "git init" of this repo.
    git checkout -t origin/main
    Set-Location "scripts"
} else {
    # Install for all users or current user
    $confirm = ""
    while(($confirm -ne "y") -and ($confirm -ne "n"))
    {
        $confirm = Read-Host -Prompt "All user install (y/n)? All user install is longer. Only use if necessary. Recommend 'n'"
    }
    if ($confirm -eq "y") {
        # all users
        Set-Location $env:ProgramData
        $installType = "AllUsers"
        $installPath = "$env:ProgramData\$repo"
        $shortcutParent = $env:GITPYUP_SHORTCUT_PARENT_ALL
    } else {
        # current user
        Set-Location $env:APPDATA
        $installType = "SingleUser"
        $installPath = "$env:APPDATA\$repo"
        $shortcutParent = $env:GITPYUP_SHORTCUT_PARENT_USER
    }
    Write-Log "cloning $repo repo in appdata directory..."
    git clone git@github.com:3M-Cloud/$repo.git
    Set-Location $installPath\scripts
    if ($UseDev) {
        git checkout dev
    }

    Copy-Item $deployKeyPath .
    Copy-Item $utilityFunctionsPath .
    Write-Log "The deploy key and script have been copied to the appdata directory.
        You may delete your downloaded copy.
    "
    
    # shortcut creation
    $toAdd = @(
        @{ "shortcut_path" = "$shortcutParent\$repo-update.lnk";
           "script_name" = "$repo-deploy-windows.ps1";
           "target_path" = "powershell.exe";
           "working_directory" = "."},
        @{ "shortcut_path" = "$shortcutParent\$repo-uninstall.lnk";
           "script_name" = "$repo-uninstall.ps1";
           "target_path" = "powershell.exe";
           "working_directory" = "."}
    )
    $shortcutArgs = $toRemove, $toAdd
    $encodedShortcutArgs = ConvertTo-Base64String -Arguments $shortcutArgs

    if ($installType -eq "AllUsers") {
        Start-Process -FilePath "powershell" -Verb RunAs -Wait -ArgumentList (
            "-EncodedCommand $encodedShortcutScript",
            "-EncodedArguments $encodedShortcutArgs"
        )
    } else {
        # could use $shortcutScript directly but this is more consistent with AllUsers
        # $shortcutScript not available in py-setup-windows.ps1
        Start-Process -FilePath "powershell" -Wait -NoNewWindow -ArgumentList (
            "-EncodedCommand $encodedShortcutScript",
            "-EncodedArguments $encodedShortcutArgs"
        )
    }
}

# set permissions on the notebooks directory
if ($installType -eq "AllUsers") {
    $notebooksPath = "$installPath\notebooks"
    icacls $notebooksPath /grant:r "Users:(OI)(CI)F" /T
} 

$env:GITPYUP_SHORTCUT_PARENT = $shortcutParent
$env:GITPYUP_INSTALL_PARENT = Split-Path -Path $installPath -Parent

$confirm = ""
while(($confirm -ne "y") -and ($confirm -ne "n"))
{
    $confirm = Read-Host -Prompt "Do you want to install or update National Instruments drivers? (y/n)"
    if ($confirm -eq "y") {
        $proc = Start-Process -FilePath "powershell" -Verb RunAs -PassThru -ArgumentList "-Command & '.\ni-setup-windows.ps1'"
        $handle = $proc.Handle
        $proc.WaitForExit();
        if ($proc.ExitCode -ne 0) {
            Write-Log "NI setup failed, re-run $repo-update shortcut to try again." -Level 'ERROR'
        } else {
            Write-Log "NI setup complete."
        }
    }
}

$confirm = ""
while(($confirm -ne "y") -and ($confirm -ne "n"))
{
    $confirm = Read-Host -Prompt "Do you want to install or update $($repo)'s python environment? (y/n)
    This includes creating or updating the shortcut clark-jupyter"
    if ($confirm -ceq "y") {
        $proc = Start-Process -FilePath "powershell" -PassThru -ArgumentList "-Command & '.\py-setup-windows.ps1'"
        $handle = $proc.Handle
        $proc.WaitForExit();
        if ($proc.ExitCode -ne 0) {
            Write-Log "Python setup failed, re-run $repo-update shortcut to try again." -Level 'ERROR'
        } else {
            Write-Log "Python setup complete."
        }
    }
}

# $repo-update shortcut
# & $shortcutScript

# check and prompt for restart
if (Test-Path "$Env:TEMP\ni-restart-needed") {
    Write-Log "You installed or updated the National Instruments drivers you must restart your computer."
    Remove-Item -Force "$Env:TEMP\ni-restart-needed"
}

Read-Host -Prompt "$repo-deploy-windows is complete, press enter key to close this window" | Out-Null