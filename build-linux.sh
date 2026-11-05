#!/usr/bin/env bash
# Compila php y php-fpm totalmente estáticos (musl) para Linux, dentro del
# contenedor Alpine de static-php-cli. Solo necesita git y Docker.
#
# Uso: ./build-linux.sh <8.4.27>
set -euo pipefail

SPC_VERSION="2.8.5"
SPC_COMMIT="4318ef8fa32a02460ec1554746674a7bc42b49fa"
WITH_LIBS="freetype,libjpeg,libwebp,nghttp2"

# spc 2.8.5 descarga libaom de su rama main, que cambia sola. Desde la v3.15.0
# su parche para Linux ya no aplica, así que se fija la última versión compatible.
LIBAOM_PIN="libaom:v3.14.1:https://aomedia.googlesource.com/aom"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$#" -eq 1 ] || { echo "uso: $0 <versión de PHP, p. ej. 8.4.27>" >&2; exit 2; }
PHP_VERSION="$1"

EXTENSIONS="$(grep -Ev '^[[:space:]]*(#|$)' "$ROOT/extensions.txt" |
  grep -vxFf <(grep -Ev '^[[:space:]]*(#|$)' "$ROOT/exclude-linux.txt") |
  paste -sd, -)"

SRC="$ROOT/.work/spc-src-$SPC_VERSION"
if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$ROOT/.work"
  git clone --quiet --depth 1 --branch "$SPC_VERSION" \
    https://github.com/crazywhalecc/static-php-cli.git "$SRC"
fi
actual="$(git -C "$SRC" rev-parse HEAD)"
if [ "$actual" != "$SPC_COMMIT" ]; then
  echo "error: la etiqueta $SPC_VERSION apunta a $actual, se esperaba $SPC_COMMIT" >&2
  exit 1
fi

cd "$SRC"
./bin/spc-alpine-docker download --with-php="$PHP_VERSION" --for-extensions="$EXTENSIONS" \
  --custom-git="$LIBAOM_PIN" --retry=3
./bin/spc-alpine-docker build "$EXTENSIONS" --with-libs="$WITH_LIBS" --build-cli --build-fpm

DIST="$ROOT/dist/$PHP_VERSION"
mkdir -p "$DIST"
cp -f buildroot/bin/php buildroot/bin/php-fpm "$DIST/"
chmod 755 "$DIST/php" "$DIST/php-fpm"
rm -rf "$DIST/license"
cp -R buildroot/license "$DIST/license"
chmod -R u+rwX "$DIST/license"
