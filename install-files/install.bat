@echo off
setlocal enabledelayedexpansion

REM ============================================================================
REM install.bat - installs Apache + MariaDB as Windows services.
REM
REM Pass "nopause" as the first argument to skip the pause at the end; the
REM setup.exe installer does that so it can read the output.
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
set "BASEDIR_FWD=%BASEDIR:\=/%"

echo.
echo === Step 1/8: unblock files ===
powershell -NoProfile -Command "Get-ChildItem -Path '%BASEDIR%' -Recurse | Unblock-File" 2>nul

echo.
echo === Step 2/8: configure httpd.conf, my.ini and php.ini ===
powershell -NoProfile -Command ^
  "(Get-Content -Raw '%BASEDIR%\apache24\conf\httpd.conf') -replace '__BASEDIR__', '%BASEDIR_FWD%' | Set-Content -NoNewline '%BASEDIR%\apache24\conf\httpd.conf'"
powershell -NoProfile -Command ^
  "(Get-Content -Raw '%BASEDIR%\mariadb\my.ini') -replace '__BASEDIR__', '%BASEDIR_FWD%' | Set-Content -NoNewline '%BASEDIR%\mariadb\my.ini'"
powershell -NoProfile -Command ^
  "(Get-Content -Raw '%BASEDIR%\php\php.ini') -replace '__BASEDIR__', '%BASEDIR_FWD%' | Set-Content -NoNewline '%BASEDIR%\php\php.ini'"

REM my.ini reads mariadb\conf.d and PHP reads php\conf.d. If one of those
REM directories went missing, MariaDB refuses to start (an includedir that
REM cannot be opened is fatal) and PHP silently ignores its own, so make them.
if not exist "%BASEDIR%\mariadb\conf.d" mkdir "%BASEDIR%\mariadb\conf.d"
if not exist "%BASEDIR%\php\conf.d" mkdir "%BASEDIR%\php\conf.d"

echo.
echo === Step 3/8: check phpMyAdmin config and generate unique blowfish secret if needed ===
set "PMA_CONF=%BASEDIR%\phpmyadmin\config.inc.php"
if exist "%PMA_CONF%" (
    findstr /C:"__BLOWFISH_SECRET__" "%PMA_CONF%" >nul 2>&1
    if !errorlevel! equ 0 (
        powershell -NoProfile -Command ^
          "$secret = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ }); (Get-Content -Raw '%PMA_CONF%') -replace '__BLOWFISH_SECRET__', $secret | Set-Content -NoNewline '%PMA_CONF%'"
    )
)

echo.
echo === Step 4/8: initialise the MariaDB data directory ===
if not exist "%BASEDIR%\mariadb\data\mysql" (
    "%BASEDIR%\mariadb\bin\mariadb-install-db.exe" ^
        --datadir="%BASEDIR%\mariadb\data" ^
        --service=%SVC_MARIADB% ^
        --port=3306
) else (
    echo Data directory already exists, skipping initialisation.
)

echo.
echo === Step 5/8: install the MariaDB service ===
sc query %SVC_MARIADB% >nul 2>&1
if %errorlevel% neq 0 (
    "%BASEDIR%\mariadb\bin\mariadbd.exe" --install %SVC_MARIADB% ^
        --datadir="%BASEDIR%\mariadb\data" --port=3306
) else (
    echo Service %SVC_MARIADB% already exists.
)

echo.
echo === Step 6/8: create a local SSL certificate (own root CA + leaf) ===
set "SSLDIR=%BASEDIR%\apache24\conf\ssl"
if not exist "%SSLDIR%" mkdir "%SSLDIR%"

if not exist "%SSLDIR%\localhost.crt" (
    if exist "%BASEDIR%\apache24\conf\openssl.cnf" (
        REM A self-signed cert that is itself in the Root store AND used as
        REM the website certificate is rejected by Firefox/Chrome
        REM (MOZILLA_PKIX_ERROR_CA_CERT_USED_AS_END_ENTITY): a root must not
        REM also be the end-entity certificate. Hence a real 2-tier structure
        REM here: our own root-CA + a leaf certificate for localhost signed
        REM by that CA.
        > "%SSLDIR%\leaf_ext.cnf" (
            echo [v3_req]
            echo basicConstraints = CA:FALSE
            echo keyUsage = digitalSignature, keyEncipherment
            echo extendedKeyUsage = serverAuth
            echo subjectAltName = DNS:localhost,IP:127.0.0.1
        )

        echo Creating the root CA...
        "%BASEDIR%\apache24\bin\openssl.exe" req -x509 -nodes -newkey rsa:2048 ^
            -config "%BASEDIR%\apache24\conf\openssl.cnf" ^
            -keyout "%SSLDIR%\ca.key" -out "%SSLDIR%\ca.crt" ^
            -days 3650 -subj "/CN=Wampstack Builder Local CA" ^
            -addext "basicConstraints=critical,CA:TRUE" ^
            -addext "keyUsage=critical,keyCertSign,cRLSign"

        echo Creating a certificate for localhost and having it signed by the root CA...
        "%BASEDIR%\apache24\bin\openssl.exe" req -new -nodes -newkey rsa:2048 ^
            -config "%BASEDIR%\apache24\conf\openssl.cnf" ^
            -keyout "%SSLDIR%\localhost.key" -out "%SSLDIR%\localhost.csr" ^
            -subj "/CN=localhost"

        "%BASEDIR%\apache24\bin\openssl.exe" x509 -req ^
            -in "%SSLDIR%\localhost.csr" ^
            -CA "%SSLDIR%\ca.crt" -CAkey "%SSLDIR%\ca.key" -CAcreateserial ^
            -out "%SSLDIR%\localhost.crt" -days 1825 -sha256 ^
            -extfile "%SSLDIR%\leaf_ext.cnf" -extensions v3_req

        del "%SSLDIR%\localhost.csr" "%SSLDIR%\ca.srl" >nul 2>&1
    ) else (
        echo WARNING: openssl.cnf not found, skipping the HTTPS certificate.
        echo Apache will then only serve http:// on port 80, not https:// on 443.
    )
) else (
    echo Certificate already exists, skipping creation.
)

REM Only import the ROOT-CA, never the leaf certificate itself -- Windows and
REM Firefox refuse to use a leaf cert as a trusted root.
if exist "%SSLDIR%\ca.crt" (
    echo Adding the root CA to the Windows trusted root certificates...
    certutil -addstore -f "Root" "%SSLDIR%\ca.crt" >nul
)

REM Firefox uses its OWN certificate store by default, not the Windows one.
REM Enable the "ImportEnterpriseRoots" policy so that Firefox trusts
REM everything that is also in the Windows Root store:
REM via the JSON provider (distribution\policies.json)

for %%D in (
    "%ProgramFiles%\Mozilla Firefox"
    "%ProgramFiles(x86)%\Mozilla Firefox"
) do (
    if exist "%%~D\firefox.exe" (
        if not exist "%%~D\distribution" mkdir "%%~D\distribution"
        powershell -NoProfile -Command ^
            "$p = '%%~D\distribution\policies.json';" ^
            "$obj = if (Test-Path $p) { Get-Content -Raw $p | ConvertFrom-Json } else { [PSCustomObject]@{ policies = [PSCustomObject]@{} } };" ^
            "if (-not $obj.policies) { $obj | Add-Member -NotePropertyName policies -NotePropertyValue ([PSCustomObject]@{}) }" ^
            "if (-not $obj.policies.Certificates) { $obj.policies | Add-Member -NotePropertyName Certificates -NotePropertyValue ([PSCustomObject]@{}) -Force }" ^
            "$obj.policies.Certificates | Add-Member -NotePropertyName ImportEnterpriseRoots -NotePropertyValue $true -Force;" ^
            "$obj | ConvertTo-Json -Depth 10 | Set-Content $p"
        echo Firefox configured to accept the certificate
    )
)

echo.
echo === Step 7/8: install the Apache service ===
sc query %SVC_APACHE% >nul 2>&1
if %errorlevel% neq 0 (
    "%BASEDIR%\apache24\bin\httpd.exe" -k install -n "%SVC_APACHE%" ^
        -f "%BASEDIR%\apache24\conf\httpd.conf"
) else (
    echo Service %SVC_APACHE% already exists.
)

REM php\conf.d\*.ini is PHP's own directory of extra ini files, read after
REM php.ini. PHP only takes that directory from the PHP_INI_SCAN_DIR
REM environment variable (mod_php has no httpd.conf directive for it), and a
REM Windows service only gets environment variables that are listed in its own
REM registry key: services.exe merges those into the environment of the
REM service process every time it starts. So register php\conf.d there.
REM This is done even when the service already existed, because it is read
REM when the service starts, not when it is installed. httpd.exe -k uninstall
REM (uninstall.bat) removes the whole service key, value included.
reg add "HKLM\SYSTEM\CurrentControlSet\Services\%SVC_APACHE%" ^
    /v Environment /t REG_MULTI_SZ /d "PHP_INI_SCAN_DIR=%BASEDIR_FWD%/php/conf.d" /f >nul
if errorlevel 1 (
    echo WARNING: could not register PHP_INI_SCAN_DIR for the Apache service,
    echo          so php\conf.d\*.ini will NOT be read by PHP.
) else (
    echo php\conf.d registered as PHP_INI_SCAN_DIR for %SVC_APACHE%.
)


echo.
echo === Step 8/8: start the services ===
net start %SVC_MARIADB%
net start %SVC_APACHE%

echo.
echo ============================================================
echo Done. Open http://localhost/ or https://localhost/ for the test page
echo and http://localhost/phpmyadmin/ (or https://) for phpMyAdmin.
echo Restart Firefox if it is open, otherwise it takes a moment for the
echo certificate to become trusted there.
echo ============================================================
if /I not "%~1"=="nopause" pause
