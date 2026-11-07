# php-builds

PHP estático para macOS, Linux y Windows, compilado con [static-php-cli](https://github.com/crazywhalecc/static-php-cli) y publicado en [Releases](../../releases). Son la fuente de versiones de PHP de Elephant Stack, una app para gestionar el entorno de desarrollo local sin Docker ni máquinas virtuales. También compila [Redis](#redis), que no publica binarios, y genera un [índice de servicios](#índice-de-servicios).

Proyecto personal, sin relación con PHP, static-php-cli, Redis ni Laravel Herd.

## Plataformas

| Paquete | `php` | `php-fpm` | Xdebug | Extensiones que no incluye |
|---|---|---|---|---|
| `macos-arm64` | ✅ | ✅ | ✅ `xdebug.so` | — |
| `linux-x86_64`, `linux-arm64` | ✅ | ✅ | ❌ | `ffi` |
| `windows-x64` | ✅ `php.exe` | ❌ | ❌ | `gettext`, `gmp`, `imagick`, `pcntl`, `posix`, `readline`, `sysvmsg`, `sysvsem`, `xsl`, `zstd` |

- **Linux:** usa musl y es totalmente estático, así que funciona en cualquier distribución, pero no puede cargar librerías dinámicas. Por eso no incluye Xdebug ni `ffi`.
- **Windows:** PHP-FPM no existe en Windows. static-php-cli no soporta todavía parte de la lista, y otras extensiones no existen en ese sistema.

La lista común está en [`extensions.txt`](extensions.txt), y las exclusiones en `exclude-linux.txt` y `exclude-windows.txt`. En todas las plataformas faltan también:

- `sqlsrv`, `pdo_sqlsrv`, `mongodb` y `ldap`, por decisión propia, para simplificar la compilación.
- `imap`: PHP 8.4 la sacó del núcleo y static-php-cli 2.8.5 falla al buscarla en `php-src`.

Xdebug es la versión que descarga static-php-cli y puede ser una alfa.

## Uso

Cada paquete incluye los binarios y la carpeta `license/`, y se publica junto a un `.sha256`.

```sh
tar -xzf php-8.4.27-macos-arm64.tar.gz
./php -v
```

Para comprobar que un paquete salió de este repositorio:

```sh
gh attestation verify php-8.4.27-macos-arm64.tar.gz --repo cristiancosano/php-builds
```

## Publicación automática

[`.github/workflows/build.yml`](.github/workflows/build.yml) consulta php.net cada día y compila, a partir de PHP 8.3, cada combinación de versión y plataforma que aún no esté publicada. Si una plataforma falla, las demás se publican igual y esa se reintenta al día siguiente. Solo se publica lo que pasa las comprobaciones de [`smoke-test.php`](smoke-test.php).

También se puede lanzar a mano con versiones y plataformas concretas.

## Redis

Redis solo publica el código fuente, así que [`.github/workflows/redis.yml`](.github/workflows/redis.yml) lo compila con [`build-redis.sh`](build-redis.sh). Cada día toma las ramas 8.x que la [política de seguridad de Redis](https://github.com/redis/redis/blob/HEAD/SECURITY.md) marca como soportadas, busca el último parche de cada una en las [releases de redis/redis](https://github.com/redis/redis/releases) y compila lo que falte. Cada versión se publica en una release `redis-<versión>` (`redis-8.2.11`…), con un paquete por plataforma y su `.sha256`:

| Paquete | Cómo se compila |
|---|---|
| `redis-<versión>-macos-arm64.tar.gz` | Con las Command Line Tools. Solo depende de `libSystem` |
| `redis-<versión>-linux-x86_64.tar.gz`, `redis-<versión>-linux-arm64.tar.gz` | En Alpine, estático con musl: funciona en cualquier distribución. jemalloc admite páginas de hasta 64 KB en arm64 |

No hay paquete para Windows: Redis no lo soporta.

```
redis-8.2.11/
  bin/redis-server, redis-cli, redis-benchmark
  bin/redis-sentinel, redis-check-aof, redis-check-rdb   (enlaces a redis-server)
  LICENSE.txt, REDISCONTRIBUTIONS.txt, 00-RELEASENOTES, redis.conf, sentinel.conf
```

- **Fuente:** el `.tar.gz` oficial de `download.redis.io`, comprobado con el sha256 de [redis/redis-hashes](https://github.com/redis/redis-hashes). Se compila sin cambios en el código, sin TLS (`BUILD_TLS=no`) y sin los módulos de Redis Open Source (RediSearch, RedisJSON…), que necesitan Rust y otras herramientas. En Redis 8.2 a 8.6, `fast_float` se compila con `-fno-exceptions` para no depender de libc++ en macOS.
- **Licencia:** desde Redis 8, se distribuye bajo RSALv2, SSPLv1 o AGPLv3, a elegir. Estos binarios se redistribuyen bajo la AGPLv3. Redis 7.x solo tiene RSALv2/SSPLv1, que no dejan claro si podemos redistribuir binarios, así que no se compila.
- **Comprobación:** [`smoke-test-redis.sh`](smoke-test-redis.sh) comprueba la versión, las dependencias (solo `libSystem` en macOS, estático en Linux) y que `redis-server` arranca y responde `PONG` a `redis-cli ping`.

```sh
./build-redis.sh 8.2.11            # en Linux necesita Docker
./smoke-test-redis.sh dist/redis-8.2.11 8.2.11
```

## Índice de servicios

[`.github/workflows/services.yml`](.github/workflows/services.yml) publica cada día `services.json` en la release [`catalog`](../../releases/tag/catalog), junto a `index.json`. Lo genera [`services-index.py`](services-index.py) y no depende de la compilación de PHP. Contiene el último parche de cada rama soportada de MySQL, PostgreSQL, Mailpit y Redis, y la última versión de phpMyAdmin y pgAdmin:

```json
{
  "schema": 1,
  "generated_at": "2026-11-06T12:00:00Z",
  "components": {
    "mysql": [
      {"version": "8.4.13", "branch": "8.4", "platform": "macos-arm64",
       "url": "https://dev.mysql.com/get/Downloads/MySQL-8.4/mysql-8.4.13-macos15-arm64.tar.gz",
       "sha256": "f324f895…", "size": 165362783, "lts": true}
    ],
    "postgresql": ["…"],
    "mailpit": ["…"],
    "redis": ["…"],
    "phpmyadmin": [
      {"version": "5.2.3", "branch": "5.2", "platform": "any",
       "url": "https://files.phpmyadmin.net/phpMyAdmin/5.2.3/phpMyAdmin-5.2.3-all-languages.zip",
       "sha256": "2d2e13c7…", "size": 16431330, "lts": false, "php": ">=7.2,<8.4"}
    ],
    "pgadmin": ["…"]
  }
}
```

Hay una entrada por versión y plataforma (`macos-arm64`, `linux-x86_64`, `linux-arm64`, `windows-x64`, o `any` si el paquete no depende de la plataforma). Algunos componentes añaden campos propios, como `php` en phpMyAdmin; los clientes deben ignorar los que no conozcan. Las URL son las de cada proyecto; este repositorio solo redistribuye Redis.

| Componente | Ramas | Binarios | sha256 |
|---|---|---|---|
| MySQL | Selector de versión de [dev.mysql.com/downloads/mysql](https://dev.mysql.com/downloads/mysql/); `lts` según su etiqueta | Oficiales | Calculado descargando el archivo y comprobando el MD5 de la página. Se reutiliza el del índice anterior si la URL no cambia |
| PostgreSQL | `supported` en [versions.json](https://www.postgresql.org/versions.json); `lts` siempre `true` | [theseus-rs/postgresql-binaries](https://github.com/theseus-rs/postgresql-binaries) | `digest` del asset en GitHub |
| Mailpit | Última release; `lts` siempre `false` | [axllent/mailpit](https://github.com/axllent/mailpit) | `digest` del asset en GitHub |
| Redis | Ramas 8.x soportadas según su [SECURITY.md](https://github.com/redis/redis/blob/HEAD/SECURITY.md); por rama y plataforma, la versión más reciente publicada aquí. `lts` siempre `false` | Releases `redis-<versión>` de este repositorio (sin Windows) | `digest` del asset en GitHub |
| phpMyAdmin | Solo la última estable de [version.json](https://www.phpmyadmin.net/home_page/version.json); `php` es su `php_versions`, `lts` siempre `false` | Oficial, `all-languages.zip`, plataforma `any` | El `.sha256` oficial junto al archivo |
| pgAdmin | Solo la última de [versions.json](https://www.pgadmin.org/versions.json) (`pgadmin4`); la rama es la versión mayor, `lts` siempre `false` | Oficial, solo el `.dmg` de `macos-arm64` | No hay checksum oficial: calculado descargando el archivo. Se reutiliza el del índice anterior si la URL no cambia |

Si una fuente falla, no se publica nada y se mantiene el índice anterior. Eso incluye Redis: si aún no hay ninguna release `redis-*` para `macos-arm64`, el índice falla, así que `redis.yml` tiene que haber publicado al menos una vez. Para probarlo en local sin descargar MySQL ni pgAdmin (pone un sha256 de ceros, que el workflow rechaza):

```sh
GH_TOKEN="$(gh auth token)" ./services-index.py --no-hash -o services.json
```

## Compilar en local

```sh
# macOS
brew install autoconf automake bison cmake libtool pkgconf re2c
BUILD_XDEBUG=1 ./build.sh 8.4
./smoke-test.sh dist/8.4.27 8.4.27

# Linux (necesita git y Docker)
./build-linux.sh 8.4.27
./smoke-test.sh dist/8.4.27 8.4.27

# Windows (PowerShell)
./build-windows.ps1 -Version 8.4.27
dist\8.4.27\php.exe -n smoke-test.php 8.4.27 windows
```

En un M3 Pro, la primera compilación tarda unos 17 minutos y `.work/` ocupa 6 GB.

En macOS, `build.sh` usa las Command Line Tools en vez del Xcode activo, porque un Xcode más antiguo que el SDK no puede enlazar. Solo afecta a ese proceso y respeta un `DEVELOPER_DIR` ya definido.

## Licencias

Los scripts de este repositorio están bajo licencia [MIT](LICENSE). Los binarios incluyen software con sus propias licencias, recogidas en `license/` dentro de cada paquete de PHP y en `LICENSE.txt` en los de Redis (que se redistribuye bajo la AGPLv3).

## Fuentes fijadas

static-php-cli 2.8.5 descarga algunas librerías de ramas que cambian solas. `libaom` se fija en la v3.14.1, porque desde la v3.15.0 deja de aplicar su parche para Linux. `libjxl` y la extensión `zstd` siguen saliendo de sus ramas principales, así que una compilación puede romperse sin cambios en este repositorio.
