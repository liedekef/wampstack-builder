@echo off
setlocal enabledelayedexpansion

REM ============================================================================
REM manage.bat - start/stop/restart/status for the Apache and MariaDB services.
REM
REM Command line usage:
REM   manage.bat status
REM   manage.bat start   [apache|mariadb|all]   (default: all)
REM   manage.bat stop    [apache|mariadb|all]
REM   manage.bat restart [apache|mariadb|all]
REM
REM Without arguments (e.g. on double-click): interactive menu.
REM ============================================================================

REM Service names -- the placeholders below are replaced by build.sh with the
REM configured service names. No need to edit them by hand anymore.
set "SVC_APACHE=__SVC_APACHE__"
set "SVC_MARIADB=__SVC_MARIADB__"

set "ACTION=%~1"
set "TARGET=%~2"
set "ELEVATED=%~3"
if "%TARGET%"=="" set "TARGET=all"

if "%ACTION%"=="" goto menu
goto run

:menu
echo.
echo ============================================
echo   Manage: %SVC_APACHE% / %SVC_MARIADB%
echo ============================================
echo   1. Status
echo   2. Start (both)
echo   3. Stop (both)
echo   4. Restart (both)
echo   5. Exit
echo ============================================
choice /C 12345 /N /M "Choose an option: "
if errorlevel 5 exit /b 0
if errorlevel 4 set "ACTION=restart" & set "TARGET=all" & goto run_and_return
if errorlevel 3 set "ACTION=stop"    & set "TARGET=all" & goto run_and_return
if errorlevel 2 set "ACTION=start"   & set "TARGET=all" & goto run_and_return
if errorlevel 1 set "ACTION=status"  & set "TARGET=all" & goto run_and_return

:run_and_return
call :do_action
echo.
pause
goto menu

:run
call :do_action
exit /b 0

:do_action
if /I not "%ACTION%"=="status" (
    net session >nul 2>&1
    if !errorlevel! neq 0 (
        echo Requesting administrator rights to perform "%ACTION%"...
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%ACTION% %TARGET% ELEVATED' -WorkingDirectory '%~dp0' -Verb RunAs"
        exit /b 0
    )
)

set "SERVICES="
if /I "%TARGET%"=="apache"  set "SERVICES=%SVC_APACHE%"
if /I "%TARGET%"=="mariadb" set "SERVICES=%SVC_MARIADB%"
if /I "%TARGET%"=="all"     set "SERVICES=%SVC_MARIADB% %SVC_APACHE%"

if not defined SERVICES (
    echo Unknown target "%TARGET%". Use: apache, mariadb or all.
    exit /b 1
)

for %%S in (%SERVICES%) do (
    if /I "%ACTION%"=="status" (
        echo.
        echo -- %%S --
        sc query "%%S" | findstr /I "STATE"
    ) else if /I "%ACTION%"=="start" (
        echo Starting %%S...
        net start "%%S"
    ) else if /I "%ACTION%"=="stop" (
        echo Stopping %%S...
        net stop "%%S"
    ) else if /I "%ACTION%"=="restart" (
        echo Restarting %%S...
        net stop "%%S" >nul 2>&1
        net start "%%S"
    ) else (
        echo Unknown action "%ACTION%". Use: start, stop, restart or status.
        exit /b 1
    )
)

if /I "%ELEVATED%"=="ELEVATED" (
    echo.
    pause
)
exit /b 0
