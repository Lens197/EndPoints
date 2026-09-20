rem 2026-09-20-22:10
@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem Configuration
rem ============================================================

set "LogFile=C:\Windows\Temp\W24H2_wired-fix-runOnce.log"
set "MigrationPath=HKLM\SOFTWARE\Microsoft\dot3svc\MigrationData"
set "MarkerPath=HKLM\SOFTWARE\NKT\SoftwarePackages\W24H2-Wired-Upgrade-Fix"

rem ============================================================
rem Prepare log directory
rem ============================================================

if not exist "C:\Windows\Temp" (
    mkdir "C:\Windows\Temp" >nul 2>&1

    if errorlevel 1 (
        echo ERROR: Failed to create C:\Windows\Temp
        exit /b 1
    )
)

rem Start with a fresh log for each execution
if exist "%LogFile%" (
    del /f /q "%LogFile%" >nul 2>&1
)

rem ============================================================
rem Start
rem ============================================================

call :Log "============================================================"
call :Log "Windows 11 24H2 Wired Upgrade - dot3svc Migration Reset"
call :Log "Script started."
call :Log "============================================================"

rem ============================================================
rem Check MigrationData registry key
rem ============================================================

call :Log "Checking MigrationData registry key..."

reg query "%MigrationPath%" >nul 2>&1

if errorlevel 1 (
    call :Log "MigrationData registry key does not exist."
    call :Log "Creating registry key..."

    reg add "%MigrationPath%" /f >nul 2>&1

    if errorlevel 1 (
        call :Log "ERROR: Failed to create MigrationData registry key."
        goto :Error
    )

    call :Log "MigrationData registry key created."
) else (
    call :Log "MigrationData registry key exists."
)

rem ============================================================
rem Check dot3svc service
rem ============================================================

call :Log "Checking dot3svc service..."

sc query "dot3svc" >nul 2>&1

if errorlevel 1 (
    call :Log "ERROR: dot3svc service was not found."
    goto :Error
)

set "ServiceStatus="

for /f "tokens=4" %%A in (
    'sc query "dot3svc" 2^>nul ^| findstr /i "STATE"'
) do (
    set "ServiceStatus=%%A"
)

call :Log "dot3svc service found. Current status: !ServiceStatus!"

rem ============================================================
rem Perform reset three times
rem ============================================================

for /l %%I in (1,1,3) do (

    call :Log "------------------------------------------------------------"
    call :Log "Iteration %%I of 3"

    rem --------------------------------------------------------
    rem Reset registry value
    rem --------------------------------------------------------

    call :Log "Resetting dot3svcMigrationDone to 0..."

    reg add "%MigrationPath%" ^
        /v "dot3svcMigrationDone" ^
        /t REG_DWORD ^
        /d 0 ^
        /f >nul 2>&1

    if errorlevel 1 (
        call :Log "ERROR: Failed to set dot3svcMigrationDone."
        goto :Error
    )

    call :Log "dot3svcMigrationDone successfully set to 0."

    rem --------------------------------------------------------
    rem Verify registry value
    rem --------------------------------------------------------

    set "RegistryValue="

    for /f "tokens=3" %%A in (
        'reg query "%MigrationPath%" /v "dot3svcMigrationDone" 2^>nul ^| findstr /i /c:"dot3svcMigrationDone"'
    ) do (
        set "RegistryValue=%%A"
    )

    call :Log "Verified dot3svcMigrationDone value: !RegistryValue!"

    if /i not "!RegistryValue!"=="0x0" (
        call :Log "ERROR: Registry verification failed."
        goto :Error
    )

    call :Log "Registry verification successful."

    rem --------------------------------------------------------
    rem Stop dot3svc
    rem --------------------------------------------------------

    call :Log "Stopping dot3svc service..."

    sc stop "dot3svc" >nul 2>&1

    rem Allow service state transition to begin
    timeout /t 2 /nobreak >nul

    call :WaitForService "STOPPED" 30

    if errorlevel 1 (
        call :Log "ERROR: dot3svc did not stop successfully."
        goto :Error
    )

    call :Log "dot3svc stopped successfully."

    rem --------------------------------------------------------
    rem Start dot3svc
    rem --------------------------------------------------------

    call :Log "Starting dot3svc service..."

    sc start "dot3svc" >nul 2>&1

    if errorlevel 1 (
        call :Log "ERROR: Failed to start dot3svc."
        goto :Error
    )

    call :WaitForService "RUNNING" 30

    if errorlevel 1 (
        call :Log "ERROR: dot3svc did not reach the RUNNING state."
        goto :Error
    )

    call :Log "dot3svc restart completed."
    call :Log "dot3svc current status: RUNNING"

    rem --------------------------------------------------------
    rem Wait before next iteration
    rem --------------------------------------------------------

    if %%I lss 3 (
        call :Log "Waiting 30 seconds before next iteration..."
        timeout /t 30 /nobreak >nul
    )
)

rem ============================================================
rem All three iterations completed
rem ============================================================

call :Log "------------------------------------------------------------"
call :Log "SUCCESS: dot3svcMigrationDone reset to 0 three times."
call :Log "SUCCESS: dot3svc service restarted three times."

rem ============================================================
rem Create completion marker
rem ============================================================

call :Log "Creating completion marker..."

reg add "%MarkerPath%" /f >nul 2>&1

if errorlevel 1 (
    call :Log "ERROR: Failed to create completion marker key."
    goto :Error
)

rem Create timestamp
set "Timestamp=%DATE% %TIME:~0,8%"

reg add "%MarkerPath%" ^
    /v "Dot1xFixAppliedTimestampRunOnce" ^
    /t REG_SZ ^
    /d "%Timestamp%" ^
    /f >nul 2>&1

if errorlevel 1 (
    call :Log "ERROR: Failed to create completion timestamp marker."
    goto :Error
)

call :Log "Completion marker successfully created."
call :Log "Timestamp: %Timestamp%"

rem ============================================================
rem Success
rem ============================================================

:Success

call :Log "============================================================"
call :Log "SUCCESS: Script completed successfully."
call :Log "============================================================"

exit /b 0


rem ============================================================
rem Error
rem ============================================================

:Error

call :Log "============================================================"
call :Log "ERROR: Script terminated with an error."
call :Log "============================================================"

exit /b 1


rem ============================================================
rem Function: Log
rem ============================================================

:Log

set "LogTime=%TIME%"
set "LogTime=%LogTime:,=.%"

set "LogMessage=%DATE% %LogTime% - %~1"

echo !LogMessage!

>>"%LogFile%" echo !LogMessage!

exit /b 0


rem ============================================================
rem Function: WaitForService
rem
rem %1 = expected state
rem %2 = maximum number of retries
rem ============================================================

:WaitForService

set "ExpectedState=%~1"
set /a "Retries=%~2"

:WaitForServiceLoop

set "CurrentState="

for /f "tokens=4" %%A in (
    'sc query "dot3svc" 2^>nul ^| findstr /i "STATE"'
) do (
    set "CurrentState=%%A"
)

if /i "!CurrentState!"=="!ExpectedState!" (
    exit /b 0
)

set /a Retries-=1

if !Retries! LEQ 0 (
    exit /b 1
)

timeout /t 1 /nobreak >nul

goto :WaitForServiceLoop
