#!/usr/bin/env bash
# Compila php y php-fpm estáticos para macOS arm64 con static-php-cli.
#
# Uso:   ./build.sh <8.4|8.4.27>
#        BUILD_XDEBUG=1 ./build.sh 8.4   # además, xdebug.so como extensión compartida
#
# No instala nada en el sistema: si falta una herramienta, termina e indica cuál.
set -euo pipefail

SPC_VERSION="2.8.5"
SPC_SHA256="acf2f25d56d0cbf8e65aa82e5054fef555f7be7c5c38046c6e0819f266d83225"
SPC_URL="https://github.com/crazywhalecc/static-php-cli/releases/download/${SPC_VERSION}/spc-macos-aarch64.tar.gz"

# Bibliotecas opcionales: gd con JPEG, WebP y FreeType, y curl con HTTP/2.
WITH_LIBS="freetype,libjpeg,libwebp,nghttp2"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_XDEBUG="${BUILD_XDEBUG:-0}"

die() {
  echo "error: $*" >&2
  exit 1
}

[ "$#" -eq 1 ] || die "uso: $0 <versión de PHP, p. ej. 8.4 u 8.4.27>"
REQUESTED="$1"

[ "$(uname -s)-$(uname -m)" = "Darwin-arm64" ] || die "este script solo es para macOS arm64"

# Bison de Apple es 2.3 y spc pide 3 o superior; el de Homebrew es keg-only.
# El cambio de PATH afecta solo a este proceso.
if [ -x /opt/homebrew/opt/bison/bin/bison ]; then
  PATH="/opt/homebrew/opt/bison/bin:$PATH"
  export PATH
fi

# Si xcode-select apunta a un Xcode más antiguo que el SDK de las Command Line
# Tools, su linker no entiende ese SDK y clang no puede generar ejecutables.
# Usar las Command Line Tools mantiene emparejados linker y SDK. Afecta solo a
# este proceso y se respeta un DEVELOPER_DIR ya definido, como en CI.
CLT_DIR="/Library/Developer/CommandLineTools"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -z "${GITHUB_ACTIONS:-}" ] && [ -x "$CLT_DIR/usr/bin/ld" ]; then
  DEVELOPER_DIR="$CLT_DIR"
  export DEVELOPER_DIR
fi

# Se comprueba aquí porque `spc doctor --auto-fix=never` termina con código 0 aunque falle algo.
missing=""
for tool in curl jq make bison re2c flex pkg-config git autoconf automake tar libtool \
  glibtoolize unzip xz gzip bzip2 cmake shasum; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if command -v bison >/dev/null 2>&1; then
  bison_major="$(bison --version | sed -n 's/^bison (GNU Bison) \([0-9]*\)\..*/\1/p')"
  if [ "${bison_major:-0}" -lt 3 ]; then
    missing="$missing bison>=3"
  fi
fi
[ -z "$missing" ] || die "faltan herramientas:$missing (build.sh no las instala)"

case "$REQUESTED" in
  [0-9]*.[0-9]*.[0-9]*)
    PHP_VERSION="$REQUESTED"
    ;;
  [0-9]*.[0-9]*)
    PHP_VERSION="$(curl -sS -f "https://www.php.net/releases/index.php?json&version=${REQUESTED}" | jq -er .version)"
    ;;
  *)
    die "versión no válida: $REQUESTED"
    ;;
esac

EXTENSIONS="$(grep -Ev '^[[:space:]]*(#|$)' "$ROOT/extensions.txt" | paste -sd, -)"
[ -n "$EXTENSIONS" ] || die "extensions.txt está vacío"

SPC_DIR="$ROOT/.work/spc-$SPC_VERSION"
SPC="$SPC_DIR/spc"
if [ ! -x "$SPC" ]; then
  mkdir -p "$SPC_DIR"
  curl -sS -f -L -o "$SPC_DIR/spc.tar.gz" "$SPC_URL"
  echo "$SPC_SHA256  $SPC_DIR/spc.tar.gz" | shasum -a 256 -c -
  tar -xzf "$SPC_DIR/spc.tar.gz" -C "$SPC_DIR"
  rm -f "$SPC_DIR/spc.tar.gz"
fi

# spc usa el directorio actual para downloads/, source/, buildroot/ y log/.
WORK="$ROOT/.work/php-$PHP_VERSION"
DIST="$ROOT/dist/$PHP_VERSION"
mkdir -p "$WORK" "$DIST"
cd "$WORK"

download_exts="$EXTENSIONS"
shared_args=()
if [ "$BUILD_XDEBUG" = "1" ]; then
  download_exts="$EXTENSIONS,xdebug"
  shared_args=(--build-shared=xdebug)
fi

# spc solo usa su propio pkg-config, no el del sistema, y lo instala dentro de
# $WORK/pkgroot. Las comprobaciones de arriba garantizan que no le falte nada
# más, así que este arreglo automático no llega a lanzar `brew install`.
"$SPC" doctor --auto-fix </dev/null
"$SPC" download --with-php="$PHP_VERSION" --for-extensions="$download_exts" --retry=3 </dev/null
"$SPC" build "$EXTENSIONS" --with-libs="$WITH_LIBS" --build-cli --build-fpm \
  ${shared_args[@]+"${shared_args[@]}"} </dev/null

cp -f buildroot/bin/php buildroot/bin/php-fpm "$DIST/"
rm -rf "$DIST/license"
cp -R buildroot/license "$DIST/license"
if [ "$BUILD_XDEBUG" = "1" ]; then
  cp -f buildroot/modules/xdebug.so "$DIST/"
fi

cd "$DIST"
shasum -a 256 php php-fpm > SHA256SUMS
if [ "$BUILD_XDEBUG" = "1" ]; then
  shasum -a 256 xdebug.so >> SHA256SUMS
fi
cat SHA256SUMS
