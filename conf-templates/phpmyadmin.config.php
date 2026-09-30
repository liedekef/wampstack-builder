<?php
/**
 * phpMyAdmin config for Wampstack Builder.
 * __BLOWFISH_SECRET__ is replaced by install.bat
 * with a freshly generated random value, so every install gets its own
 * secret without needing anything changed per build.
 *
 * Your own settings go in the conf.d subdirectory, as .php files:
 * everything in there is read after this file, so it overrides what is set
 * here. Use that instead of editing this file: this file is replaced with
 * every new version of the stack, your own files in conf.d are not.
 *
 *     phpmyadmin\conf.d\my.php
 *         $cfg['Servers'][$i]['host'] = '127.0.0.1';
 *         $cfg['MaxExactCount'] = false;
 *
 * The files are read by the loop at the bottom of this file, from within
 * phpMyAdmin's own config loading, so they can use $cfg just like this file.
 */
$cfg['blowfish_secret'] = '__BLOWFISH_SECRET__';

$i = 0;
$i++;
$cfg['Servers'][$i]['auth_type']     = 'config';
$cfg['Servers'][$i]['user']          = 'root';
$cfg['Servers'][$i]['password']      = '';
$cfg['Servers'][$i]['host']          = '127.0.0.1';
$cfg['Servers'][$i]['port']          = '3306';
$cfg['Servers'][$i]['compress']      = false;
$cfg['Servers'][$i]['AllowNoPassword'] = true;

$cfg['UploadDir'] = '';
$cfg['SaveDir'] = '';

// No calling out to phpmyadmin.net to check for a newer version.
$cfg['VersionCheck'] = false;

/**
 * Read the user's own configuration files, in alphabetical order, last so
 * they win from everything above.
 */
foreach (glob(__DIR__ . '/conf.d/*.php') as $userConfigFile) {
    include $userConfigFile;
}
unset($userConfigFile);
