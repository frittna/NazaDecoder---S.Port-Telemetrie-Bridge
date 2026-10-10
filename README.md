## Naza-M V1/V2 to FrSky SmartPort Telemetrie Bridge - Arduino + EDGE-TX LUA SCRIPT
-  Project Site: https://github.com/frittna/NazaDecoder-S.Port-Telemetrie-Bridge-MPU @ 10.Okt.2026 

-->   runter scrollen für die deutsche Beschreibung  --  scroll down for german explanations   <--
  
- Integrates all GPS data and compass heading from the DJI Naza-M V1/V2 into the native FrSky SmartPort telemetry data channel S.Port.

- Uses NazaDecoder library [dalmirdasilva/ArduinoNazaDecoder](https://github.com/dalmirdasilva/ArduinoNazaDecoder) and FrSkySportTelemetry library [FrSkySportTelemetry](https://github.com/marhar/FrSkySportTelemetry)

- Auto-detected sensors: Latitude, Longitude, Altitude, Speed, Heading, Timestamp, Satellites*, FixType*
*)Satellite count and GPS fix type, which are not included in the FrSky GPS packet, are transmitted using auxiliary values of the standard RPM sensor (which also contains T1+T2). 
RPM itself can be deleted later. Simply rename T1+T2 to "Sats" and "GFix".

### Hardware

- Arduino with ATMega328P 5V (in my case, a repurposed old S-OSD/iOSD REMZIBI module with an ATmega328P on it, but it will work with any Arduino 328P/328PB)
- Only one hardware serial input for the GPS signal and one software serial output for S.Port transmission are needed. Optional: one LED output.
- For other hardware, only the pin assignment of the input/output needs to be adapted and possibly the settings for the programmer in Arduino or your preferred flashing method.

### Connections

  In my case:
- ATmega328P Pin PD7: via 1k resistor to SmartPort line ("CH3 In THRO" on my S-OSD module).
- ATmega328P Pin PD0: Serial RX pin (PD0 / RXD) connected to NAZA<->GPS cable TX (Pin 2 orange, next to Pin 1 GND black).
- 1x Status LED of your choice ("valid packet detected"): ATmega328P Pin 13/PB1 -> Pin 9 in Arduino! (on S-OSD module: "F1-In" pin with appropriate series resistor via LED to ground)
- If you are using a reprogrammed S-OSD module like I am, do not pass the GPS through the module as normally intended. The pins "to GPS" and "to LED" from the module diagram are not directly connected 1:1.
- Therefore, a simple tap must be made from the GPS cable for TX and GND, or much better: build a pass-through connector from the desoldered connector and pins that you no longer need.
- #########
- OPTIONAL: For safety, I installed a 3.3V->5V level converter on the serial GPS TX signal (3.3V) to the Arduino (5V). So 3.3V from small regulator and 5V to the level shifter, with LV1 to GPS(TX) and HV1 to PD7(Pin 30).
- #########
- OPTIONAL: MPU-6000/6050 sensor or similair, connection via I²C -> my LUA script `horz.lua` also works with this -> See instructions further down in the text.
- #########

### Programming the Arduino with ATmega328P
- Arduino IDE: Tools -> Board -> "Arduino Pro or Mini Pro" -> Processor: 16MHz 5V -> Programmer -> STK 500 dev. -> Sketch -> Upload Programmer (Ctrl+Shift+U)
- VIA ISP CABLE ON THE ISP CONNECTOR -> KEEP BOOT BUTTON ON MODULE PRESSED FIRMLY DURING FLASHING.
- The ATmega328P has only ONE serial interface; active GPS and serial monitor for testing cannot run simultaneously.

### LUA Script Instructions - Attitude Display and Telemetry Display Script - for SmartPort Transmitters like Taranis QX9 EdgeTX @ 2.11.7 (and compatible)
--
- `horz.lua` offers sources `ANGLES` (receiver values `Ptch`/`Roll`) and `VECTOR` (normalized `AccX/Y/Z`) in the menu. In vector mode, `fwd`, `side`, and `down` can be set with signs; `Calibrate` first determines the gravity axis and then the forward axis by tilting nose-down.

- For the Archer mounted on its side, use these start values: `fwd=X+`, `side=Z-`, `down=Y+`: nose down gives `AccX+`, lower right gives `AccZ+`, and down is `AccY+`. 
When using the Gyro-Arduino sketch, set these Lua axes in the menu to `fwd=X+`, `side=Y+`, `down=Z-`; this is not the Archer default setting. Pitch/Roll are not mixed with raw axes; Heading remains `Hdg` from the Naza.

- The Config page links to `SENSORS` and `AXES`; `ATTITUDE:` changes ANGLES/VECTOR and `VIEW:` changes 3D/Classic on the row below. Use `+/-` to move between rows and the rotary encoder left/right to select fields. At the last field, right advances to the first field of the next row; ENTER activates the selected field. The sensor pages are `Sensors Left 1/3` (slots 1–6), `Sensors Right 2/3` (slots 7–9 plus inside-horizon, graph, and altimeter settings), and `Custom Sensors 3/3`. Each of the six custom entries contains only a manually entered four-character name, unit, and precision. A configured custom name is added to the source catalog and can then be selected anywhere a catalog source is used; its unit and precision are applied when selected.
- Sensor rows expose precision (0–4 decimals), `MM` for a temporary MIN/MAX editor, and the visibility checkbox. `+/-` and the rotary encoder change catalog sources and precision. The graph is enabled by default. In the one-sensor view, `MIN=0` and `MAX=0` keep automatic scaling; configured limits are shown without units. If only one limit is set, the other edge follows the current session extreme (with at least a one-unit span); an inverted/equal pair is defensively displayed with a one-unit span.

- NEW: If you have only 1 to 5 sensors active instead of all 6 (this is for the left side only) the space between the fields and the font-size will be adjusted automatically.

- If graph display is disabled, the one-sensor field shows the current session minimum and maximum instead; these extrema reset when the Lua script starts. Graph X-Time remains adjustable from 10–999 seconds.

- `Altimeter-Scale` (default `Alt`) controls the 2.5-m/5-m altitude marks at the left edge of the horizon box. On the axis settings page, `View` toggles 3D/Classic; `Attitude` selects the attitude source and `Calibrate` starts vector calibration. In `VECTOR` mode, Pitch/Roll sources are disabled because the vector axes provide attitude.

- 3D view shows dotted attitude lines at ±45° and dashed lines at ±90°; the compass bar and filled home arrow remain. `View` can be switched back to the classic horizon view at any time. The 3D mode also works with the corrected `Ptch`/`Roll` values (`ANGLES`); raw values of all three acceleration axes are only needed in `VECTOR` mode.

- The display in the horizon center can be switched to a catalog sensor on the second sensor page under `inside Horizon` and turned off with its checkbox. By default it is active and displays `Alt`.

- Next to the satellite count, the main view shows a 10×10-pixel symbol: without GPS fix, the symbol and number are hidden; from fix 1, the satellite base blinks; with 2D/3D fix, signal rays are added. After more than 10 seconds of stable 3D fix, the symbol blinks for one minute if it drops to fix 2 or below for longer than 3 seconds.

- The home arrow is set from the GPS position on the first valid 3D fix after Lua start and points relative to `Hdg` to the starting position. The direction is marked within the visible compass scale; outside the scale, an arrow on the left or right edge points in the appropriate direction. Below 5 m distance it is hidden due to GPS position noise; after a Lua restart, home is reset.
- Arduino GPS position, altitude, and vario updates are accepted only from a valid 2D-or-better fix and valid coordinates; altitudes above 3000 m are ignored.

- The sketch waits 25 seconds after power-on before reading MPU data. It then averages the gyro offset for about one second; the model must be stationary during this measurement. The attitude is then initialized from the actual acceleration direction – a tilted power-on position is not subtracted as zero position.

-- Example images:
  
![](DOKU/Case_compl.jpg)

![](DOKU/Lua_Screen1.png) 

![](DOKU/Lua_Screen9.png)

![](DOKU/Lua_Screen2.png)

![](DOKU/Lua_Screen3.png)

![](DOKU/Lua_Screen4.png)

![](DOKU/Lua_Screen5.png)

![](DOKU/Lua_Screen6.png)

![](DOKU/Lua_Screen7.png)

![](DOKU/Lua_Screen8.png)

![](DOKU/Lua_Screen9.png)

![](DOKU/Lua_Screen10.png)

![](DOKU/Lua_Screen11.png)


##########################################################################

##########################################################################

##########################################################################

##########################################################################


## Naza-M V1/V2 to FrSky SmartPort Telemetrie Bridge - Arduino + EDGE-TX LUA SCRIPT
-  Project Site: https://github.com/frittna/NazaDecoder-S.Port-Telemetrie-Bridge-MPU @ 8.Okt.2026 

- integriert alle GPS-Daten und das Kompass-Heading vom DJI Naza-M V1/V2 in den nativen FrSky SmartPort Telemetrie-Datenkanal S.Port.

- verwendet NazaDecoder Bibliothek [dalmirdasilva/ArduinoNazaDecoder](https://github.com/dalmirdasilva/ArduinoNazaDecoder) und FrSkySportTelemetry Bibiliothek [FrSkySportTelemetry](https://github.com/marhar/FrSkySportTelemetry)

- automatisch gefundene Sensoren: Latitude, Longitude, Altitude, Speed, Heading, Timestamp, Satellites*, FixType*
*)Die Satellitenanzahl und GPSFix-Type welche im FrSky GPS-Paket nicht vorgesehen sind werden mit Hilfswerten des Standartsensors RPM (enthält auch T1+T2) übertragen. 
RPM selbst kann später gelöscht werden. T1+T2 einfach in "Sats" und GFix" umbenennen.

### Hardware

- Arduino mit ATMega328P 5V (hier in Form eines zweckentfremdeten alten S-OSD/iOSD REMZIBI Moduls mit Atmega328P darauf, es wird aber mit jedem Arduino 328P/328PB laufen)
- Es wird nur ein HW-Serial Eingang für das GPS-Singal und ein SW-Serial Port Ausgang für die SPort übertragung gebraucht. Evtl. ein LED-Ausgang.
- Somit ist bei anderer Hardware nur die Pinbelegung des Ein-/Ausgangs anzupassen und evtl. die Einstellungen für den Programmer in Arduino bzw bevorzugte Art es zu flashen.

### Anschlüsse

  In meinem Fall:
- Atmega328P Pin PD7: über R1k Widerstand zu SmartPort Leitung führen ("CH3 In THRO" auf meinem S-OSD Modul). 
- Atmega328P Pin PD0: Serial-RX-Pin (PD0 / RXD) zum NAZA<->GPS Kabel-TX führen (Pin 2 orange, neben 1 GND schwarz).
- 1x Status LED nach Wahl ("gültiges Paket erkannt"): Atmega328P Pin13/PB1 -> 9 in Ardiuono! (am S-OSD Modul: "F1-In"-PIN mit passendem Vorwiderstand über LED nach Masse führen)
- Wenn jemand wie ich dieses umprogrammierte S-ODS Modul verwendet, nicht das GPS wie sonst vorgesehen durch das Modul schleifen. Die Pins des "to GPS" und "to LED" vom Bild des Moduls sind nicht 1:1 durchverbunden.
- Es muss also vom GPS-Kabel eine einfache Anzapfung für TX und GND gemacht werden, oder viel schöner ist einen Passthrough Stecker aus den ausgelöteten Stecker und Pins basteln die man alle nicht mehr braucht.
- #########
- OPTIONAL: ich habe mir sicherheitshalber einen 3.3V->5V Pegelwandler für das serielle GPS-TX-Signal(3.3V) zum Arduino(5V) eingebaut. Also 3.3V aus kleinem Fix-Regler und 5V in den Levelshifter, dessen LV1 zu GPS(TX) und HV1 zu PD7(Pin30).
- #########
- OPTIONAL: MPU-6000-Senor Anschluß per I²C -> dazu passt auch mein LUA Skript `horz.lua` -> Siehe Anleitung weiter unten im Text..
- #########

### Programmierung des Ardiono bei Atmega328P
- Arduino IDE: Werkzeuge -> Board -> "Arduino Pro or Mini Pro" -> Processor: 16Mhz 5V -> Programmer -> STK 500 dev. -> Sketch -> Programmer upload (Strg+Shift+U)
- ÜBER ISP-KABEL AM ISP ANSCHLUSS -> BOOT BUTTON AM MODUL WÄHREND FLASHEN FEST GEDRÜCKT HALTEN.
- Der Atmega283P hat nur EINE serielle Schnittstelle, aktives GPS und serieller Monitor zum testen gleichzeitig nicht möglich.



### LUA Script Anleitung - Lageanzeige und Telemetie Display Skript - für SmartPort Sender wie Taranis QX9 EdgeTX @ 2.11.7 (und kompatible)
--
- `horz.lua` bietet im Menü die Quellen `ANGLES` (Empfängerwerte `Ptch`/`Roll`) und `VECTOR` (normierte `AccX/Y/Z`). Im Vektormodus sind `fwd`, `side` und `down` samt Vorzeichen einstellbar; `Calibrate` ermittelt zuerst die Schwerkraftachse und danach durch Nase-abwärts-Neigen die Vorwärtsachse.

- Für den seitlich montierten Archer passen als Startwert `fwd=X+`, `side=Z-`, `down=Y+`: Nase abwärts ergibt `AccX+`, rechts unten `AccZ+`, und unten ist `AccY+`. 
Bei Verwendung des Gyro-Arduino-Sketches diese Lua-Achsen im Menü auf `fwd=X+`, `side=Y+`, `down=Z-` einstellen; das ist nicht die Archer-Voreinstellung. Pitch/Roll werden nicht mit Rohachsen vermischt; Heading bleibt `Hdg` von der Naza.

- Die Config-Seite verlinkt auf `SENSORS` und `AXES`; darunter schalten `ATTITUDE:` zwischen ANGLES/VECTOR und `VIEW:` zwischen 3D/Classic um. Mit `+/-` wechselt man zwischen den Zeilen, der Drehgeber wählt links/rechts die Felder; rechts vom letzten Feld geht es zum ersten Feld der nächsten Zeile. ENTER aktiviert das markierte Feld. Die Sensorseiten heißen `Sensors Left 1/3` (Slots 1–6), `Sensors Right 2/3` (Slots 7–9 sowie inside-Horizon-, Graph- und Altimeter-Einstellungen) und `Custom Sensors 3/3`. Jeder der sechs Custom-Einträge enthält nur einen manuell vergebenen vierstelligen Namen, eine Einheit und eine Präzision. Ein eingetragener Custom-Name wird der Quellliste hinzugefügt und kann anschließend überall als Quelle gewählt werden; Einheit und Präzision werden bei der Auswahl übernommen.
- Sensorzeilen bieten Präzision (0–4 Nachkommastellen), `MM` für eine temporäre MIN/MAX-Seite und die Sichtbarkeits-Checkbox. `+/-` und Drehgeber ändern Katalogquelle und Präzision. Der Graph ist standardmäßig aktiv. Bei genau einem Sensor bleibt mit `MIN=0` und `MAX=0` die automatische Skalierung aktiv; gesetzte Grenzen werden ohne Einheit angezeigt. Ist nur eine Grenze gesetzt, folgt die andere dem aktuellen Session-Extrem (mindestens ein Einheitsschritt Abstand); ein vertauschtes/gleiches Paar wird defensiv mit einem Einheitsschritt dargestellt.

- NEU: Wenn anstelle aller sechs Sensoren nur zw. 1 bis 5 aktiv sind (dies gilt nur für die linke Seite), werden der Abstand zwischen den Feldern sowie die Schriftgröße automatisch angepasst.

- Ist der Graph deaktiviert, zeigt das Ein-Sensor-Feld stattdessen Session-Minimum und -Maximum; diese Werte werden beim Start des Lua-Skripts zurückgesetzt. Graph X-Time ist weiterhin von 10–999 Sekunden einstellbar.

- `Altimeter-Scale` (Standard `Alt`) steuert die 2,5-m-/5-m-Höhenstriche links an der Horizontbox. Auf der Axis-Settings-Seite schaltet `View` 3D/Classic um; `Attitude` wählt die Lagequelle und `Calibrate` startet die Vektorkalibrierung. Im `VECTOR`-Modus sind Pitch/Roll-Quellen deaktiviert, da die Vektorachsen die Lage liefern.

- 3D-View zeigt gepunktete Lage-Linien bei ±45° und gestrichelte Linien bei ±90°; Kompassleiste und gefüllter Home-Pfeil bleiben erhalten. `View` kann jederzeit auf die klassische Horizontansicht zurückgestellt werden. Der 3D-Modus funktioniert auch mit den korrigierten `Ptch`/`Roll`-Werten (`ANGLES`); Rohwerte aller drei Beschleunigungsachsen werden nur im `VECTOR`-Modus benötigt.

- Die Anzeige in der Horizontmitte lässt sich auf der zweiten Sensorseite unter `inside Horizon` auf einen Katalogsensor umstellen und mit der Checkbox abschalten. Standardmäßig ist sie aktiv und zeigt `Alt`.

- Neben der Satellitenzahl zeigt die Hauptansicht ein 10×10-Pixelsymbol: ohne GPS-Fix werden Symbol und Zahl ausgeblendet, ab Fix 1 blinkt die Satellitenbasis, bei 2D/3D-Fix kommen Signalstrahlen hinzu. Nach mehr als 10 Sekunden stabilem 3D-Fix blinkt das Symbol bei einem Einbruch auf Fix 2 oder darunter (länger als 3 Sekunden) eine Minute lang.

- Der Home-Pfeil wird beim ersten gültigen 3D-Fix nach Lua-Start aus der GPS-Position gesetzt und zeigt relativ zum `Hdg` zur Startposition. Die Richtung wird innerhalb der sichtbaren Kompassskala markiert, außerhalb weist ein Pfeil am linken oder rechten Rand in die passende Richtung. Unter 5 m Abstand wird er wegen GPS-Positionsrauschen ausgeblendet; nach einem Lua-Neustart wird Home neu gesetzt.
- Das Arduino-Sketch übernimmt GPS-Position, Höhe und Vario nur bei gültigem Fix ab 2D und gültigen Koordinaten; Höhen über 3000 m werden ignoriert.

- Der Sketch wartet nach dem Einschalten 25 Sekunden, bevor er MPU-Daten liest. Danach mittelt er für etwa eine Sekunde den Gyro-Offset; das Modell muss während dieser Messung ruhig stehen. Die Lage wird anschließend aus der tatsächlichen Beschleunigungsrichtung initialisiert – eine schräge Einschaltlage wird nicht als Nulllage abgezogen.


-- Beispiel Bilder: siehe oben
