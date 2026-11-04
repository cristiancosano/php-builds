#!/usr/bin/env bash
# Comprueba un PHP compilado en macOS o Linux antes de publicarlo.
# En Windows se ejecuta directamente smoke-test.php.
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

case "$(uname -s)" in
  Darwin) PLATFORM=macos ;;
  Linux) PLATFORM=linux ;;
  *) fail "sistema no soportado: $(uname -s)" ;;
esac

"$DIST/php-fpm" -n -v | grep -q "^PHP $EXPECTED (fpm-fcgi)" || fail "php-fpm no informa de la versión $EXPECTED"

# Un binario estático no puede depender de librerías externas.
for binary in "$PHP" "$DIST/php-fpm"; do
  if [ "$PLATFORM" = macos ]; then
    foreign="$(otool -L "$binary" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/usr/lib|/System)/' || true)"
    [ -z "$foreign" ] || fail "$binary enlaza fuera del sistema: $foreign"
  elif ldd "$binary" 2>&1 | grep -q '=>'; then
    fail "$binary enlaza librerías dinámicas"
  fi
done

"$PHP" -n "$ROOT/smoke-test.php" "$EXPECTED" "$PLATFORM"

if [ -f "$DIST/xdebug.so" ]; then
  # Es código PHP: las comillas simples evitan que el shell lo interprete.
  # shellcheck disable=SC2016
  "$PHP" -n -d "zend_extension=$DIST/xdebug.so" -r 'exit(phpversion("xdebug") ? 0 : 1);' || fail "xdebug.so no carga"
  echo "ok: xdebug"
fi

echo "Todas las comprobaciones han pasado para PHP $EXPECTED."
