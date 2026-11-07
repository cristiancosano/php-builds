#!/usr/bin/env bash
# Comprueba un paquete de Redis: versión, dependencias, y que redis-server
# arranca y responde PONG a redis-cli.
#
# Uso: ./smoke-test-redis.sh dist/redis-8.2.11 8.2.11
set -euo pipefail

[ "$#" -eq 2 ] || { echo "uso: $0 <carpeta> <versión>" >&2; exit 2; }
DIR="$(cd "$1" && pwd)"
VERSION="$2"
BIN="$DIR/bin"

fail() { echo "FALLO: $*" >&2; exit 1; }

for tool in redis-server redis-cli redis-benchmark; do
  [ -x "$BIN/$tool" ] || fail "falta bin/$tool"
done
for tool in redis-sentinel redis-check-aof redis-check-rdb; do
  [ -e "$BIN/$tool" ] || fail "falta bin/$tool"
done
[ -f "$DIR/LICENSE.txt" ] || fail "falta LICENSE.txt"
grep -q "GNU AFFERO GENERAL PUBLIC LICENSE" "$DIR/LICENSE.txt" || fail "LICENSE.txt no incluye la AGPLv3"

"$BIN/redis-server" --version | tee /dev/stderr | grep -q "v=$VERSION " || fail "redis-server no es la versión $VERSION"
"$BIN/redis-cli" --version | grep -q "$VERSION" || fail "redis-cli no es la versión $VERSION"
"$BIN/redis-benchmark" --version | grep -q "$VERSION" || fail "redis-benchmark no es la versión $VERSION"

case "$(uname -s)" in
  Darwin)
    for tool in redis-server redis-cli redis-benchmark; do
      deps="$(otool -L "$BIN/$tool" | tail -n +2 | awk '{print $1}')"
      if [ "$deps" != "/usr/lib/libSystem.B.dylib" ]; then
        fail "$tool depende de algo más que libSystem: $(echo "$deps" | paste -sd' ' -)"
      fi
    done
    ;;
  Linux)
    for tool in redis-server redis-cli redis-benchmark; do
      file "$BIN/$tool" | grep -Eq "statically linked|static-pie linked" || fail "$tool no es estático: $(file "$BIN/$tool")"
    done
    ;;
esac

# Arranque en un puerto libre, sin persistencia, con un directorio propio.
TMP="$(mktemp -d)"
PORT=$((20000 + RANDOM % 20000))
cleanup() {
  "$BIN/redis-cli" -p "$PORT" shutdown nosave >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

"$BIN/redis-server" --port "$PORT" --bind 127.0.0.1 --dir "$TMP" --save "" --appendonly no \
  --daemonize yes --pidfile "$TMP/redis.pid" --logfile "$TMP/redis.log"

reply=""
for _ in $(seq 1 50); do
  reply="$("$BIN/redis-cli" -p "$PORT" ping 2>/dev/null || true)"
  [ "$reply" = "PONG" ] && break
  sleep 0.2
done
if [ "$reply" != "PONG" ]; then
  cat "$TMP/redis.log" >&2 || true
  fail "redis-cli ping no responde PONG (respuesta: ${reply:-ninguna})"
fi

"$BIN/redis-cli" -p "$PORT" set elephant stack >/dev/null
[ "$("$BIN/redis-cli" -p "$PORT" get elephant)" = "stack" ] || fail "SET/GET no funciona"
"$BIN/redis-benchmark" -p "$PORT" -q -n 1000 -t ping >/dev/null || fail "redis-benchmark falla"

echo "OK: Redis $VERSION ($(uname -s) $(uname -m))"
