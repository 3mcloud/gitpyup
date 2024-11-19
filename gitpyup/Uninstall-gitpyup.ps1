$response = Read-Host -Prompt "Type 'uninstall' and press enter to remove gitpyup installed shortcuts and repositories. Miniforge and conda environments will be preserved."

$scriptBlock = {
    $repo = "gitpyup"

    # determine if installed in user profile or program files
    if (Test-Path "$env:APPDATA\$repo") {
        $installPath = "$env:APPDATA\$repo"
    } elseif (Test-Path "$env:ProgramData\$repo") {
        $installPath = "$env:ProgramData\$repo"
    } else {
        Write-Host "Application not found"
        Start-Sleep -Seconds 5
        exit
    }

    # load installConfig.yaml
    $configYmlPath = Join-Path $installPath\$repo "installConfig.yaml"
    $fileContent = Get-Content -Path $configYmlPath -Raw
    $configRoot = ConvertFrom-Yaml $fileContent
    $install = $configRoot.install
    $shortcutParent = $install.shortcutParent

    $pathsToRemove = @(
        $shortcutParent
    )

    # add all the app paths to the pathsToRemove array
    $applications = $configRoot.applications
    foreach ($app in $applications) {
        $pathsToRemove += $app.path
    }
    
    # use a for loop to check and remove shortcuts
    foreach ($item in $pathsToRemove) {
        if (Test-Path $item) {
            Remove-Item -Recurse -Force $item
            Write-Host "Removed $item"
        }
    }
    Write-Host "Uninstall complete"
    Start-Sleep -Seconds 5
    # Read-Host -Prompt "Press enter key to exit" | Out-Null
}
$EncodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptBlock))

if ($response -eq "uninstall") {
    
    # Define the action to delete the folder
    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -EncodedCommand $EncodedCommand"

    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $RunningAsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($RunningAsAdmin) {
        $TaskName = "gitpyup-uninstall-admin"
        # Define the principal to run the task with the highest privileges
        $Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount  # works on admin files but not user files
        # $Principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Administrators" -RunLevel Highest
    } else {
        $TaskName = "gitpyup-uninstall"
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $Principal = New-ScheduledTaskPrincipal -UserId $currentUser
    }

    # if scheduled task exists, remove it
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    # Define the trigger to start the task once only and immediately
    $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(3)

    # Register the scheduled task
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal
}