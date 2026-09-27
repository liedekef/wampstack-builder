@echo off
REM ============================================================================
REM uninstall.bat - removes the Apache/MariaDB services again.
REM Data and configuration are left alone; only the services are
REM stopped and removed.
REM ============================================================================

REM Service names -- the placeholders below are replaced by build.sh with the
REM configured service names.
set "SVC_APACHE=__SVC_APACHE__"
set "SVC_MARIADB=__SVC_MARIADB__"

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -WorkingDirectory '%~dp0' -Verb RunAs"
    exit /b
)

set "BASEDIR=%~dp0"
if "%BASEDIR:~-1%"=="\" set "BASEDIR=%BASEDIR:~0,-1%"

net stop %SVC_APACHE% 2>nul
net stop %SVC_MARIADB% 2>nul

"%BASEDIR%\apache24\bin\httpd.exe" -k uninstall -n "%SVC_APACHE%"
"%BASEDIR%\mariadb\bin\mariadbd.exe" --remove %SVC_MARIADB%

echo Removing the certificate from the Windows trusted root store...
powershell -NoProfile -Command "Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -eq 'CN=Wampstack Builder Local CA' } | Remove-Item -Force" 2>nul

echo.
echo Services and certificate removed.
echo (Firefox policies.json and the files on disk are left in place.)
if not defined WAMPSTACK_NOPAUSE pause
