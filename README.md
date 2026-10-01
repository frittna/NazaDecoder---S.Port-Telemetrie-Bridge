# NazaDecoder - S.Port Telemetrie Bridge 

## Naza-M V1/V2 to FrSky SmartPort - Arduino

-> integriert die GPS- und Magn.-Daten vom DJI Naza-M V1/V2 in den FrSky SmartPort Telemetrie-Datenkanal S.Port.

-> verwendet NazaDecoder Bibliothek [dalmirdasilva/ArduinoNazaDecoder](https://github.com/dalmirdasilva/ArduinoNazaDecoder) und FrSkySportTelemetry Bibiliothek [FrSkySportTelemetry](https://github.com/marhar/FrSkySportTelemetry)

-> automatisch gefundene Sensoren: Latitude, Longitude, Altitude, Speed, Heading, Satellites*, FixType*, (keine Zeitstempel, das spart 6 einzelne Sensoren J/M/D/H/M/S)

### *)Erklärung zu Satellites & FixType

Die Satellitenanzahl und GPSFix-Type werden hier kombiniert in einem Hilfswert des RPM Sensors übertragen. zb: T1 = 113 bedeutet 11 Sats(die 11) + 3DFix(die 3)

Um am Sender den Wert T1 wieder schön in zwei Werte zu trennen kann man, wenn man will, mein Script in `SCRIPTS\TELEMETRY\NAZA_fix.lua` nutzen. Dieses trennt T1 zurück in "Sats" und "Gfix". T1 muss in der Sensorenliste als Basis verbleiben. RPM kann gelöscht werden.

Das ganze macht man deshalb weil die zwei Werte sonst fehlen würden weil sie nicht im FrSky-GPS-Paket enthalten sind.
So aber werden sie automatisch bei Sensorsuche vom Sender gepollt und gefunden. RPM-Sensor deshalb, weil dieser T1 Rohwerte ohne feste Einheit mitsenden kann.

### Hardware

- Arduino mit ATMega328P 5V (hier in Form eines zweckentfremdeten alten S-OSD/iOSD Moduls mit 328P, es wird aber mehr oder weniger mit jedem Arduino 328P/328PB laufen)
- Es wird nur ein HW-Serial Eingang für das GPS-Singal und ein SW-Serial Port Ausgang für die SPort übertragung gebraucht. Evtl. ein LED-Ausgang.
- Somit ist bei anderer Hardware nur die Pinbelegung des Ein-/Ausgangs anzupassen und evtl. die Einstellungen für den Programmer in Arduino bzw bevorzugte Art es zu flashen.

In meinem Fall:

- Arduino IDE: Werkzeuge -> Board -> "Arduino Pro or Mini Pro" -> Processor: 16Mhz 5V -> Programmer -> STK 500 dev. -> Sketch -> Programmer upload (Strg+Shift+U)
- ÜBER ISP-KABEL AM ISP ANSCHLUSS -> BOOT BUTTON AM MODUL WÄHREND FLASHEN FEST GEDRÜCKT HALTEN.
- Der Atmega283P hat nur EINE serielle Schnittstelle, aktives GPS und serieller Monitor zum testen gleichzeitig nicht möglich.

### Anschlüsse

- Atmega328P Pin PD7: über R1k Widerstand zu SmartPort Leitung führen ("CH3 In THRO" auf meinem S-OSD Modul)
- Atmega328P Pin PD0: Serial-RX-Pin (PD0 / RX) zum NAZA<->GPS Kabel-TX führen (Pin 2 orange, neben 1 GND schwarz).
- optional: sicherheitshalber habe ich einen 3.3V zu 5V Pegelwandler für das serielle GPS-RX-Signal(3.3V) zum Arduino(5V) eingebaut.
- 1x Status LED (gültiges Paket): Atmega328P Pin 9 (am S-OSD Modul: "F1-In"-PIN mit LED-Vorwiderstand über LED und nach Masse führen)
