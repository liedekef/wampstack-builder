# wampstack-builder

Builds a single zip (`wampstack.zip`) with Apache + MariaDB + PHP +
phpMyAdmin, pinned versions, ready to use on a Windows installation.

## Usage

1. Open `build.sh` and review/adjust the versions and download URLs at the
   top of the script (Apache Lounge, windows.php.net, MariaDB and phpMyAdmin
   change their exact filename per release — always verify this on their
   download pages, see the comments in build.sh).
2. Run:
   ```
   chmod +x build.sh
   ./build.sh
   ```
3. Result: `build/wampstack.zip`.

## Client side

1. Download `wampstack.zip` and extract it (e.g. to `C:\wampstack`).
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
- Copies the config from `conf-templates/` over them, and creates the four
  "own settings" directories (see below)
- Fills the service names into `install.bat` / `manage.bat` / `uninstall.bat`
- Forces CRLF line endings on the Windows text files (.bat/.conf/.ini/.txt)
- Zips everything into `build/wampstack.zip`

## Client-side own settings (conf.d per component)

Every component reads a directory of extra files in addition to its main config
file, **after** that main config file, so a setting in one of those files always
wins:

| Component | Own settings | Read by |
| --- | --- | --- |
| Apache | `apache24\conf\custom\*.conf` | `IncludeOptional conf/custom/*.conf` in `httpd.conf` |
| MariaDB | `mariadb\conf.d\*.cnf` / `*.ini` | `?includedir __BASEDIR__/mariadb/conf.d/` in `my.ini` |
| PHP | `php\conf.d\*.ini` | PHP's own ini scan dir (`PHP_INI_SCAN_DIR`, see below) |
| phpMyAdmin | `phpmyadmin\conf.d\*.php` | a loop at the bottom of `config.inc.php` |

Each of those directories ships with a `README.txt` for the students, with a
short example. The main config files are replaced on every upgrade; the files
students put in these directories are not, which is the whole point: they can
upgrade the stack without losing their own settings, and without having to
remember what they changed in a config file that is overwritten anyway.

Two things worth knowing:

- **PHP is the odd one out**: mod_php has no httpd.conf directive for a second
  ini directory (`PHPIniDir` is the only one it has), so `php\conf.d` is
  registered as PHP's ini scan dir through the `PHP_INI_SCAN_DIR` environment
  variable. `install.bat` writes it into the Apache service key in the registry
  (`HKLM\...\Services\<service>\Environment`, a `REG_MULTI_SZ` with one
  `NAME=value` entry), which is where a Windows service picks up environment
  variables from; services.exe merges them in on every start. `install.bat`
  also does that when the service already exists, because the value is read at
  service start and not at install time. It is removed again by
  `uninstall.bat`, which deletes the whole service key. So after editing a file
  in `php\conf.d`, `manage.bat restart apache` is all that is needed — no
  re-run of `install.bat`, no Apache restart of the service registration.
- **A stack that was moved to another folder** has stale absolute paths in
  `httpd.conf`/`my.ini`/`php\php.ini` and a stale `PHP_INI_SCAN_DIR`; extract it
  where it should live and run `install.bat` again (that is what fills in the
  paths).

## Customizing

- Verify/change the versions for Apache, MariaDB, PHPi and phpMyAdmin in
  `build.sh`
- **`build.config`** — optional, plain shell assignments that are sourced right
  after the defaults in `build.sh`, so they override them:
  ```
  SVC_APACHE="Course_Apache"
  SVC_MARIADB="Course_MariaDB"
  ```
  Put YOUR settings here instead of in `build.sh`, so updating wampstack-builder
  (`git pull`) never overwrites them.
- **Service names** — `SVC_APACHE` and `SVC_MARIADB` in `build.sh` (defaults
  `WAMP_Apache` and `WAMP_MariaDB`). They are substituted for the
  `__SVC_APACHE__` / `__SVC_MARIADB__` placeholders in `install-files/*.bat`
  at build time, so all three scripts always agree on the names. Pick
  something recognisable for usage so the stack doesn't clash with an
  already-installed Apache/MariaDB.
- `conf-templates/httpd.conf` — Apache config (port, modules, DocumentRoot,
  phpMyAdmin alias, the `IncludeOptional` for `conf/custom`). `__BASEDIR__` is
  automatically replaced by `install.bat` with the actual installation path.
- `conf-templates/php.ini` — which extensions are enabled, timezone, limits.
  The students' own settings go in `php\conf.d\*.ini`, which `install.bat`
  registers as PHP's ini scan directory.
- `conf-templates/my.ini` — MariaDB config (port, bind-address, the
  `?includedir` for `conf.d`). `__BASEDIR__` is replaced by `install.bat`, like
  in `httpd.conf`.
- `conf-templates/phpmyadmin.config.php` — phpMyAdmin config, plus the loop
  that reads `phpmyadmin\conf.d\*.php`.
  `__BLOWFISH_SECRET__` is replaced by `install.bat` on each install with a
  freshly generated random value, so nothing to change here per build.
- `htdocs-template/index.php` — landing page in htdocs; links to phpMyAdmin
  and automatically lists every directory created in htdocs (1 level deep).
