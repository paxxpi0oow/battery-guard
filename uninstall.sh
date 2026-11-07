#!/data/data/com.termux/files/usr/bin/bash
set -e
battery-guard stop 2>/dev/null || true
rm -f "$PREFIX/bin/battery-guard"
echo "[+] Removed battery-guard"
echo "    Logs kept in ~/.battery-guard (rm -rf ~/.battery-guard to delete)"
