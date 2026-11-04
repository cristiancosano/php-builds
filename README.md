# php-builds

PHP estático para macOS arm64, compilado con [static-php-cli](https://github.com/crazywhalecc/static-php-cli) y publicado en [Releases](../../releases). Son la fuente de versiones de PHP de LocalDeck, una app para gestionar el entorno de desarrollo local sin Docker ni máquinas virtuales.

Proyecto personal, sin relación con PHP, static-php-cli ni Laravel Herd.

## Qué incluye cada versión

Cada `php-<versión>-macos-arm64.tar.gz` contiene:

- `php` y `php-fpm`, con las extensiones de [`extensions.txt`](extensions.txt) dentro del binario.
- `xdebug.so`, que se carga aparte con `zend_extension`. Xdebug es la versión que descarga static-php-cli y puede ser una alfa.
- `license/`, con las licencias de PHP y de las librerías enlazadas.
- `SHA256SUMS`.

## Uso

```sh
tar -xzf php-8.4.27-macos-arm64.tar.gz
./php -v
```

Para comprobar que el archivo salió de este repositorio:

```sh
gh attestation verify php-8.4.27-macos-arm64.tar.gz --repo cristiancosano/php-builds
```

## Publicación automática

[`.github/workflows/build.yml`](.github/workflows/build.yml) consulta php.net cada día y compila las versiones soportadas, a partir de 8.3, que aún no tengan release. Una versión solo se publica si pasa [`smoke-test.sh`](smoke-test.sh). También se puede lanzar a mano con versiones concretas.

## Compilar en local

```sh
brew install autoconf automake bison cmake libtool pkgconf re2c
BUILD_XDEBUG=1 ./build.sh 8.4
./smoke-test.sh dist/8.4.27 8.4.27
```

En un M3 Pro, la primera compilación tarda unos 17 minutos y `.work/` ocupa 6 GB.

`build.sh` usa las Command Line Tools en vez del Xcode activo, porque un Xcode más antiguo que el SDK no puede enlazar. Solo afecta a ese proceso y respeta un `DEVELOPER_DIR` ya definido.

## Extensiones excluidas

- `sqlsrv`, `pdo_sqlsrv`, `mongodb` y `ldap`, por decisión propia, para simplificar la compilación.
- `imap`: PHP 8.4 la sacó del núcleo y static-php-cli 2.8.5 falla al buscarla en `php-src`.

## Licencias

Los scripts de este repositorio están bajo licencia [MIT](LICENSE). Los binarios incluyen software con sus propias licencias, recogidas en `license/` dentro de cada paquete.
