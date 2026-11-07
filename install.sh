#!/data/data/com.termux/files/usr/bin/bash
set -e
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$PREFIX/bin/battery-guard"

echo "[*] Installing battery-guard..."
command -v jq >/dev/null 2>&1 || { echo "[*] Installing jq..."; pkg install -y jq; }

if ! command -v termux-battery-status >/dev/null 2>&1; then
    echo "[!] termux-battery-status not found."
    echo "    Install Termux:API app from F-Droid + run: pkg install termux-api"
    exit 1
fi

chmod +x "$REPO_DIR/battery-guard.sh" "$REPO_DIR/uninstall.sh"
ln -sf "$REPO_DIR/battery-guard.sh" "$TARGET"
[ -f "$REPO_DIR/config.conf" ] || cp "$REPO_DIR/config.conf.example" "$REPO_DIR/config.conf"
echo "[+] Installed -> $TARGET"
echo "    Try: battery-guard status"
