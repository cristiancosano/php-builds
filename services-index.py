#!/usr/bin/env python3
"""Genera services.json: el último parche de cada rama soportada de MySQL,
PostgreSQL, Mailpit, Redis, phpMyAdmin y pgAdmin, con su URL, sha256 y tamaño.

Uso:
    ./services-index.py [--previous services.json] [--no-hash] [-o services.json]

--previous  índice anterior. Si una entrada de MySQL o pgAdmin tiene la misma
            URL, se reutiliza su sha256 y tamaño en vez de descargar el
            archivo otra vez.
--no-hash   no descarga MySQL ni pgAdmin: toma el tamaño de la cabecera y pone
            un sha256 ficticio (ceros). Solo para probar en local; el CI no lo
            usa.

Las consultas a la API de GitHub usan GH_TOKEN o GITHUB_TOKEN si existen.
Sale con error si alguna fuente falla o no encuentra nada, para no publicar un
índice incompleto.
"""

import argparse
import hashlib
import html
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

FAKE_SHA256 = "0" * 64


def log(message):
    print(message, file=sys.stderr)


def curl(url, *extra, output=None):
    """Devuelve el cuerpo de la respuesta (o lo guarda en output)."""
    cmd = ["curl", "-sS", "-f", "-L", "--retry", "3", *extra]
    if output:
        cmd += ["-o", output]
    cmd.append(url)
    result = subprocess.run(cmd, capture_output=True, text=output is None, check=False)
    if result.returncode != 0:
        stderr = result.stderr if isinstance(result.stderr, str) else result.stderr.decode()
        raise RuntimeError(f"curl {url}: {stderr.strip()}")
    return result.stdout


def github(path):
    """GET a la API de GitHub, siguiendo la paginación si es una lista."""
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    headers = ["-H", "Accept: application/vnd.github+json"]
    if token:
        headers += ["-H", f"Authorization: Bearer {token}"]
    url = f"https://api.github.com/{path}"
    if "?" not in path:
        url += "?per_page=100"
    items = []
    page = 1
    while True:
        data = json.loads(curl(f"{url}&page={page}", *headers))
        if not isinstance(data, list):
            return data
        items += data
        if len(data) < 100:
            return items
        page += 1


def version_key(version):
    return tuple(int(part) for part in version.split("."))


def entry(version, branch, platform, url, sha256, size, lts, **extra):
    if not re.fullmatch(r"[0-9a-f]{64}", sha256):
        raise RuntimeError(f"sha256 no válido para {url}: {sha256}")
    if not isinstance(size, int) or size <= 0:
        raise RuntimeError(f"tamaño no válido para {url}: {size}")
    return {
        "version": version,
        "branch": branch,
        "platform": platform,
        "url": url,
        "sha256": sha256,
        "size": size,
        "lts": lts,
        **extra,
    }


def content_length(url):
    headers = curl(url, "-I")
    lengths = re.findall(r"(?im)^content-length:\s*(\d+)", headers)
    if not lengths:
        raise RuntimeError(f"sin content-length para {url}")
    return int(lengths[-1])


def download_hash(url, previous, no_hash, md5=None):
    """sha256 y tamaño de url, descargándolo salvo que el índice anterior ya
    tenga esa URL. Si se da md5, comprueba que coincide."""
    cached = previous.get(url)
    if cached and cached["sha256"] != FAKE_SHA256:
        return cached["sha256"], cached["size"]
    if no_hash:
        return FAKE_SHA256, content_length(url)
    log(f"  descargando {url}")
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "file")
        curl(url, output=path)
        sha256, md5sum, size = hashlib.sha256(), hashlib.md5(), 0
        with open(path, "rb") as handle:
            for chunk in iter(lambda: handle.read(1 << 20), b""):
                sha256.update(chunk)
                md5sum.update(chunk)
                size += len(chunk)
    if md5 and md5sum.hexdigest() != md5:
        raise RuntimeError(f"el MD5 de {url} no coincide con el publicado")
    return sha256.hexdigest(), size


def github_digest(asset):
    digest = asset.get("digest") or ""
    if not digest.startswith("sha256:"):
        raise RuntimeError(f"{asset['name']} no tiene digest sha256")
    return digest.removeprefix("sha256:")


# ---------------------------------------------------------------- MySQL

MYSQL_DOWNLOADS = "https://dev.mysql.com/downloads/mysql/"
# Sistemas de la página de descargas: 33 macOS, 2 Linux genérico, 3 Windows.
MYSQL_OS = {"macos-arm64": 33, "linux-x86_64": 2, "linux-arm64": 2, "windows-x64": 3}
# Nombre del archivo por plataforma. El grupo "rank" ordena las variantes
# (versión de macOS o de glibc): se elige la más alta y, en Linux, la variante
# -minimal si existe (unos 80 MB frente a 1 GB; sin tests ni símbolos).
MYSQL_FILES = {
    "macos-arm64": r"mysql-{v}-macos(?P<rank>\d+(?:\.\d+)?)-arm64\.tar\.gz",
    "linux-x86_64": r"mysql-{v}-linux-glibc(?P<rank>\d+\.\d+)-x86_64(?P<minimal>-minimal)?\.tar\.xz",
    "linux-arm64": r"mysql-{v}-linux-glibc(?P<rank>\d+\.\d+)-aarch64(?P<minimal>-minimal)?\.tar\.xz",
    "windows-x64": r"mysql-{v}-winx64(?P<rank>)\.zip",
}


def mysql_branches():
    """Ramas del selector de versión de la página de descargas.

    Cada opción es <option value="8.4">8.4.13 LTS</option>; la página solo
    ofrece las ramas que Oracle mantiene.
    """
    page = curl(MYSQL_DOWNLOADS)
    select = re.search(r'<select name="version".*?</select>', page, re.S)
    if not select:
        raise RuntimeError("MySQL: no se encuentra el selector de versión")
    branches = []
    for value, label in re.findall(r'<option value="([^"]*)"[^>]*>([^<]*)</option>', select.group(0)):
        label = html.unescape(label).strip()
        match = re.fullmatch(r"(\d+\.\d+\.\d+)(.*)", label)
        if not re.fullmatch(r"\d+\.\d+", value) or not match or not match.group(1).startswith(value + "."):
            raise RuntimeError(f"MySQL: opción inesperada en el selector: {value!r} {label!r}")
        branches.append({"branch": value, "version": match.group(1), "lts": "LTS" in match.group(2)})
    if not branches:
        raise RuntimeError("MySQL: el selector de versión está vacío")
    # Las LTS y solo la innovation más reciente: una innovation queda sin
    # soporte al salir la siguiente, y lo que no es LTS ni la última (8.0 tras
    # su fin de vida) no se ofrece.
    innovation = [b for b in branches if not b["lts"]]
    newest = max(innovation, key=lambda b: version_key(b["version"]), default=None)
    return [b for b in branches if b["lts"] or b is newest]


def mysql_files(branch, os_id):
    """Archivos de una rama y sistema: {nombre: md5}."""
    page = curl(f"{MYSQL_DOWNLOADS}?tpl=platform&os={os_id}&version={branch}")
    files = re.findall(r"\((mysql-[^)\s]+)\)\s*</td>\s*<td[^>]*>\s*MD5:\s*<code[^>]*>([0-9a-f]{32})</code>", page)
    return dict(files)


def mysql(previous, no_hash):
    cache = {item["url"]: item for item in previous.get("mysql", [])}
    entries = []
    for info in mysql_branches():
        branch, version = info["branch"], info["version"]
        pages = {}
        for platform, os_id in MYSQL_OS.items():
            if os_id not in pages:
                pages[os_id] = mysql_files(branch, os_id)
            pattern = re.compile(MYSQL_FILES[platform].format(v=re.escape(version)))
            candidates = [(m, md5) for name, md5 in pages[os_id].items() if (m := pattern.fullmatch(name))]
            if not candidates:
                log(f"  aviso: MySQL {version} no tiene paquete para {platform}")
                continue
            match, md5 = max(
                candidates,
                key=lambda c: (version_key(c[0].group("rank") or "0"), bool(c[0].groupdict().get("minimal"))),
            )
            url = f"https://dev.mysql.com/get/Downloads/MySQL-{branch}/{match.group(0)}"
            sha256, size = download_hash(url, cache, no_hash, md5=md5)
            entries.append(entry(version, branch, platform, url, sha256, size, info["lts"]))
        log(f"MySQL {version}{' LTS' if info['lts'] else ''}")
    if not any(e["platform"] == "macos-arm64" for e in entries):
        raise RuntimeError("MySQL: no se ha encontrado ningún paquete para macos-arm64")
    return entries


# ----------------------------------------------------------- PostgreSQL

POSTGRESQL_TARGETS = {
    "macos-arm64": "aarch64-apple-darwin",
    "linux-x86_64": "x86_64-unknown-linux-gnu",
    "linux-arm64": "aarch64-unknown-linux-gnu",
    "windows-x64": "x86_64-pc-windows-msvc",
}


def postgresql():
    versions = json.loads(curl("https://www.postgresql.org/versions.json"))
    majors = sorted({str(v["major"]) for v in versions if v.get("supported")}, key=int)
    if not majors:
        raise RuntimeError("PostgreSQL: versions.json no tiene ramas soportadas")
    releases = [
        r for r in github("repos/theseus-rs/postgresql-binaries/releases")
        if not r["draft"] and not r["prerelease"] and re.fullmatch(r"\d+\.\d+\.\d+", r["tag_name"])
    ]
    entries = []
    for major in majors:
        candidates = [r for r in releases if r["tag_name"].split(".")[0] == major]
        if not candidates:
            log(f"  aviso: theseus no tiene binarios de PostgreSQL {major}")
            continue
        release = max(candidates, key=lambda r: version_key(r["tag_name"]))
        version = release["tag_name"]
        assets = {a["name"]: a for a in release["assets"]}
        for platform, target in POSTGRESQL_TARGETS.items():
            asset = assets.get(f"postgresql-{version}-{target}.tar.gz")
            if not asset:
                log(f"  aviso: PostgreSQL {version} no tiene paquete para {platform}")
                continue
            entries.append(entry(version, major, platform, asset["browser_download_url"],
                                 github_digest(asset), asset["size"], True))
        log(f"PostgreSQL {version}")
    if not any(e["platform"] == "macos-arm64" for e in entries):
        raise RuntimeError("PostgreSQL: no se ha encontrado ningún paquete para macos-arm64")
    return entries


# -------------------------------------------------------------- Mailpit

MAILPIT_ASSETS = {
    "macos-arm64": "mailpit-darwin-arm64.tar.gz",
    "linux-x86_64": "mailpit-linux-amd64.tar.gz",
    "linux-arm64": "mailpit-linux-arm64.tar.gz",
    "windows-x64": "mailpit-windows-amd64.zip",
}


def mailpit():
    release = github("repos/axllent/mailpit/releases/latest")
    version = release["tag_name"].removeprefix("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise RuntimeError(f"Mailpit: tag inesperado {release['tag_name']}")
    assets = {a["name"]: a for a in release["assets"]}
    entries = []
    for platform, name in MAILPIT_ASSETS.items():
        asset = assets.get(name)
        if not asset:
            log(f"  aviso: Mailpit {version} no tiene {name}")
            continue
        entries.append(entry(version, version.split(".")[0], platform, asset["browser_download_url"],
                             github_digest(asset), asset["size"], False))
    log(f"Mailpit {version}")
    if not entries:
        raise RuntimeError("Mailpit: la última release no tiene paquetes")
    return entries


# ---------------------------------------------------------------- Redis

# Lo compila redis.yml en este repositorio y lo publica en releases redis-<v>.
REDIS_REPO = "cristiancosano/php-builds"
REDIS_PLATFORMS = ("macos-arm64", "linux-x86_64", "linux-arm64")
REDIS_SECURITY = "https://raw.githubusercontent.com/redis/redis/HEAD/SECURITY.md"


def redis():
    """Por cada rama 8.x soportada y plataforma, la versión más reciente que
    hayamos publicado. Si un parche nuevo aún no ha compilado en una
    plataforma, esa plataforma se queda en el anterior."""
    security = curl(REDIS_SECURITY)
    branches = [
        f"{major}.{minor}"
        for major, minor in re.findall(r"(?m)^\|\s*(\d+)\.(\d+)\.x\s*\|\s*:white_check_mark:", security)
        if int(major) >= 8
    ]
    if not branches:
        raise RuntimeError("Redis: SECURITY.md no tiene ramas 8.x soportadas")
    releases = [
        r for r in github(f"repos/{REDIS_REPO}/releases")
        if not r["draft"] and re.fullmatch(r"redis-\d+\.\d+\.\d+", r["tag_name"])
    ]
    entries = []
    for branch in sorted(branches, key=version_key):
        candidates = sorted(
            (r for r in releases if r["tag_name"].removeprefix("redis-").startswith(branch + ".")),
            key=lambda r: version_key(r["tag_name"].removeprefix("redis-")),
            reverse=True,
        )
        versions = set()
        for platform in REDIS_PLATFORMS:
            for release in candidates:
                version = release["tag_name"].removeprefix("redis-")
                asset = next((a for a in release["assets"] if a["name"] == f"redis-{version}-{platform}.tar.gz"), None)
                if asset:
                    entries.append(entry(version, branch, platform, asset["browser_download_url"],
                                         github_digest(asset), asset["size"], False))
                    versions.add(version)
                    break
            else:
                log(f"  aviso: no hay Redis {branch} para {platform}")
        if versions:
            log(f"Redis {', '.join(sorted(versions, key=version_key))}")
    if not any(e["platform"] == "macos-arm64" for e in entries):
        raise RuntimeError("Redis: no se ha encontrado ningún paquete para macos-arm64")
    return entries


# ----------------------------------------------------------- phpMyAdmin


def phpmyadmin():
    """Solo la última versión estable (version.json la pone la primera)."""
    info = json.loads(curl("https://www.phpmyadmin.net/home_page/version.json"))
    version = info.get("version", "")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise RuntimeError(f"phpMyAdmin: versión inesperada en version.json: {version!r}")
    release = next((r for r in info.get("releases", []) if r.get("version") == version), None)
    if not release or not release.get("php_versions"):
        raise RuntimeError(f"phpMyAdmin: version.json no tiene php_versions para {version}")
    url = f"https://files.phpmyadmin.net/phpMyAdmin/{version}/phpMyAdmin-{version}-all-languages.zip"
    checksum = curl(f"{url}.sha256").split()
    if not checksum or not re.fullmatch(r"[0-9a-f]{64}", checksum[0]):
        raise RuntimeError(f"phpMyAdmin: {url}.sha256 no tiene un sha256 válido")
    log(f"phpMyAdmin {version}")
    return [entry(version, ".".join(version.split(".")[:2]), "any", url, checksum[0],
                  content_length(url), False, php=release["php_versions"])]


# -------------------------------------------------------------- pgAdmin


def pgadmin(previous, no_hash):
    """Solo macOS arm64. pgAdmin no publica checksums: se calcula descargando
    el .dmg, salvo que el índice anterior ya tenga esa URL."""
    cache = {item["url"]: item for item in previous.get("pgadmin", [])}
    info = json.loads(curl("https://www.pgadmin.org/versions.json"))
    version = (info.get("pgadmin4") or {}).get("version", "")
    if not re.fullmatch(r"\d+\.\d+", version):
        raise RuntimeError(f"pgAdmin: versión inesperada en versions.json: {version!r}")
    url = f"https://ftp.postgresql.org/pub/pgadmin/pgadmin4/v{version}/macos/pgadmin4-{version}-arm64.dmg"
    sha256, size = download_hash(url, cache, no_hash)
    log(f"pgAdmin {version}")
    return [entry(version, version.split(".")[0], "macos-arm64", url, sha256, size, False)]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--previous", help="services.json anterior, para reutilizar los sha256 de MySQL y pgAdmin")
    parser.add_argument("--no-hash", action="store_true", help="no descargar MySQL ni pgAdmin (sha256 ficticio)")
    parser.add_argument("-o", "--output", default="services.json")
    args = parser.parse_args()

    previous = {}
    if args.previous and os.path.exists(args.previous):
        with open(args.previous) as handle:
            previous = json.load(handle).get("components", {})

    index = {
        "schema": 1,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "components": {
            "mysql": mysql(previous, args.no_hash),
            "postgresql": postgresql(),
            "mailpit": mailpit(),
            "redis": redis(),
            "phpmyadmin": phpmyadmin(),
            "pgadmin": pgadmin(previous, args.no_hash),
        },
    }
    with open(args.output, "w") as handle:
        json.dump(index, handle, indent=2)
        handle.write("\n")
    log(f"Escrito {args.output}")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as error:
        log(f"error: {error}")
        sys.exit(1)
