<?php
/**
 * phpMyAdmin config for Wampstack Builder.
 * __BLOWFISH_SECRET__ is replaced by install.bat
 * with a freshly generated random value, so every install gets its own
 * secret without needing anything changed per build.
 */
$cfg['blowfish_secret'] = '__BLOWFISH_SECRET__';

$i = 0;
$i++;
$cfg['Servers'][$i]['auth_type']     = 'config';
$cfg['Servers'][$i]['user']          = 'root';
$cfg['Servers'][$i]['password']      = '';
$cfg['Servers'][$i]['host']          = 'localhost';
$cfg['Servers'][$i]['port']          = '3306';
$cfg['Servers'][$i]['compress']      = false;
$cfg['Servers'][$i]['AllowNoPassword'] = true;

$cfg['UploadDir'] = '';
$cfg['SaveDir'] = '';
