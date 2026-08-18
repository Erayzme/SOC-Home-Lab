# SOC Home Lab

Ein Home Lab zum Üben von Security Monitoring und späteren Angriffssimulationen. Ziel des Projekts: eine Windows-VM, die ihre eigenen Security-Events über Sysmon erfasst und an Splunk sendet, danach Angriffe aus einer Kali-VM gegen dieses Setup fahren und die Erkennung in Splunk nachweisen.

## Status

- [x] Teil 1: Windows VM mit Sysmon und Splunk
- [ ] Teil 2: Kali VM, Netzwerk auf Bridged, erste Angriffe

## Aufbau

| Komponente | Rolle |
|---|---|
| VirtualBox | Virtualisierung |
| Windows 11 Enterprise (Evaluierung) | Ziel-VM, generiert Events |
| Sysmon (SwiftOnSecurity-Konfiguration) | Erfasst detaillierte Prozess-, Netzwerk- und Registry-Events |
| Splunk Universal Forwarder | Sendet Windows- und Sysmon-Logs an Splunk |
| Splunk Enterprise | Empfängt, indiziert, durchsucht die Logs |

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

## Screenshots

<img width="767" height="587" alt="image" src="https://github.com/user-attachments/assets/c1014264-f9fe-4701-936f-351101496390" />


## Nächste Schritte (Teil 2)

- Kali VM auf dem MacBook einrichten
- Netzwerk beider VMs auf Bridged umstellen
- Erste Angriffe von Kali gegen die Windows-VM fahren (z. B. Brute-Force, Nmap-Scan)
- Erkennung der Angriffe in Splunk nachweisen und dokumentieren
