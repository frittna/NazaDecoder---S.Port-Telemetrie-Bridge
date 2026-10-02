# NazaDecoder - S.Port Telemetrie Bridge

## Naza-M V1/V2 to FrSky SmartPort - Arduino
-  source code: [frittna/NazaDecoder---S.Port-Telemetrie-Bridge](https://github.com/frittna/NazaDecoder---S.Port-Telemetrie-Bridge)  @ 2.Okt.2026 
  
-> integriert die GPS- und Magn.-Daten vom DJI Naza-M V1/V2 in den FrSky SmartPort Telemetrie-Datenkanal S.Port.

-> verwendet NazaDecoder Bibliothek [dalmirdasilva/ArduinoNazaDecoder](https://github.com/dalmirdasilva/ArduinoNazaDecoder) und FrSkySportTelemetry Bibiliothek [FrSkySportTelemetry](https://github.com/marhar/FrSkySportTelemetry)

-> automatisch gefundene Sensoren: Latitude, Longitude, Altitude, Speed, Heading, Satellites*, FixType*, (keine Zeitstempel, das spart 6 relativ unnötige Sensoren J/M/D/H/M/S)

*)Die Satellitenanzahl und GPSFix-Type welche im FrSky GPS-Paket nicht vorgesehen sind werden mit Hilfswerten des Standartsensors ASS-Airspeed/Custom T1+T2 übertragen. 
AirSpeed selbst kann später gelöscht werden. T1+tT2 in "Sats" und GFix" umbenennen.

### Hardware

- Arduino mit ATMega328P 5V (hier in Form eines zweckentfremdeten alten S-OSD/iOSD Moduls mit 328P, es wird aber mehr oder weniger mit jedem Arduino 328P/328PB laufen)
- Es wird nur ein HW-Serial Eingang für das GPS-Singal und ein SW-Serial Port Ausgang für die SPort übertragung gebraucht. Evtl. ein LED-Ausgang.
- Somit ist bei anderer Hardware nur die Pinbelegung des Ein-/Ausgangs anzupassen und evtl. die Einstellungen für den Programmer in Arduino bzw bevorzugte Art es zu flashen.

### Anschlüsse

  In meinem Fall:
- Atmega328P Pin PD7: über R1k Widerstand zu SmartPort Leitung führen ("CH3 In THRO" auf meinem S-OSD Modul)
- Atmega328P Pin PD0: Serial-RX-Pin (PD0 / RX) zum NAZA<->GPS Kabel-TX führen (Pin 2 orange, neben 1 GND schwarz).
- optional: sicherheitshalber habe ich einen 3.3V zu 5V Pegelwandler für das serielle GPS-RX-Signal(3.3V) zum Arduino(5V) eingebaut.
- 1x Status LED (gültiges Paket): Atmega328P Pin 9 (am S-OSD Modul: "F1-In"-PIN mit LED-Vorwiderstand über LED und nach Masse führen)

- Arduino IDE: Werkzeuge -> Board -> "Arduino Pro or Mini Pro" -> Processor: 16Mhz 5V -> Programmer -> STK 500 dev. -> Sketch -> Programmer upload (Strg+Shift+U)
- ÜBER ISP-KABEL AM ISP ANSCHLUSS -> BOOT BUTTON AM MODUL WÄHREND FLASHEN FEST GEDRÜCKT HALTEN.
- Der Atmega283P hat nur EINE serielle Schnittstelle, aktives GPS und serieller Monitor zum testen gleichzeitig nicht möglich.


