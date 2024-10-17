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
$ENV:GITPYUPUTILSNAME = "Utility-Functions.ps1"

# Test working directory and move to the script directory if needed
if (Test-Path "gitpyup") {
    Set-Location "gitpyup"
}

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

# script to create start menu shortcuts
$shortcutScript = {
    param(
        [array]$toRemove,
        [array]$toAdd
    )

    . "./$ENV:GITPYUPUTILSNAME"
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
        $directory = Convert-Path $item['working_directory']
        $shortcut.WorkingDirectory = Convert-Path $item['working_directory']
        $shortcut.TargetPath = $item['target_path']
        if ($item.ContainsKey('script_name')) {
            if ($item['script_name'] -gt 0) {
                # find the script path in the shortcut's working directory
                $scriptPath = Get-ChildItem -Path $directory -Filter $item['script_name'] -Recurse
                # $scriptPath = Convert-Path $item['script_name']
                $shortcut.Arguments = "-File $scriptPath"
            }
        }
        $shortcut.Save()
    }

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
$utilityFunctionsPath = Join-Path -Path (Get-Location).Path -ChildPath $ENV:GITPYUPUTILSNAME
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

    . "./$ENV:GITPYUPUTILSNAME"
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

# install type hash tables
$installAll = @{
    'type' = "AllUsers"
    'path' = "$env:ProgramData\$repo"
    'shortcutParent' = $env:GITPYUP_SHORTCUT_PARENT_ALL
}
$installUser = @{
    'type' = "SingleUser"
    'path' = "$env:APPDATA\$repo"
    'shortcutParent' = $env:GITPYUP_SHORTCUT_PARENT_USER
}

# determine install type
$installedAll = Test-Path "$env:ProgramData\$repo"
$installedUser = Test-Path "$env:APPDATA\$repo"
$installedDev = git rev-parse --is-inside-work-tree # checks if in a git repo
if ($installedAll) {
    # all user install detected
    $install = $installAll
} elseif ($installedUser) {
    # single user install detected
    $install = $installUser
} elseif ($installedDev) {
    # dev install detected
    $install = $installUser
    $install.path = Split-Path (Get-Location).Path -Parent
} else {  # not installed
    # Install for all users or current user
    $confirm = ""
    while(($confirm -ne "y") -and ($confirm -ne "n"))
    {
        $confirm = Read-Host -Prompt "All user install (y/n)? All user install is longer. Only use if necessary. Recommend 'n'"
    }
    if ($confirm -eq "y") {
        # all users
        $install = $installAll
    } else {
        # single user
        $install = $installUser
    }
}

# TODO how does one install a second app?
# if installed, make sure running script from the installed location
Write-LogOrHost "Updating $repo"
$updateShortcutPath = Join-Path $install.shortcutParent "$repo-update.lnk"
$shortcutExists = Test-Path $updateShortcutPath
$repoSubDir = Join-Path $install.path $repo
$runFromInstalled = (Get-Location).Path -eq $repoSubDir
$installed = Test-Path $repoSubDir
if ($installed -and $shortcutExists -and !($runFromInstalled)) {
    Write-LogOrHost "Error: $repo allready installed.
Must run the startmenu shortcut '$repo-update' to update.
You should delete this copy of the scripts and the deploy key."
# TODO, users don't appear to follow the directions of this message, automatically jump to the update shortcut
    Read-Host -Prompt "Press enter key to exit" | Out-Null
    # jump to shortcut? 
    exit
}

<# The code related to the known_hosts file prevents a confusing prompt. The 
prompt can be confusing because it doesn't show the user's input when user
types #>

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
            Write-Log "deploy key not found, Set-DeployKeyPermissions should not have been called."
        }
    }
}

# update or clone the repo
function Update-LocalRepo {
    param(
        [string]$Repo,
        [string]$CloneURI,
        [hashtable]$Install
    )

    Write-Log "Updating or cloning $Repo repo..."

    # save initial location
    $initialLocation = Get-Location

    # check if the repo is in any parent directory
    for ($i = 0; $i -lt 5; $i++) {
        $parentDir = Split-Path (Get-Location).Path -Parent
        $someWhereInApp = Join-Path $parentDir $Repo
        $repoInParent = Test-Path $someWhereInApp
        if ($repoInParent) {
            break
        }
        else {
            Set-Location $parentDir
        }
    }

    # check if in the git repo you want to update or clone
    if ((git rev-parse --is-inside-work-tree) -and $repoInParent) {
        Set-Location $someWhereInApp
        $appPath = git rev-parse --show-toplevel 
        Write-Log "in the git repo, pulling"
        # $appPath was getting assigned some text from git pull output
        # Write-Log seems to fix
        Write-Log (git pull) 
    } else {
        # cloning
        $parentPath = Split-Path -Path $Install.path -Parent
        $appPath = Join-Path $parentPath $Repo

        Set-Location $parentPath
        Write-Log "cloning $Repo repo into $appPath ..."
        git clone $CloneURI
        Set-Location $appPath
        if ($UseDev) {
            git checkout dev
        }
    }

    # set permissions on the repo directory
    if ($Install.type -eq "AllUsers") {
        icacls $appPath /grant:r "Users:(OI)(CI)F" /T
    }

    # set location back to initial
    Set-Location $initialLocation

    return $appPath
}

<# New-Shortcuts creates new or updates existing shortcuts. It uses the
shortcuts.yml file found in the repo to determine the shortcuts to create.
#>
function Parse-Shortcuts {
    param(
        [hashtable]$Install,
        [array]$Shortcuts,
        [string]$AppPath
    )

    $parsedShortcuts = @()

    foreach ($shortcut in $Shortcuts) {
        
        $parsed = @{
            "shortcut_path" = "$($Install.shortcutParent)\$($shortcut.name).lnk";
            "script_name" = $shortcut.script;
            "target_path" = $shortcut.target;
            "working_directory" = $AppPath
        }
        
        $parsedShortcuts += $parsed
    }

    return $parsedShortcuts
}

# initialize shortcuts to add array
$toAdd = @()

# load the yml files
foreach ($file in $allYmlFiles) {
    # read the file into a string
    $fileContent = Get-Content -Path $file.FullName -Raw
    $configRoot = ConvertFrom-Yaml $fileContent
    $apps = $configRoot.applications

    # loop through each application
    foreach ($application in $apps) {
        $name = $application.name
        $cloneURI = $application.clone_uri

        # check for and extract deploy key if it exists
        if ($application.ContainsKey("deploy_key")) {
            if ($null -eq $application.deploy_key) {
                Write-Log "$name deploy_key is empty"
            } elseif ($application.deploy_key -notlike "-----BEGIN OPENSSH PRIVATE KEY-----*") {
                Write-Log "$name deploy_key doesn't look like a private key"
            } else {
                $deployKeyPath = Save-ToTemp -Filename "$name-deploy_key" -Content $application.deploy_key
            
                # make git use deploy key
                $deployKeyPath = Convert-Path $deployKeyPath # needed?
                $Env:GIT_SSH_COMMAND = "ssh -i '$deployKeyPath' -o IdentitiesOnly=yes"
                Set-DeployKeyPermissions -Key $deployKeyPath
            }
        }
        
        # clone the repo
        $appPath = Update-LocalRepo -Repo $name `
                                    -CloneURI $cloneURI `
                                    -Install $install
        
        # load gitpyup.yml
        $configYmlPath = Join-Path $appPath "$repo.yml"
        if (Test-Path $configYmlPath) {
            # config file found
            $repoConfigRaw = Get-Content -Path $configYmlPath -Raw
            $repoConfig = ConvertFrom-Yaml $repoConfigRaw

            if ($repoConfig.ContainsKey("shortcuts")) {                    
                $shortcuts = $repoConfig.shortcuts

                # add parsed shortcuts to $toAdd
                $toAdd += Parse-Shortcuts -Install $install `
                                          -Shortcuts $shortcuts `
                                          -AppPath $appPath
            }
        }

        # clean up deploy key
        if ($deployKeyPath) {                
            # remove temp deploy key
            Remove-Item -Path $deployKeyPath
            # clear $deployKeyPath
            $deployKeyPath = $null
            # remove the GIT_SSH_COMMAND environment variable
            $Env:GIT_SSH_COMMAND = $null
        }
    }

    # set the location to gitpyup repo
    Set-Location $repoSubDir
    if (-not (Test-Path $file.Name)){
        # copy the application yml
        Copy-Item $file.FullName .
        Write-Log "The application yml has been copied to $repoSubDir"
    }
}

Set-Location $repoSubDir
if (-not (Test-Path $ENV:GITPYUPUTILSNAME)){
    Copy-Item $utilityFunctionsPath .
    Write-Log "The application yml has been copied to $repoSubDir"
}

$shortcutArgs = $toRemove, $toAdd
$encodedShortcutArgs = ConvertTo-Base64String -Arguments $shortcutArgs

if ($Install.type -eq "AllUsers") {
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

$env:GITPYUP_SHORTCUT_PARENT = $install.shortcutParent
$env:GITPYUP_INSTALL_PARENT = Split-Path -Path $install.path -Parent

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

Write-Log "When needed use start menu shortcut '$repo-update' to update this application."

# check and prompt for restart
if (Test-Path "$Env:TEMP\ni-restart-needed") {
    Write-Log "You installed or updated the National Instruments drivers you must restart your computer."
    Remove-Item -Force "$Env:TEMP\ni-restart-needed"
}

Read-Host -Prompt "$repo installation is complete, press enter key to close this window" | Out-Null