# wampstack-builder

Builds a single zip (`wampstack-v1.zip`) with Apache + MariaDB + PHP +
phpMyAdmin, pinned versions, ready to use on a Windows installation.

## Usage

1. Open `build.sh` and review/adjust the versions and download URLs at the
   top of the script (Apache Lounge, windows.php.net, MariaDB and phpMyAdmin
   change their exact filename per release — always verify this on their
   download pages, see the comments in build.sh).
2. In `conf-templates/phpmyadmin.config.php` (phpMyAdmin config): change
  `blowfish_secret` to something unique per build.
3. Run:
   ```
   chmod +x build.sh
   ./build.sh
   ```
4. Result: `build/wampstack-v1.zip`.

## Client side

1. Download `wampstack-v1.zip` and extract it (e.g. to `C:\wampstack`).
2. Click `install.bat` (it will try to run with administrator rights).
3. Done: `http://localhost/` and `http://localhost/phpmyadmin/`
   (also via `https://`; `install.bat` creates a self-signed certificate
   and imports it into the Windows trusted root store, so no browser
   warning, also corrects Firefox via a policies.json file).

`manage.bat` starts, stops, restarts and queries the two services — just a
handy script to control the services. Run it without arguments for an
interactive menu, or from the command line,
e.g. `manage.bat stop mariadb`, `manage.bat start all`.

`uninstall.bat` removes the two Windows services again (useful to
reinstall/test) without touching any data or config.

## What build.sh does

- Downloads the 4 components
- Unpacks them into `apache24/`, `php/`, `mariadb/`, `phpmyadmin/`
- Copies the config from `conf-templates/` over them
- Fills the service names into `install.bat` / `manage.bat` / `uninstall.bat`
- Forces CRLF line endings on the Windows text files (.bat/.conf/.ini)
- Zips everything into `build/wampstack-v1.zip`

## Customizing

- Verify/change the versions for Apache, MariaDB, PHPi and phpMyAdmin in
  `build.sh`
- **Service names** — `SVC_APACHE` and `SVC_MARIADB` in `build.sh` (defaults
  `WAMP_Apache` and `WAMP_MariaDB`). They are substituted for the
  `__SVC_APACHE__` / `__SVC_MARIADB__` placeholders in `install-files/*.bat`
  at build time, so all three scripts always agree on the names. Pick
  something recognisable for usage so the stack doesn't clash with an
  already-installed Apache/MariaDB.
- `conf-templates/httpd.conf` — Apache config (port, modules, DocumentRoot,
  phpMyAdmin alias). `__BASEDIR__` is automatically replaced by `install.bat`
  with the actual installation path.
- `conf-templates/php.ini` — which extensions are enabled, timezone, limits.
- `conf-templates/phpmyadmin.config.php` — phpMyAdmin config. Definitely change
  `blowfish_secret` to something unique per build.
- `htdocs-template/index.php` — landing page in htdocs; links to phpMyAdmin
  and automatically lists every directory created in htdocs (1 level deep).
