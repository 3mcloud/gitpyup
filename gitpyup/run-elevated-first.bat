@echo off

echo run-elevated-v2

if exist clarke-deploy-windows.ps1 if exist clarke_deploy_key goto check_Permissions

:result_False
    echo Ensure run-elevated-once.bat, clarke-deploy-windows.ps1 and clarke_deploy_key are extracted (may have downloaded .zip) and in the same directory.
    goto Done

:check_Permissions
    echo Administrative permissions required. Detecting permissions...
    
    net session >nul 2>&1
    if %errorLevel% == 0 (
        echo Success: Administrative permissions confirmed.
        goto set_Policies_Unblock
    ) else (
        echo Failure: Current permissions inadequate, right click and select 'Run with Elevated Privileges'
        goto Done
    )
    
:set_Policies_Unblock
    powershell -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force"
    powershell -Command "Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force"
    powershell -Command "Unblock-File clarke-deploy-windows.ps1"
    echo Next step: right click clarke-deploy-windows.ps1 and select 'Run with PowerShell'

:Done
    pause