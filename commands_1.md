# Befehlsreferenz — Teil 1

Alle Terminal-Befehle aus Teil 1, chronologisch, mit kurzer Erklärung. Alle Befehle laufen in einer Eingabeaufforderung mit Administratorrechten auf der Windows-VM, sofern nicht anders angegeben.

## Sysmon installieren

```
Sysmon64.exe -accepteula -i sysmonconfig-export.xml
```

Installiert Sysmon mit der SwiftOnSecurity-Konfiguration.

## Splunk Universal Forwarder — Log-Quellen konfigurieren

Datei `C:\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf`:

```
[WinEventLog://Security]
index=security_logs
disabled=false

[WinEventLog://System]
index=windows_logs
disabled=false

[WinEventLog://Microsoft-Windows-Sysmon/Operational]
index=sysmon_logs
disabled=false
```

Zugehörige `outputs.conf` (wird bei der Installation automatisch angelegt, wenn `127.0.0.1` und Port `9997` als Ziel angegeben werden):

```
[tcpout]
defaultGroup = default-autolb-group

[tcpout:default-autolb-group]
server = 127.0.0.1:9997

[tcpout-server://127.0.0.1:9997]
```

## Forwarder neu starten

```
cd "C:\Program Files\SplunkUniversalForwarder\bin"
splunk restart
```

## Verbindung zum Indexer prüfen

```
splunk list forward-server
```

Erwartete Ausgabe bei funktionierender Verbindung:

```
Active forwards:
        127.0.0.1:9997
Configured but inactive forwards:
        None
```

## Empfangenen Port auf der Splunk-Enterprise-Seite prüfen

```
cd "C:\Program Files\Splunk\bin"
splunk display listen
```

## Vorhandene Indizes auflisten

```
splunk list index | findstr /i "sysmon security_logs windows_logs"
```

## Sysmon-Events direkt aus dem Windows Event Log lesen (ohne Splunk)

```
wevtutil qe "Microsoft-Windows-Sysmon/Operational" /c:5 /rd:true /f:text
```

Nützlich, um zu prüfen, ob Sysmon überhaupt Events produziert, unabhängig von Splunk.

## Forwarder-Konfiguration effektiv prüfen (alle Quelldateien zusammengeführt)

```
splunk btool inputs list --debug
```

Zeigt, aus welcher Datei jeder Konfigurationswert stammt, gut um Tippfehler oder überschriebene Werte zu finden.

## Forwarder-Log nach Fehlern durchsuchen

```
cd "C:\Program Files\SplunkUniversalForwarder\var\log\splunk"
findstr /i "TcpOutputProc" splunkd.log
findstr /i "subscribeToEvtChannel errorCode" splunkd.log
```

## Dienstkonto auf Local System umstellen (Fix für errorCode=5 / Zugriff verweigert)

```
sc config SplunkForwarder obj= LocalSystem
net stop SplunkForwarder
net start SplunkForwarder
```

Nötig, weil das ursprüngliche Dienstkonto keine Berechtigung hatte, das Security- und Sysmon-Event-Log zu lesen.

## Testsuchen in Splunk (Search-Feld, kein Terminal)

Alle Sysmon-Events:

```
index=sysmon_logs
```

Alle Events aus einer beliebigen Quelle mit passendem Sourcetype (Fallback-Suche, falls der Index nicht stimmt):

```
index=* sourcetype=WinEventLog:Sysmon
```

Nachweis, dass überhaupt Daten vom Forwarder ankommen, unabhängig vom konkreten Input:

```
index=_internal host=HomeLabV1
```

Testfall: fehlgeschlagene Anmeldung:

```
index=security_logs EventCode=4625
```

---

# Befehlsreferenz — Teil 2

Alle Terminal-Befehle aus Teil 2, chronologisch. Befehle mit `$` laufen in einem Terminal auf der Kali-VM, Befehle mit `>` in einer Eingabeaufforderung (teils als Administrator) auf der Windows-VM.

## Kali-Netzwerkkonfiguration prüfen

```
$ ip a
```

Zeigt die aktuelle IP-Adresse von `eth0`. Im UTM-Modus „Shared Network" beginnt sie mit `192.168.64.`, im „Bridged"-Modus mit der Adresse aus dem echten Heimnetzwerk (hier `192.168.0.x`).

## Grundlegende Konnektivität testen

```
$ ping -c 4 192.168.64.1
$ curl -I https://www.google.com
```

`ping` gegen das eigene virtuelle Gateway prüft die lokale Netzwerkanbindung, `curl` ist der zuverlässigere Internet-Test, weil viele Netzwerke ICMP filtern, ohne echten Datenverkehr zu blockieren.

## Verbindung zwischen den beiden VMs testen

```
$ ping -c 4 192.168.0.105
> ping 192.168.0.104
```

## Nmap-Scan gegen die Windows-VM

```
$ sudo nmap -Pn -sV 192.168.0.105
```

`-Pn` überspringt den Ping-Check (Windows blockt ICMP standardmäßig), `-sV` versucht zusätzlich Dienste zu erkennen.

Gezielter Scan auf den RDP-Port, nachdem Remotedesktop aktiviert wurde:

```
$ sudo nmap -Pn -sV -p 3389 192.168.0.105
```

## Windows: Remotedesktop und Firewall

RDP wird über die Windows-Einstellungen aktiviert (System → Remotedesktop → Ein), das legt automatisch passende Firewall-Regeln an. Zur Diagnose:

```
> netstat -an | findstr 3389
> netsh advfirewall firewall show rule name="Remote Desktop - User Mode (TCP-In)"
```

## Brute-Force-Test mit Hydra

Kleine Testpasswortliste anlegen (bewusst ohne das echte Passwort):

```
$ echo -e "123456\npassword\nadmin\nletmein\nqwerty\nWillkommen1" > /tmp/passwords.txt
```

Angriff starten:

```
$ hydra -l WhiteLotus -P /tmp/passwords.txt rdp://192.168.0.105
```

## Nachweis und Detection in Splunk (Search-Feld, kein Terminal)

Alle fehlgeschlagenen Logins:

```
index=security_logs EventCode=4625
```

Einfache Brute-Force-Erkennung, mehrere Fehlversuche derselben Quelle:

```
index=security_logs EventCode=4625
| stats count by Source_Network_Address, Account_Name
| where count > 3
```
