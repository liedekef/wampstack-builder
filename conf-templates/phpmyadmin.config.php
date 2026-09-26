<?php
/**
 * phpMyAdmin config for Wampstack Builder.
 * Change $cfg['blowfish_secret'] to something unique for your build
 * (32 random characters will do; it doesn't have to be secret for a
 * local classroom environment, but phpMyAdmin does require a value).
 */
$cfg['blowfish_secret'] = 'change-this-to-32-random-characters!';

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
