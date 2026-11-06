# php-builds

PHP estático para macOS, Linux y Windows, compilado con [static-php-cli](https://github.com/crazywhalecc/static-php-cli) y publicado en [Releases](../../releases). Son la fuente de versiones de PHP de Elephant Stack, una app para gestionar el entorno de desarrollo local sin Docker ni máquinas virtuales.

Proyecto personal, sin relación con PHP, static-php-cli ni Laravel Herd.

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

## Índice de servicios

[`.github/workflows/services.yml`](.github/workflows/services.yml) publica cada día `services.json` en la release [`catalog`](../../releases/tag/catalog), junto a `index.json`. Lo genera [`services-index.py`](services-index.py) y no depende de la compilación de PHP. Contiene el último parche de cada rama soportada de MySQL, PostgreSQL y Mailpit:

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
    "mailpit": ["…"]
  }
}
```

Hay una entrada por versión y plataforma (`macos-arm64`, `linux-x86_64`, `linux-arm64`, `windows-x64`). Las URL son las de cada proyecto; este repositorio no redistribuye esos binarios.

| Componente | Ramas | Binarios | sha256 |
|---|---|---|---|
| MySQL | Selector de versión de [dev.mysql.com/downloads/mysql](https://dev.mysql.com/downloads/mysql/); `lts` según su etiqueta | Oficiales | Calculado descargando el archivo y comprobando el MD5 de la página. Se reutiliza el del índice anterior si la URL no cambia |
| PostgreSQL | `supported` en [versions.json](https://www.postgresql.org/versions.json); `lts` siempre `true` | [theseus-rs/postgresql-binaries](https://github.com/theseus-rs/postgresql-binaries) | `digest` del asset en GitHub |
| Mailpit | Última release; `lts` siempre `false` | [axllent/mailpit](https://github.com/axllent/mailpit) | `digest` del asset en GitHub |

Si una fuente falla, no se publica nada y se mantiene el índice anterior. Para probarlo en local sin descargar MySQL (pone un sha256 de ceros, que el workflow rechaza):

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

Los scripts de este repositorio están bajo licencia [MIT](LICENSE). Los binarios incluyen software con sus propias licencias, recogidas en `license/` dentro de cada paquete.

## Fuentes fijadas

static-php-cli 2.8.5 descarga algunas librerías de ramas que cambian solas. `libaom` se fija en la v3.14.1, porque desde la v3.15.0 deja de aplicar su parche para Linux. `libjxl` y la extensión `zstd` siguen saliendo de sus ramas principales, así que una compilación puede romperse sin cambios en este repositorio.
