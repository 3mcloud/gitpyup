#Requires -RunAsAdministrator

# logging
# check if Utility-Functions.ps1 is present
if (Test-Path "./$ENV:GITPYUPUTILSNAME") {
    . "./$ENV:GITPYUPUTILSNAME"
    Start-Logging
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

Write-LogOrHost "Setup-NationalInstruments v1"

$ProgressPreference = 'SilentlyContinue'  # speeds up Invoke-WebRequest

$nipm = "$Env:Programfiles\National Instruments\NI Package Manager\nipkg.exe"

$pkg_root = "https://download.ni.com/support/nipkg/products"
$ni4882Version = "23.5"
$visaVersion = "24.0"

# array to configure packages
$packages = @(
    [pscustomobject]@{
        installID = "ni-488.2";
        name = "ni-488-2-$(${ni4882Version}.replace(".", "-"))-released";
        url = "$($pkg_root)/ni-4/ni-488.2/$ni4882Version/released"}
    [pscustomobject]@{
        installID = "ni-visa";
        name = "ni-visa-$(${visaVersion}.replace(".", "-"))-released";
        url = "$($pkg_root)/ni-v/ni-visa/$visaVersion/released"}
)

# Install NIPM if not installed
if (!(Test-Path $nipm)) {
    Write-LogOrHost "NI package manager not installed, downloading..."
    # Download NIPM. The URL can be passed as an argument.
    $nipmUrl ="https://download.ni.com/support/nipkg/products/ni-package-manager/installers/NIPackageManager24.3.0.exe"
    powershell.exe -Command `
    $ErrorActionPreference = 'Stop'; `
    Invoke-WebRequest -Uri $nipmUrl -OutFile NIPM_installer.exe ; `
    # Install NIPM
    Write-LogOrHost "NI package manager installing..."
    Start-Process -wait .\NIPM_installer.exe `
        -ArgumentList '--passive','--accept-eulas','--prevent-reboot' ; `
    # Remove the installer
    Remove-Item NIPM_installer.exe;
}

# check if feeds need to be added and add them if necessary
$feeds = & "$nipm" feed-list
ForEach($package in $packages)
{
    $feedId = $($package.installID).replace(".", "-")
    if (!($feeds -Match $feedId)){
        Write-LogOrHost "Adding feeds for $($package.installID)"
        & $nipm feed-add --name="""$($package.name)""" --system $($package.url)
        & $nipm feed-add --name="""$($package.name)-critical""" --system $($package.url + "-critical")
    }
}

# update from feeds
& $nipm update
# get the installed packages
$installedList = & $nipm list-installed
# install packages if necessary
ForEach($package in $packages)
{
    $installID = $package.installID
    if (!($installedList -Match $installID)){
        Write-LogOrHost "'$installID' is installing, this may take 30 minutes or longer, do something else but monitor for prompts."
        & $nipm install --accept-eulas --assume-yes $installID
        # create file to indicate a restart is needed
        New-Item -Path $Env:TEMP -Name "ni-restart-needed" -ItemType "file" -Force
    }
}

# Read-Host -Prompt "Press enter key to close this window and return to parent script" | Out-Null

Return 0