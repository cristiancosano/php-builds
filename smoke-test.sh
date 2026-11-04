#!/usr/bin/env bash
# Comprueba un PHP compilado antes de publicarlo. Termina con error ante el primer fallo.
#
# Uso: ./smoke-test.sh <carpeta con php y php-fpm> <versión esperada>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$#" -eq 2 ] || { echo "uso: $0 <carpeta> <versión>" >&2; exit 2; }
DIST="$(cd "$1" && pwd)"
EXPECTED="$2"
PHP="$DIST/php"

fail() {
  echo "FALLO: $*" >&2
  exit 1
}

actual="$("$PHP" -n -r 'echo PHP_VERSION;')"
[ "$actual" = "$EXPECTED" ] || fail "versión $actual, se esperaba $EXPECTED"

"$DIST/php-fpm" -n -v | grep -q "^PHP $EXPECTED (fpm-fcgi)" || fail "php-fpm no informa de la versión $EXPECTED"

# Un binario estático solo puede depender de librerías del sistema.
for binary in "$PHP" "$DIST/php-fpm"; do
  foreign="$(otool -L "$binary" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/usr/lib|/System)/' || true)"
  [ -z "$foreign" ] || fail "$binary enlaza fuera del sistema: $foreign"
done

modules="$("$PHP" -n -m | tr '[:upper:]' '[:lower:]')"
while IFS= read -r extension; do
  case "$extension" in
    '' | '#'*) continue ;;
    opcache) name="zend opcache" ;;
    *) name="$extension" ;;
  esac
  grep -qx "$name" <<<"$modules" || fail "falta la extensión $extension"
done <"$ROOT/extensions.txt"

# Es código PHP: las comillas simples evitan que el shell expanda sus variables.
# shellcheck disable=SC2016
"$PHP" -n -r '
$checks = [
    "pdo_sqlite" => function () {
        $pdo = new PDO("sqlite::memory:");
        $pdo->exec("create table t (a)");
        $pdo->exec("insert into t values (42)");
        return $pdo->query("select a from t")->fetchColumn() == 42;
    },
    "drivers" => fn () => !array_diff(["mysql", "pgsql", "sqlite"], PDO::getAvailableDrivers()),
    "gd" => function () {
        $gd = gd_info();
        return $gd["JPEG Support"] && $gd["WebP Support"] && $gd["FreeType Support"] && $gd["PNG Support"];
    },
    "curl http2" => fn () => (curl_version()["features"] & CURL_VERSION_HTTP2) > 0,
    "https" => function () {
        $handle = curl_init("https://www.php.net/");
        curl_setopt_array($handle, [CURLOPT_NOBODY => true, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 30]);
        curl_exec($handle);
        return curl_getinfo($handle, CURLINFO_RESPONSE_CODE) === 200;
    },
    "intl" => fn () => (new NumberFormatter("es_ES", NumberFormatter::DECIMAL))->format(1234.5) === "1.234,5",
    "sodium" => fn () => strlen(sodium_crypto_secretbox_keygen()) === 32,
    "imagick" => fn () => in_array("WEBP", Imagick::queryFormats(), true),
];
foreach ($checks as $name => $check) {
    if (!$check()) {
        fwrite(STDERR, "FALLO: $name\n");
        exit(1);
    }
    echo "ok: $name\n";
}
'

if [ -f "$DIST/xdebug.so" ]; then
  "$PHP" -n -d "zend_extension=$DIST/xdebug.so" -r 'exit(phpversion("xdebug") ? 0 : 1);' || fail "xdebug.so no carga"
  echo "ok: xdebug"
fi

echo "Todas las comprobaciones han pasado para PHP $EXPECTED."
