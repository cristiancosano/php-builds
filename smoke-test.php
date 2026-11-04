<?php

// Comprobaciones comunes a todas las plataformas. Cada una solo se ejecuta si la
// plataforma debería tener esa extensión, así que nada falta sin que se note.
//
// Uso: php -n smoke-test.php <versión esperada> <macos|linux|windows>

function readList(string $path): array
{
    if (!is_file($path)) {
        return [];
    }
    $lines = array_map('trim', file($path));

    return array_values(array_filter($lines, fn ($line) => $line !== '' && $line[0] !== '#'));
}

function fail(string $message): never
{
    fwrite(STDERR, "FALLO: {$message}\n");
    exit(1);
}

[$expected, $platform] = array_slice($argv, 1) + [null, null];
if ($expected === null || !in_array($platform, ['macos', 'linux', 'windows'], true)) {
    fail('uso: php -n smoke-test.php <versión> <macos|linux|windows>');
}

if (PHP_VERSION !== $expected) {
    fail('versión ' . PHP_VERSION . ", se esperaba {$expected}");
}

$wanted = array_diff(
    readList(__DIR__ . '/extensions.txt'),
    readList(__DIR__ . "/exclude-{$platform}.txt"),
);

$loaded = array_map('strtolower', get_loaded_extensions());
foreach ($wanted as $extension) {
    $name = $extension === 'opcache' ? 'zend opcache' : $extension;
    if (!in_array($name, $loaded, true)) {
        fail("falta la extensión {$extension}");
    }
}
echo 'ok: ' . count($wanted) . " extensiones\n";

$checks = [
    'pdo_sqlite' => function () {
        $pdo = new PDO('sqlite::memory:');
        $pdo->exec('create table t (a)');
        $pdo->exec('insert into t values (42)');

        return $pdo->query('select a from t')->fetchColumn() == 42;
    },
    'pdo_mysql' => fn () => in_array('mysql', PDO::getAvailableDrivers(), true),
    'pdo_pgsql' => fn () => in_array('pgsql', PDO::getAvailableDrivers(), true),
    'gd' => function () {
        $gd = gd_info();

        return $gd['JPEG Support'] && $gd['WebP Support'] && $gd['FreeType Support'] && $gd['PNG Support'];
    },
    'curl' => function () {
        if ((curl_version()['features'] & CURL_VERSION_HTTP2) === 0) {
            return false;
        }
        $handle = curl_init('https://www.php.net/');
        curl_setopt_array($handle, [CURLOPT_NOBODY => true, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 30]);
        curl_exec($handle);
        $error = curl_error($handle);
        if ($error !== '') {
            fwrite(STDERR, "curl: {$error}\n");
        }

        return curl_getinfo($handle, CURLINFO_RESPONSE_CODE) === 200;
    },
    'intl' => fn () => (new NumberFormatter('es_ES', NumberFormatter::DECIMAL))->format(1234.5) === '1.234,5',
    'sodium' => fn () => strlen(sodium_crypto_secretbox_keygen()) === 32,
    'imagick' => fn () => in_array('WEBP', Imagick::queryFormats(), true),
];

foreach ($checks as $extension => $check) {
    if (!in_array($extension, $wanted, true)) {
        echo "omitido: {$extension}\n";
        continue;
    }
    if (!$check()) {
        fail($extension);
    }
    echo "ok: {$extension}\n";
}

echo "Comprobaciones comunes superadas para PHP {$expected} en {$platform}.\n";
