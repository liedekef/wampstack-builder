<?php
/**
 * Landing page for htdocs. Shows a link to phpMyAdmin and, 1 level
 * deep, a clickable link for every directory a student creates in htdocs
 * — so a student never has to type their own project path into the
 * address bar.
 */

$base = __DIR__;
$dirs = array_filter(glob($base . '/*'), function ($path) {
    return is_dir($path) && strtolower(basename($path)) !== 'phpmyadmin';
});
sort($dirs);
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Wampstack Builder</title>
<style>
    body { font-family: sans-serif; max-width: 600px; margin: 40px auto; line-height: 1.5; }
    h1 { margin-bottom: 0; }
    .versie { color: #666; margin-top: 0; }
    ul { padding-left: 1.2em; }
    li { margin: 4px 0; }
</style>
</head>
<body>
    <h1>Welcome to your own webserver</h1>
    <h2>Tools</h2>
    <ul>
        <li><a href="phpmyadmin/">phpMyAdmin</a></li>
    </ul>

    <h2>Projects</h2>
    <ul>
        <?php if (empty($dirs)): ?>
            <li><em>(no folders in htdocs yet &mdash; create one here yourself)</em></li>
        <?php else: ?>
            <?php foreach ($dirs as $dir): $name = basename($dir); ?>
                <li><a href="<?= htmlspecialchars(rawurlencode($name)) ?>/"><?= htmlspecialchars($name) ?></a></li>
            <?php endforeach; ?>
        <?php endif; ?>
    </ul>
</body>
</html>
