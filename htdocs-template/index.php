<?php
/**
 * Landing page for htdocs. Shows a link to phpMyAdmin and, 1 level
 * deep, a clickable link for every directory created in htdocs.
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
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Wampstack Builder</title>
<style>
    :root {
        --bg: #f4f5f7;
        --surface: #ffffff;
        --text: #1c1e21;
        --muted: #6b7280;
        --border: #e5e7eb;
        --accent: #4f46e5;
        --accent-soft: #eef2ff;
        --shadow: 0 1px 2px rgba(0, 0, 0, .04), 0 1px 8px rgba(0, 0, 0, .04);
    }
    @media (prefers-color-scheme: dark) {
        :root {
            --bg: #0f1115;
            --surface: #181b21;
            --text: #e7e9ec;
            --muted: #9099a6;
            --border: #2a2e37;
            --accent: #8183f4;
            --accent-soft: #22243a;
            --shadow: 0 1px 2px rgba(0, 0, 0, .3), 0 1px 8px rgba(0, 0, 0, .3);
        }
    }

    * { box-sizing: border-box; }
    body {
        margin: 0;
        padding: 48px 20px;
        background: var(--bg);
        color: var(--text);
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        line-height: 1.5;
    }
    .wrap { max-width: 720px; margin: 0 auto; }

    header { display: flex; align-items: center; gap: 14px; margin-bottom: 8px; }
    .logo {
        flex: 0 0 auto;
        width: 44px; height: 44px;
        border-radius: 12px;
        background: linear-gradient(135deg, var(--accent), #a78bfa);
        display: flex; align-items: center; justify-content: center;
        font-size: 20px;
    }
    h1 { font-size: 22px; margin: 0; }
    .subtitle { color: var(--muted); margin: 2px 0 0; font-size: 14px; }

    .badges { display: flex; flex-wrap: wrap; gap: 8px; margin: 20px 0 36px; }
    .badge {
        font-size: 12px; font-weight: 600; letter-spacing: .02em;
        padding: 5px 10px; border-radius: 999px;
        background: var(--accent-soft); color: var(--accent);
    }

    section { margin-bottom: 32px; }
    section h2 {
        font-size: 12px; text-transform: uppercase; letter-spacing: .06em;
        color: var(--muted); margin: 0 0 12px;
    }

    .card-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 12px; }
    .card {
        display: flex; align-items: center; gap: 10px;
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: 12px;
        padding: 14px 16px;
        text-decoration: none;
        color: var(--text);
        box-shadow: var(--shadow);
        transition: transform .12s ease, border-color .12s ease;
    }
    .card:hover { transform: translateY(-2px); border-color: var(--accent); }
    .card .icon { font-size: 18px; flex: 0 0 auto; }
    .card .label { font-size: 14px; font-weight: 500; overflow-wrap: anywhere; }

    .empty {
        border: 1px dashed var(--border);
        border-radius: 12px;
        padding: 18px 16px;
        color: var(--muted);
        font-size: 14px;
    }
    .empty code {
        background: var(--accent-soft); color: var(--accent);
        padding: 1px 6px; border-radius: 6px; font-size: 13px;
    }

    footer { color: var(--muted); font-size: 12px; text-align: center; margin-top: 40px; }
</style>
</head>
<body>
<div class="wrap">

    <header>
        <div class="logo">🚀</div>
        <div>
            <h1>Your local web server is running</h1>
            <p class="subtitle">Apache &middot; MariaDB &middot; PHP &middot; phpMyAdmin</p>
        </div>
    </header>

    <div class="badges">
        <span class="badge">PHP <?= htmlspecialchars(phpversion()) ?></span>
        <span class="badge"><?= htmlspecialchars($_SERVER['SERVER_SOFTWARE'] ?? 'Apache') ?></span>
    </div>

    <section>
        <h2>Tools</h2>
        <div class="card-grid">
            <a class="card" href="phpmyadmin/">
                <span class="icon">🗄️</span>
                <span class="label">phpMyAdmin</span>
            </a>
        </div>
    </section>

    <section>
        <h2>Projects</h2>
        <?php if (empty($dirs)): ?>
            <div class="empty">
                No folders in <code>htdocs</code> yet &mdash; create one yourself and it shows up here automatically.
            </div>
        <?php else: ?>
            <div class="card-grid">
                <?php foreach ($dirs as $dir): $name = basename($dir); ?>
                    <a class="card" href="<?= htmlspecialchars(rawurlencode($name)) ?>/">
                        <span class="icon">📁</span>
                        <span class="label"><?= htmlspecialchars($name) ?></span>
                    </a>
                <?php endforeach; ?>
            </div>
        <?php endif; ?>
    </section>

    <footer>Wampstack Builder</footer>

</div>
</body>
</html>
