#!/usr/bin/env bash
set -euo pipefail

# === Inställningar ===
WIN_EXPORT_DIR="C:\\Users\\Public\\wsl-root-certs"
WSL_EXPORT_DIR="/mnt/c/Users/Public/wsl-root-certs"
WSL_STAGE_DIR="/tmp/wsl-win-certs"
WSL_TARGET_DIR_DEB="/usr/local/share/ca-certificates/windows"
WSL_TARGET_DIR_RPM="/etc/pki/ca-trust/source/anchors"

echo "==> Kollar miljö…"
if [[ ! -d /mnt/c/Windows/System32 ]]; then
  echo "Det här verkar inte vara WSL (saknar /mnt/c). Avbryter." >&2
  exit 1
fi

# Kräver sudo för att lägga cert i systemets CA-butik
if [[ $EUID -ne 0 ]]; then
  echo "Kör med sudo: sudo $0" >&2
  exit 1
fi

# Hämta distro-info
source /etc/os-release || true
ID_LIKE="${ID_LIKE:-}"
ID="${ID:-}"

echo "==> Säkerställer att nödvändiga paket finns…"
case "$ID$ID_LIKE" in
  *debian*|*ubuntu*)
    apt-get update -y
    apt-get install -y ca-certificates openssl
    ;;
  *alpine*)
    apk add --no-cache ca-certificates openssl
    update-ca-certificates || true
    ;;
  *fedora*|*rhel*|*centos*)
    dnf install -y ca-certificates openssl || yum install -y ca-certificates openssl
    update-ca-trust force-enable || true
    ;;
  *)
    echo "Varnar: Okänd distro ($ID / $ID_LIKE). Försöker ändå med ca-certificates + openssl…" >&2
    ;;
esac

echo "==> Exporterar Windows rotcertifikat via PowerShell…"
# Exportera alla cert från Windows LocalMachine\Root till en katalog
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
  \$ErrorActionPreference = 'Stop';
  \$dest = '$WIN_EXPORT_DIR';
  if (-not (Test-Path \$dest)) { New-Item -ItemType Directory -Force -Path \$dest | Out-Null }
  # Töm mappen först
  Get-ChildItem -Path \$dest -Filter *.cer -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

  \$store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root','LocalMachine');
  \$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly);

  \$i = 0
  foreach (\$c in \$store.Certificates) {
    # Exportera i DER (.cer)
    \$bytes = \$c.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    \$name = ('{0:D4}-{1}.cer' -f \$i, \$c.Thumbprint)
    [System.IO.File]::WriteAllBytes((Join-Path \$dest \$name), \$bytes)
    \$i++
  }
  \$store.Close();
" | sed 's/\r$//'

if [[ ! -d "$WSL_EXPORT_DIR" ]]; then
  echo "Kunde inte hitta exporterad mapp på $WSL_EXPORT_DIR. Avbryter." >&2
  exit 1
fi

echo "==> Förbereder staging-katalog…"
rm -rf "$WSL_STAGE_DIR"
mkdir -p "$WSL_STAGE_DIR"

echo "==> Kopierar certifikat från Windows till WSL staging…"
cp -f "$WSL_EXPORT_DIR"/*.cer "$WSL_STAGE_DIR"/ 2>/dev/null || true

COUNT=$(ls -1 "$WSL_STAGE_DIR"/*.cer 2>/dev/null | wc -l || echo 0)
if [[ "$COUNT" -eq 0 ]]; then
  echo "Inga .cer-filer hittades i $WSL_EXPORT_DIR. Avbryter." >&2
  exit 1
fi
echo "   Hittade $COUNT certifikat."

echo "==> Konverterar .cer (DER) till .crt (PEM) för Linux…"
CONV_DIR="$WSL_STAGE_DIR/converted"
mkdir -p "$CONV_DIR"

shopt -s nullglob
for CER in "$WSL_STAGE_DIR"/*.cer; do
  CRT="$CONV_DIR/$(basename "${CER%.*}").crt"
  # Försök läsa som DER; om det misslyckas, prova PEM -> PEM
  if openssl x509 -inform DER -in "$CER" -out "$CRT" >/dev/null 2>&1; then
    :
  elif openssl x509 -in "$CER" -out "$CRT" >/dev/null 2>&1; then
    :
  else
    echo "Varnar: Kunde inte konvertera $CER, hoppar över." >&2
    continue
  fi
done

CONV_COUNT=$(ls -1 "$CONV_DIR"/*.crt 2>/dev/null | wc -l || echo 0)
if [[ "$CONV_COUNT" -eq 0 ]]; then
  echo "Inga cert gick att konvertera. Avbryter." >&2
  exit 1
fi
echo "   Konverterade $CONV_COUNT certifikat."

echo "==> Installerar cert i systemets CA-butik…"
if [[ "$ID$ID_LIKE" == *debian* || "$ID$ID_LIKE" == *ubuntu* || "$ID$ID_LIKE" == *alpine* ]]; then
  mkdir -p "$WSL_TARGET_DIR_DEB"
  cp -f "$CONV_DIR"/*.crt "$WSL_TARGET_DIR_DEB"/
  update-ca-certificates
elif [[ "$ID$ID_LIKE" == *fedora* || "$ID$ID_LIKE" == *rhel* || "$ID$ID_LIKE" == *centos* ]]; then
  mkdir -p "$WSL_TARGET_DIR_RPM"
  cp -f "$CONV_DIR"/*.crt "$WSL_TARGET_DIR_RPM"/
  update-ca-trust extract
else
  # Försök Debian/Ubuntu-väg som default
  mkdir -p "$WSL_TARGET_DIR_DEB"
  cp -f "$CONV_DIR"/*.crt "$WSL_TARGET_DIR_DEB"/
  if command -v update-ca-certificates >/dev/null 2>&1; then
    update-ca-certificates
  elif command -v update-ca-trust >/dev/null 2>&1; then
    update-ca-trust extract
  else
    echo "Varnar: Hittar inget uppdateringskommando för CA-butiken. Installationen kan vara ofullständig." >&2
  fi
fi

echo "==> Klart! Dina WSL-processer använder nu Windows’ rotcertifikat."
echo
echo "Tips:"
echo " - Om du kör Docker _inne_ i WSL (docker-ce), kör: sudo service docker restart || sudo systemctl restart docker"
echo " - Om du använder Docker Desktop (Windows-daemon), certfixen påverkar främst verktyg som 'curl', 'git', 'apt', etc. i WSL."