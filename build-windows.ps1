# Compila php.exe estático para Windows x64 con static-php-cli.
# PHP-FPM no existe en Windows, así que solo genera el CLI.
#
# Uso: ./build-windows.ps1 -Version 8.4.27
param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$SpcVersion = '2.8.5'
$SpcSha256 = '425b54ab857e21409c1fd9b818899ffebabd1e2817ef0a0ed5ae8a3d9f5b463b'
$SpcUrl = "https://github.com/crazywhalecc/static-php-cli/releases/download/$SpcVersion/spc-windows-x64.exe"
$WithLibs = 'freetype,libjpeg,libwebp,nghttp2'

function Read-List([string]$Path) {
    Get-Content $Path | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
}

$Excluded = Read-List (Join-Path $PSScriptRoot 'exclude-windows.txt')
$Extensions = (Read-List (Join-Path $PSScriptRoot 'extensions.txt') |
    Where-Object { $Excluded -notcontains $_ }) -join ','

$SpcDir = Join-Path $PSScriptRoot ".work\spc-$SpcVersion"
$Spc = Join-Path $SpcDir 'spc.exe'
if (-not (Test-Path $Spc)) {
    New-Item -ItemType Directory -Force -Path $SpcDir | Out-Null
    Invoke-WebRequest -Uri $SpcUrl -OutFile $Spc
    $Actual = (Get-FileHash -Algorithm SHA256 $Spc).Hash.ToLowerInvariant()
    if ($Actual -ne $SpcSha256) {
        Remove-Item $Spc
        throw "SHA-256 de spc.exe incorrecto: $Actual"
    }
}

# spc usa el directorio actual para downloads/, source/, buildroot/ y log/.
$Work = Join-Path $PSScriptRoot ".work\php-$Version"
$Dist = Join-Path $PSScriptRoot "dist\$Version"
New-Item -ItemType Directory -Force -Path $Work, $Dist | Out-Null
Set-Location $Work

# En Windows, doctor instala el PHP SDK y nasm dentro de esta carpeta de trabajo.
& $Spc doctor --auto-fix
& $Spc download --with-php=$Version --for-extensions=$Extensions --retry=3
& $Spc build $Extensions --with-libs=$WithLibs --build-cli

Copy-Item -Force 'buildroot\bin\php.exe' $Dist
$License = Join-Path $Dist 'license'
if (Test-Path $License) { Remove-Item -Recurse -Force $License }
Copy-Item -Recurse 'buildroot\license' $License
