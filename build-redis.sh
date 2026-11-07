#!/usr/bin/env bash
# Compila redis-server, redis-cli y redis-benchmark (más redis-sentinel,
# redis-check-aof y redis-check-rdb, que son el mismo binario que redis-server)
# a partir del código fuente oficial, sin TLS ni módulos.
#
# - macOS: compila con las herramientas del sistema. El resultado solo depende
#   de libSystem.
# - Linux: compila dentro de un contenedor Alpine, enlazado estáticamente con
#   musl, para que funcione en cualquier distribución. Solo necesita Docker.
#
# Uso: ./build-redis.sh <8.2.11>
# Deja el paquete en dist/redis-<versión>/{bin,LICENSE.txt,redis.conf,...}.
set -euo pipefail

ALPINE_IMAGE="alpine:3.22"
HASHES_URL="https://raw.githubusercontent.com/redis/redis-hashes/master/README"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$#" -eq 1 ] || { echo "uso: $0 <versión de Redis, p. ej. 8.2.11>" >&2; exit 2; }
VERSION="$1"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: versión no válida: $VERSION" >&2
  exit 2
fi
if [ "${VERSION%%.*}" -lt 8 ]; then
  # Redis 7.x se distribuye bajo RSALv2/SSPLv1, que no dejan claro si podemos
  # redistribuir binarios. Desde la 8.0 también se ofrece bajo AGPLv3.
  echo "error: solo se compila Redis 8 o posterior (licencia AGPLv3)" >&2
  exit 2
fi

case "$(uname -s)" in
  Linux)
    if [ ! -f /etc/alpine-release ]; then
      # Se vuelve a ejecutar este mismo script dentro de Alpine.
      exec docker run --rm -v "$ROOT:/work" -w /work \
        -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
        "$ALPINE_IMAGE" sh -c 'apk add --no-cache bash build-base linux-headers curl >/dev/null && exec bash ./build-redis.sh "$0"' "$VERSION"
    fi
    ;;
  Darwin)
    # Igual que build.sh: un Xcode más antiguo que el SDK no puede enlazar.
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
    ;;
  *)
    echo "error: sistema no soportado: $(uname -s)" >&2
    exit 1
    ;;
esac

WORK="$ROOT/.work/redis"
DIST="$ROOT/dist/redis-$VERSION"
TARBALL="redis-$VERSION.tar.gz"
mkdir -p "$WORK"

# Código fuente oficial, comprobado con el sha256 que publica Redis en
# redis/redis-hashes.
expected="$(curl -fsSL --retry 3 "$HASHES_URL" |
  awk -v name="$TARBALL" '$1 == "hash" && $2 == name && $3 == "sha256" { print $4 }')"
if ! [[ "$expected" =~ ^[0-9a-f]{64}$ ]]; then
  echo "error: redis-hashes no tiene el sha256 de $TARBALL" >&2
  exit 1
fi
curl -fsSL --retry 3 -o "$WORK/$TARBALL" "https://download.redis.io/releases/$TARBALL"
if command -v sha256sum >/dev/null; then
  actual="$(sha256sum "$WORK/$TARBALL" | cut -d' ' -f1)"
else
  actual="$(shasum -a 256 "$WORK/$TARBALL" | cut -d' ' -f1)"
fi
if [ "$actual" != "$expected" ]; then
  echo "error: el sha256 de $TARBALL no coincide ($actual, se esperaba $expected)" >&2
  exit 1
fi

SRC="$WORK/redis-$VERSION"
rm -rf "$SRC"
tar -xzf "$WORK/$TARBALL" -C "$WORK"

# Redis 8.2 a 8.6 incluyen fast_float, en C++. Sin excepciones (no las usa) no
# queda ninguna referencia al runtime de C++ y en macOS no se enlaza libc++.
if [ -f "$SRC/deps/fast_float/Makefile" ]; then
  sed -i.orig 's/^DEFS=\(.*\)$/DEFS=\1 -fno-exceptions/' "$SRC/deps/fast_float/Makefile"
  grep -q '^DEFS=.*-fno-exceptions' "$SRC/deps/fast_float/Makefile" ||
    { echo "error: no se ha podido parchear deps/fast_float/Makefile" >&2; exit 1; }
fi

# mkreleasehdr.sh lee el commit con git: sin esto tomaría el de este repositorio.
export GIT_CEILING_DIRECTORIES="$WORK"

make_args=(BUILD_TLS=no USE_SYSTEMD=no)
if [ "$(uname -s)" = Linux ]; then
  # Estático con musl. REDIS_LDFLAGS solo se aplica a los binarios de Redis, no
  # a los módulos de prueba.
  make_args+=(MALLOC=jemalloc REDIS_LDFLAGS="-static")
  if [ "$(uname -m)" = aarch64 ]; then
    # jemalloc fija el tamaño de página al compilar. Con 64 KB funciona también
    # en kernels de 16 y 64 KB (Raspberry Pi 5, Asahi, algunos servidores).
    make_args+=(JEMALLOC_CONFIGURE_OPTS="--with-lg-page=16")
  fi
else
  # Redis 8.2 añade -lstdc++ aunque no use su runtime: así no queda enlazado.
  make_args+=(REDIS_LDFLAGS="-Wl,-dead_strip_dylibs")
fi
jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
# Solo los binarios: ni los módulos (RediSearch, RedisJSON...), que necesitan
# Rust y otras herramientas, ni los módulos de prueba que `make all` añade.
make -C "$SRC/src" -j"$jobs" "${make_args[@]}" redis-server redis-cli redis-benchmark

rm -rf "$DIST"
mkdir -p "$DIST/bin"
for tool in redis-server redis-cli redis-benchmark; do
  cp "$SRC/src/$tool" "$DIST/bin/"
  strip "$DIST/bin/$tool"
done
# Igual que `make install`: redis-server hace de sentinel y de comprobador de
# RDB y AOF según el nombre con el que se ejecuta.
for tool in redis-sentinel redis-check-aof redis-check-rdb; do
  ln -s redis-server "$DIST/bin/$tool"
done
for file in LICENSE.txt REDISCONTRIBUTIONS.txt 00-RELEASENOTES redis.conf sentinel.conf; do
  if [ -f "$SRC/$file" ]; then
    cp "$SRC/$file" "$DIST/"
  fi
done

if [ -n "${HOST_UID:-}" ]; then
  chown -R "$HOST_UID:${HOST_GID:-$HOST_UID}" "$ROOT/dist" "$WORK"
fi
ls -l "$DIST/bin"
