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
