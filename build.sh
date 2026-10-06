#!/bin/bash
# ============================================================================
# build.sh — builds a self-contained "wampstack" zip for Windows
# (Apache + MariaDB + PHP + phpMyAdmin), pinned versions, no installers.
#
# Run this on Linux (or WSL). Requires: curl, unzip, zip (7z optional).
# Output: build/wampstack.zip and build/wampstack.7z
# ============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# 1. VERSIONS & URLs — ADJUST THIS AND VERIFY BEFORE EVERY BUILD
#    These sources change their exact filename per release, so check them
#    yourself on the download page before building:
#      - Apache: https://www.apachelounge.com/download/  (newest VS version, Win64 zip)
#      - PHP:    https://windows.php.net/download/        (x64 Thread Safe zip)
#      - MariaDB:https://mariadb.org/download/             (Windows, zip, x86_64)
#      - phpMyAdmin: https://www.phpmyadmin.net/downloads/ (all-languages.zip)
# ---------------------------------------------------------------------------
APACHE_VER="2.4.68"
APACHE_URL="https://www.apachelounge.com/download/VS18/binaries/httpd-${APACHE_VER}-260920-Win64-VS18.zip"

PHP_VER="8.5.11"
PHP_URL="https://windows.php.net/downloads/releases/php-${PHP_VER}-Win32-vs17-x64.zip"

MARIADB_VER="13.0.2"
MARIADB_URL="https://archive.mariadb.org/mariadb-${MARIADB_VER}/winx64-packages/mariadb-${MARIADB_VER}-winx64.zip"

PMA_VER="5.2.3"
PMA_URL="https://files.phpmyadmin.net/phpMyAdmin/${PMA_VER}/phpMyAdmin-${PMA_VER}-all-languages.zip"

# ---------------------------------------------------------------------------
# 2. WINDOWS SERVICE NAMES
#    Substituted for the __SVC_APACHE__ and __SVC_MARIADB__ placeholders in
#    install-files/*.bat. Pick something recognisable for your school/course
#    so your own stack doesn't clash with an already-installed
#    Apache/MariaDB. Only letters, digits, _, . and - are allowed.
# ---------------------------------------------------------------------------
SVC_APACHE="WAMP_Apache"
SVC_MARIADB="WAMP_MariaDB"

# ---------------------------------------------------------------------------
# 2b. OPTIONAL build.config
#     Sourced after the defaults above, so anything assigned in it wins. Use
#     this for the settings that are YOURS (service names, pinned versions),
#     instead of editing this script: a git pull/update of wampstack-builder
#     then overwrites build.sh but leaves build.config alone.
#     Plain shell assignments, e.g.:
#         SVC_APACHE="Course_Apache"
#         SVC_MARIADB="Course_MariaDB"
#         APACHE_VER="2.4.69"
#         APACHE_URL="https://.../httpd-${APACHE_VER}-...zip"
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_CONFIG="${SCRIPT_DIR}/build.config"
if [ -f "${BUILD_CONFIG}" ]; then
    echo "==> Reading overrides from ${BUILD_CONFIG}..."
    . "${BUILD_CONFIG}"
fi

validate_svc_name() {
    if ! printf '%s' "${2}" | grep -qE '^[A-Za-z0-9_.-]{1,64}$'; then
        echo "ERROR: ${1} is not a valid Windows service name: '${2}'" >&2
        echo "       Allowed: letters, digits, _, . and - (max. 64 characters)." >&2
        exit 1
    fi
}
validate_svc_name "SVC_APACHE"  "${SVC_APACHE}"
validate_svc_name "SVC_MARIADB" "${SVC_MARIADB}"

# ---------------------------------------------------------------------------
# 3. Paths (SCRIPT_DIR itself is set further up, where build.config is read)
# ---------------------------------------------------------------------------
BUILD_DIR="${SCRIPT_DIR}/build"
DOWNLOAD_DIR="${BUILD_DIR}/downloads"
PKG_DIR="${BUILD_DIR}/wampstack"
CONF_DIR="${SCRIPT_DIR}/conf-templates"
INSTALL_DIR="${SCRIPT_DIR}/install-files"

rm -rf "${BUILD_DIR}"
mkdir -p "${DOWNLOAD_DIR}" "${PKG_DIR}"

echo "==> Downloading..."
curl -fL -o "${DOWNLOAD_DIR}/apache.zip"     "${APACHE_URL}"
curl -fL -o "${DOWNLOAD_DIR}/php.zip"        "${PHP_URL}"
curl -fL -o "${DOWNLOAD_DIR}/mariadb.zip"    "${MARIADB_URL}"
curl -fL -o "${DOWNLOAD_DIR}/phpmyadmin.zip" "${PMA_URL}"

# ---------------------------------------------------------------------------
# Helper: unzip an archive and "flatten" it when it contains exactly 1
# top-level directory (the MariaDB and phpMyAdmin zips typically contain a
# single version-named directory; the Apache and PHP zips do not).
# ---------------------------------------------------------------------------
unzip_flatten() {
    local zipfile="$1"
    local target="$2"
    local tmp
    tmp="$(mktemp -d)"
    unzip -q "${zipfile}" -d "${tmp}"
    mkdir -p "${target}"

    shopt -s dotglob nullglob
    local entries=("${tmp}"/*)
    local dirs=()
    for e in "${entries[@]}"; do
        [ -d "${e}" ] && dirs+=("${e}")
    done

    if [ "${#dirs[@]}" -eq 1 ]; then
        # exactly 1 top-level dir -> move its contents up.
        # loose files next to it (readme/license etc.) are ignored.
        mv "${dirs[0]}"/* "${target}/"
    else
        mv "${tmp}"/* "${target}/"
    fi
    shopt -u dotglob nullglob
    rm -rf "${tmp}"
}

echo "==> Unpacking..."
unzip_flatten "${DOWNLOAD_DIR}/apache.zip"     "${PKG_DIR}/apache24"
unzip_flatten "${DOWNLOAD_DIR}/php.zip"        "${PKG_DIR}/php"
unzip_flatten "${DOWNLOAD_DIR}/mariadb.zip"    "${PKG_DIR}/mariadb"
unzip_flatten "${DOWNLOAD_DIR}/phpmyadmin.zip" "${PKG_DIR}/phpmyadmin"

echo "==> Creating htdocs + wiring up phpMyAdmin..."
mkdir -p "${PKG_DIR}/htdocs"
cp "${SCRIPT_DIR}/htdocs-template/index.php" "${PKG_DIR}/htdocs/index.php"

echo "==> Placing config templates..."
cp "${CONF_DIR}/httpd.conf"     "${PKG_DIR}/apache24/conf/httpd.conf"
cp "${CONF_DIR}/php.ini"        "${PKG_DIR}/php/php.ini"
cp "${CONF_DIR}/mariadb.ini"    "${PKG_DIR}/mariadb/my.ini"
cp "${CONF_DIR}/phpmyadmin.config.php" "${PKG_DIR}/phpmyadmin/config.inc.php"

echo "==> Creating the 'own settings' directories..."
# Every component reads the files in its own directory in addition to (and
# after) its main config file, so students can put their own settings there
# instead of editing a config file that gets replaced on every upgrade.
# Arguments: directory, which files it reads, example, what to do after a change.
includedir_readme() {
    local dir="$1" files="$2" example="$3" after="$4"
    mkdir -p "${PKG_DIR}/${dir}"
    {
        echo "This directory is for your OWN settings, not for the ones that"
        echo "ship with the stack."
        echo
        echo "The main config file of this component reads every $files file in"
        echo "this directory, in alphabetical order, AFTER itself, so whatever"
        echo "you put here wins. That is the whole point of this directory: the"
        echo "main config file is replaced with every new version of the stack,"
        echo "the files you put in here are not."
        echo
        echo "For example:"
        echo "$example"
        echo
        echo "$after"
    } > "${PKG_DIR}/${dir}/README.txt"
}
includedir_readme "apache24/conf/custom" "*.conf" \
    "    <VirtualHost *:8080> ... </VirtualHost>" \
    "After changing a file here: manage.bat restart apache"
includedir_readme "mariadb/conf.d" "*.cnf and *.ini" \
    "$(printf '    [mariadb]\n    max_connections = 200')" \
    "After changing a file here: manage.bat restart mariadb"
includedir_readme "php/conf.d" "*.ini" \
    "    memory_limit = 1G" \
    "$(printf 'After changing a file here: manage.bat restart apache\n(install.bat tells the Apache service where this directory is.)')"
includedir_readme "phpmyadmin/conf.d" "*.php" \
    "    \$cfg['MaxExactCount'] = false;" \
    "$(printf 'Nothing to do after changing a file here: phpMyAdmin reads it\non every page request.')"

echo "==> Placing bat files..."
cp ${INSTALL_DIR}/*.bat ${PKG_DIR}/

echo "==> Filling in the service names..."
sed -i -e "s|__SVC_APACHE__|${SVC_APACHE}|g" \
       -e "s|__SVC_MARIADB__|${SVC_MARIADB}|g" \
       "${PKG_DIR}"/*.bat

echo "==> Forcing CRLF line endings on the Windows text files..."
# *.txt is in here for the README.txt files of the own-settings directories
# above, so Notepad shows them like every other text file on Windows.
find "${PKG_DIR}" -type f \
    \( -iname "*.bat" -o -iname "*.conf" -o -iname "*.ini" -o -iname "*.txt" \) -print0 \
    | xargs -0 sed -i 's/\r$//; s/$/\r/'

echo "==> Packing into wampstack.zip..."
( cd "${BUILD_DIR}" && zip -r -q wampstack.zip wampstack )
echo "==> Done: ${BUILD_DIR}/wampstack.zip"

echo "==> Packing into wampstack.7z..."
if command -v 7z >/dev/null 2>&1 || command -v 7za >/dev/null 2>&1; then
    SEVENZIP="$(command -v 7z || command -v 7za)"
    ( cd "${BUILD_DIR}" && "${SEVENZIP}" a -t7z -mx=5 wampstack.7z wampstack )
    echo "==> Done: ${BUILD_DIR}/wampstack.7z"
else
    echo "    7z not found, skipping wampstack.7z (install p7zip-full / 7zip)."
fi

echo "==> Building the Inno Setup installer (optional)..."
ISCC="$HOME/.wine/drive_c/Program Files/Inno Setup 7/ISCC.exe"
if [ -f "${ISCC}" ]; then
    cp "${SCRIPT_DIR}/install-files/innosetup.iss" "${BUILD_DIR}/wampstack.iss"
    ( cd "${BUILD_DIR}" && wine "${ISCC}" wampstack.iss )
    echo "    Also built: ${BUILD_DIR}/wampstack-setup.exe"
else
    echo "    Inno Setup not found under Wine (${ISCC}), skipping .exe installer."
    echo "    One-time setup: wine innosetup-7.x.x.exe /VERYSILENT"
    echo "    (see installer/wampstack.iss for the installer script itself)."
fi

