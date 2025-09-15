#!/usr/bin/env bash
set -euo pipefail

WSL_EXPORT_DIR="/mnt/c/Users/Public/wsl-root-certs"
WSL_STAGE_DIR="/tmp/wsl-win-certs"
WSL_TARGET_DIR="/usr/local/share/ca-certificates/windows"

if [[ ! -d "$WSL_EXPORT_DIR" ]]; then
  echo "No exported certs found at $WSL_EXPORT_DIR. Did you run the PowerShell export first?" >&2
  exit 1
fi

sudo mkdir -p "$WSL_STAGE_DIR" "$WSL_TARGET_DIR"
sudo cp -f "$WSL_EXPORT_DIR"/*.cer "$WSL_STAGE_DIR"/

for CER in "$WSL_STAGE_DIR"/*.cer; do
  CRT="$WSL_STAGE_DIR/$(basename "${CER%.*}").crt"
  if openssl x509 -inform DER -in "$CER" -out "$CRT" >/dev/null 2>&1; then
    sudo cp -f "$CRT" "$WSL_TARGET_DIR"/
  fi
done

sudo update-ca-certificates

echo "==> Imported Windows root certs into WSL."