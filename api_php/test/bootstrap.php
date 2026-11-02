<?php

declare(strict_types=1);

// Variables mínimas para que Config::get() no falle en los tests (igual que los
// process.env.X ||= 'x' al tope de los test/*.test.js del api/ Node).
$defaults = [
    'DB_HOST' => 'x',
    'DB_USER' => 'x',
    'DB_PASS' => 'x',
    'DB_NAME' => 'x',
    'FTP_HOST' => 'x',
    'FTP_USER' => 'x',
    'FTP_PASS' => 'x',
    'JWT_SECRET' => 'test-secret',
    'CACHE_DIR' => __DIR__ . '/../cache-test',
];
foreach ($defaults as $k => $v) {
    if (getenv($k) === false) {
        putenv("{$k}={$v}");
        $_ENV[$k] = $v;
    }
}

require __DIR__ . '/../vendor/autoload.php';
