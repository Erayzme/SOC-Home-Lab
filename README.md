# SOC Home Lab

Ein Home Lab zum Üben von Security Monitoring und späteren Angriffssimulationen. Ziel des Projekts: eine Windows-VM, die ihre eigenen Security-Events über Sysmon erfasst und an Splunk sendet, danach Angriffe aus einer Kali-VM gegen dieses Setup fahren und die Erkennung in Splunk nachweisen.

## Status

- [x] Teil 1: Windows VM mit Sysmon und Splunk
- [x] Teil 2: Kali VM, Netzwerk auf Bridged, erste Angriffe

## Aufbau

| Komponente | Rolle |
|---|---|
| VirtualBox (Windows-PC) | Virtualisierung der Windows-VM |
| UTM (MacBook, Apple Silicon) | Virtualisierung der Kali-VM |
| Windows 11 Enterprise (Evaluierung) | Ziel-VM, generiert Events |
| Sysmon (SwiftOnSecurity-Konfiguration) | Erfasst detaillierte Prozess-, Netzwerk- und Registry-Events |
| Splunk Universal Forwarder | Sendet Windows- und Sysmon-Logs an Splunk |
| Splunk Enterprise | Empfängt, indiziert, durchsucht die Logs |
| Kali Linux | Angreifer-VM, Nmap-Scans und Brute-Force gegen die Windows-VM |

## Teil 1: Windows VM mit Sysmon und Splunk

### Was gemacht wurde

1. VirtualBox installiert, VM angelegt (Windows 11, 4 GB RAM, 2 CPUs, 60 GB Platte)
2. Windows 11 Enterprise Evaluierung installiert, lokales Konto, keine Angriffssimulation, kein Netzwerk-Umbau
3. Sysmon installiert mit der SwiftOnSecurity-Konfiguration:
   ```
   Sysmon64.exe -accepteula -i sysmonconfig-export.xml
   ```
4. Splunk Enterprise installiert, Receiving Port 9997 aktiviert, drei Indizes angelegt: `windows_logs`, `security_logs`, `sysmon_logs`
5. Splunk Universal Forwarder installiert, Ziel `127.0.0.1:9997`
6. `inputs.conf` angelegt für die drei Log-Quellen (Security, System, Sysmon Operational)
7. Testfall: fehlgeschlagene Anmeldung provoziert, in Splunk mit `index=security_logs EventCode=4625` nachgewiesen
8. Sauberer Snapshot in VirtualBox gesichert

### Ergebnis

Alle drei Indizes empfangen laufend Daten:

- `sysmon_logs` — Prozess-, Netzwerk- und sonstige Sysmon-Events
- `security_logs` — Windows Security-Log inklusive Anmeldeversuche
- `windows_logs` — Windows System-Log

Testsuche zum Nachweis der kompletten Kette (Windows → Sysmon → Forwarder → Splunk):

```
index=security_logs EventCode=4625
```

zeigt die fehlgeschlagenen Anmeldeversuche mit Zeitstempel und Computername.

### Troubleshooting

Zwei Probleme sind während des Setups aufgetreten, beide sind gute Beispiele dafür, wie man eine Log-Pipeline systematisch debuggt statt einfach neu zu installieren.

**Problem 1: Keine Events trotz aktiver Verbindung.**
`splunk list forward-server` zeigte den Forwarder korrekt als aktiv verbunden mit `127.0.0.1:9997`, trotzdem kamen keine Sysmon-Events in Splunk an. Eingrenzung über `splunk btool inputs list --debug`: die Konfiguration selbst war korrekt geladen. Ursache war ein simpler Tippfehler in `inputs.conf`: `diasabled=false` statt `disabled=false`. Da Splunk den Parameternamen nicht erkannte, blieben die Inputs auf dem Standardwert (deaktiviert).

**Problem 2: Zugriff auf Windows Event Log verweigert.**
Nach Korrektur des Tippfehlers weiterhin keine Sysmon-Events, obwohl `index=_internal` bereits Daten vom Forwarder zeigte (das bestätigte: die TCP-Verbindung Forwarder → Splunk funktioniert grundsätzlich). Im Forwarder-Log (`splunkd.log`) fand sich:

```
WinEventLogChannel::subscribeToEvtChannel: Could not subscribe to Windows Event Log channel
'Microsoft-Windows-Sysmon/Operational': errorCode=5
```

`errorCode=5` ist Windows für Zugriff verweigert. Der `SplunkForwarder`-Dienst lief unter einem Konto ohne Berechtigung, das Security- und Sysmon-Log zu lesen. Behoben durch Umstellen des Dienstkontos auf Local System:

```
sc config SplunkForwarder obj= LocalSystem
net stop SplunkForwarder
net start SplunkForwarder
```

Danach liefen alle drei Indizes sauber.

### Lessons Learned

- Bei fehlenden Logs immer von hinten nach vorne prüfen: erst die Quelle (produziert die Anwendung überhaupt Events, hier per `wevtutil`), dann die Konfiguration (`btool`), dann die Verbindung (`list forward-server`), dann die Logs des Forwarders selbst (`splunkd.log`)
- `index=_internal host=<hostname>` ist ein guter genereller Test, ob ein Forwarder überhaupt Daten sendet, unabhängig vom eigentlichen Input
- Der Splunk Forwarder-Dienst braucht ausreichende Rechte, um Security-relevante Windows Event Log Kanäle zu lesen, Local System ist für ein Lab die einfachste Lösung

## Teil 2: Kali VM, Bridged Netzwerk, erste Angriffe

Anders als Teil 1 läuft die Angreifer-VM auf einem separaten Gerät, einem MacBook mit Apple-Silicon-Chip (M2), während die Windows-Ziel-VM weiterhin auf dem PC in VirtualBox läuft. Beide Geräte müssen sich dafür im selben Netzwerk sehen können.

### Was gemacht wurde

1. UTM auf dem MacBook installiert (VirtualBox unterstützt Apple Silicon nur eingeschränkt)
2. Kali Linux (arm64, native Virtualisierung) heruntergeladen und in UTM installiert
3. Netzwerkmodus beider VMs von NAT/Shared Network auf Bridged umgestellt, sodass beide eine reguläre IP-Adresse aus dem Heimnetzwerk bekommen
4. Verbindung zwischen beiden VMs mit `ping` bestätigt
5. Auf der Windows-VM Remotedesktop (RDP) aktiviert, Netzwerkprofil auf „Privat" gesetzt, damit die zugehörige Firewall-Regel greift
6. Von Kali aus mit Nmap gescannt (`-Pn`, da Windows ICMP-Pings standardmäßig blockt)
7. Mit Hydra ein Brute-Force-Test gegen RDP gefahren
8. Den Angriff in Splunk nachgewiesen, inklusive Zuordnung zur Quell-IP der Kali-VM
9. Eine einfache Detection-Suche gebaut, die mehrere fehlgeschlagene Logins derselben Quelle zusammenfasst

### Ergebnis

Nmap-Scan gegen die offenen Ports der Windows-VM:

```
sudo nmap -Pn -sV -p 3389 192.168.0.105
```

zeigt Port 3389 (RDP) als offen, nachdem Remotedesktop aktiviert wurde.

Brute-Force-Test mit Hydra (Testzweck, absichtlich mit einer kleinen, garantiert falschen Passwortliste):

```
hydra -l WhiteLotus -P /tmp/passwords.txt rdp://192.168.0.105
```

Nachweis in Splunk, dass die Versuche als fehlgeschlagene Anmeldungen erfasst wurden, inklusive Quell-IP:

```
index=security_logs EventCode=4625
```

Im aufgeklappten Event stehen `Workstation Name: kali` und `Source Network Address: 192.168.0.104`, eindeutig der Kali-VM zugeordnet.

Einfache Detection-Suche, die Brute-Force-Muster (mehrere Fehlversuche derselben Quelle) zusammenfasst:

```
index=security_logs EventCode=4625
| stats count by Source_Network_Address, Account_Name
| where count > 3
```

### Troubleshooting

**Falsche CPU-Architektur.** Die zuerst heruntergeladene Kali-ISO war für x86_64 (amd64), UTM auf einem M2-Mac benötigt aber nativ arm64. UTM meldete das direkt beim Auswählen des Boot-Images. Für Kali Purple gibt es aktuell offiziell keine arm64-Version, daher fiel die Wahl auf das normale Kali Linux (arm64), das für Angriffe aus diesem Lab ausreicht.

**UEFI-Shell statt Installer.** Nach dem VM-Start landete die VM in einer UEFI Interactive Shell statt im Kali-Bootmenü, weil das Boot-Medium nicht automatisch erkannt wurde. Manuell behoben durch Wechsel auf das CD-Laufwerk und direkten Aufruf der Bootdatei:

```
FS0:
cd EFI\Boot
bootx64.efi
```

**Nach der Installation Boot-Loop zur Installer-ISO.** Nach abgeschlossener Installation bootete die VM wieder vom Installationsmedium statt von der neuen Festplatte. Grund: die ISO war in UTM noch als Boot-Medium eingelegt. Behoben durch Auswerfen der ISO in den VM-Einstellungen (Drives, „Eject").

**Kali erreicht kein Internet trotz gültiger IP.** `ping` gegen öffentliche IPs (`8.8.8.8`, `1.1.1.1`) schlug mit „Destination Port Unreachable" fehl, obwohl Kali eine gültige IP im UTM-eigenen Shared-Network-Bereich (`192.168.64.x`) hatte und das eigene Gateway erreichbar war. Ursache war ein Netzwerkfilter im umgebenden Netzwerk, der ICMP blockiert; per `curl` (echter TCP/HTTP-Verkehr) funktionierte die Verbindung einwandfrei. Lehre daraus: `ping` ist kein zuverlässiger Konnektivitätstest, viele Netzwerke filtern ICMP, ohne den restlichen Datenverkehr zu blockieren.

**Kein Ping zur Windows-VM.** Nach dem Umstieg auf Bridged Mode erreichte Windows die Kali-VM problemlos, umgekehrt schlug der Ping fehl. Ursache: die Windows-Firewall blockiert eingehende ICMP-Echo-Anfragen standardmäßig, das ist Normalverhalten und musste für dieses Lab nicht behoben werden, da die eigentlichen Angriffstests (Nmap mit `-Pn`, Hydra) ohnehin nicht auf ICMP angewiesen sind.

**RDP-Port bleibt „filtered" trotz aktivierter Firewall-Regel.** Der naheliegende erste Verdacht (Netzwerkprofil „Öffentlich" statt „Privat") stellte sich als falsche Fährte heraus, das Profil stand bereits korrekt auf „Privat". Die eigentliche Ursache: Remotedesktop war in den Windows-Einstellungen schlicht noch nicht aktiviert worden. Nach dem Aktivieren war Port 3389 sofort erreichbar.

### Lessons Learned

- Bei Apple Silicon immer zuerst die passende Architektur (arm64) sicherstellen, bevor an anderen Stellen gesucht wird, viele Folgefehler (UEFI-Shell, „Unsupported"-Fehler beim Booten) gehen auf diese eine Ursache zurück
- `ping` ist ein schwacher Konnektivitätstest, weil ICMP häufig gefiltert wird, ohne dass echter Datenverkehr (TCP/HTTP) betroffen ist, im Zweifel mit `curl` gegenprüfen
- Windows blockt eingehende Dienste und ICMP standardmäßig sehr restriktiv, das ist für ein Security-Lab eher hilfreich, weil es reale Bedingungen abbildet
- Bevor man tief in der Firewall-Konfiguration sucht, erst die einfachste Ursache ausschließen, hier: ist der Dienst (RDP) überhaupt aktiviert
- Ein einfaches `stats`/`where`-Muster in Splunk reicht bereits aus, um Brute-Force-Versuche sichtbar zu machen, ganz ohne fertige Regelwerke

## Screenshots

<img width="555" height="283" alt="image" src="https://github.com/user-attachments/assets/ddd89796-b03e-4c8a-9eb2-2ee7c967a95e" />
<img width="1300" height="626" alt="image" src="https://github.com/user-attachments/assets/97f18530-b124-482b-a28a-7b50e600c309" />
<img width="1412" height="862" alt="image" src="https://github.com/user-attachments/assets/5ceb0b98-db78-46e9-ac6f-784f44d4d4a9" />
<img width="1478" height="926" alt="image" src="https://github.com/user-attachments/assets/7b5edf27-8713-4700-be96-66cde3342c40" />
<img width="957" height="708" alt="image" src="https://github.com/user-attachments/assets/0af9455c-1b3b-42d0-90e8-692b40d278bb" />
<img width="437" height="598" alt="image" src="https://github.com/user-attachments/assets/19f7a1a1-9d77-40c8-9c2c-aa69cea215e7" />
<img width="975" height="692" alt="image" src="https://github.com/user-attachments/assets/3b393d97-6bc0-4ae3-a22a-0a079476d9cf" />






