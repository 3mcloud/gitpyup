@echo off

echo run-elevated-v3

pushd %~dp0

if exist Deploy-gitpyup.ps1 goto check_Permissions

:result_False
    echo Please try again!: Ensure run-elevated-first.bat and Deploy-gitpyup.ps1 are extracted (not in a zip file) and in the same directory.
    goto Done

:check_Permissions
    echo Administrative permissions required. Detecting permissions...
    
    net session >nul 2>&1
    if %errorLevel% == 0 (
        echo Success: Administrative permissions confirmed.
        goto set_Policies_Unblock
    ) else (
        echo Please try again!: Current permissions inadequate, right click and select 'Run with Elevated Privileges' or 'Run as Administrator'.
        goto Done
    )
    
:set_Policies_Unblock
    echo Attempting to set execution policies and unblock deploy script...
    powershell -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force"
    powershell -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force"
	echo There may be errors above. They can be ignored if 'CurrentUser' and 'LocalMachine' ExecutionPolicies are set to 'RemoteSigned' in the table below.
	powershell -Command "Get-ExecutionPolicy -list"
    powershell -Command "Unblock-File Deploy-gitpyup.ps1"
    echo Next step: right click Deploy-gitpyup.ps1 and select 'Run with PowerShell'

:Done
    pause
    popd