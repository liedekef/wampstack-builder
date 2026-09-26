@echo off
setlocal enabledelayedexpansion

REM ============================================================================
REM install.bat - installs Apache + MariaDB as Windows services.
REM Right-click -> "Run as administrator".
REM ============================================================================

REM Service names -- the placeholders below are replaced by build.sh with the
REM configured service names. No need to edit them by hand anymore.
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
echo === Step 1/7: unblock files ===
powershell -NoProfile -Command "Get-ChildItem -Path '%BASEDIR%' -Recurse | Unblock-File" 2>nul

echo.
echo === Step 2/7: configure httpd.conf and php.ini ===
powershell -NoProfile -Command ^
  "(Get-Content -Raw '%BASEDIR%\apache24\conf\httpd.conf') -replace '__BASEDIR__', '%BASEDIR_FWD%' | Set-Content -NoNewline '%BASEDIR%\apache24\conf\httpd.conf'"
powershell -NoProfile -Command ^
  "(Get-Content -Raw '%BASEDIR%\php\php.ini') -replace '__BASEDIR__', '%BASEDIR_FWD%' | Set-Content -NoNewline '%BASEDIR%\php\php.ini'"

echo.
echo === Step 3/7: initialise the MariaDB data directory ===
if not exist "%BASEDIR%\mariadb\data\mysql" (
    "%BASEDIR%\mariadb\bin\mariadb-install-db.exe" ^
        --datadir="%BASEDIR%\mariadb\data" ^
        --service=%SVC_MARIADB% ^
        --port=3306
) else (
    echo Data directory already exists, skipping initialisation.
)

echo.
echo === Step 4/7: install the MariaDB service ===
sc query %SVC_MARIADB% >nul 2>&1
if %errorlevel% neq 0 (
    "%BASEDIR%\mariadb\bin\mariadbd.exe" --install %SVC_MARIADB% ^
        --datadir="%BASEDIR%\mariadb\data" --port=3306
) else (
    echo Service %SVC_MARIADB% already exists.
)

echo.
echo === Step 5/7: create a local SSL certificate (own root CA + leaf) ===
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
echo === Step 6/7: install the Apache service ===
sc query %SVC_APACHE% >nul 2>&1
if %errorlevel% neq 0 (
    "%BASEDIR%\apache24\bin\httpd.exe" -k install -n "%SVC_APACHE%" ^
        -f "%BASEDIR%\apache24\conf\httpd.conf"
) else (
    echo Service %SVC_APACHE% already exists.
)


echo.
echo === Step 7/7: start the services ===
net start %SVC_MARIADB%
net start %SVC_APACHE%

echo.
echo ============================================================
echo Done. Open http://localhost/ or https://localhost/ for the test page
echo and http://localhost/phpmyadmin/ (or https://) for phpMyAdmin.
echo Restart Firefox if it is open, otherwise it takes a moment for the
echo certificate to become trusted there.
echo ============================================================
pause
