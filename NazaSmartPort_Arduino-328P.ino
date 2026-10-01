/*
 * NazaDecoder - SmartPort Telemetrie Data Bridge - @frittna 01-Okt-2026
 * integriert die GPS- und Magn.-Daten vom DJI Naza-M V1/V2 in den FrSky SmartPort Telemetrie-Datenkanal S.Port.
 *
 * verwendet NazaDecoder Bibliothek https://github.com und FrSkySportTelemetry Bibiliothek https://github.com/marhar/FrSkySportTelemetry
 * automatisch gefundene Sensoren: Latitude, Longitude, Altitude, Speed, Heading, Satellites*, FixType*, (keine Zeitstempel, das spart 6 einzelne Sensoren J/M/D/H/M/S)
 *
 *   *)Erklärung zu Satellites & FixType:
 *    Die Satellitenanzahl und GPSFix-Type werden hier kombiniert in einem Hilfswert des RPM Sensors übertragen. zb: T1 = 113 bedeutet 11 Sats(die 11) + 3DFix(die 3)  
 *    Um am Sender den Wert T1 wieder schön in zwei Werte zu trennen kann man, wenn man will, mein Script in SCRIPTS\TELEMETRY\NAZA_fix.lua nutzen.
 *    Dieses trennt T1 zurück in "Sats" und "Gfix". T1 muss in der Sensorenliste als Basis verbleiben. RPM kann gelöscht werden.
 *    Das ganze macht man deshalb weil die zwei Werte sonst fehlen würden weil sie nicht im FrSky-GPS-Paket enthalten sind.
 *    So aber werden sie automatisch bei Sensorsuche vom Sender gepollt und gefunden. RPM-Sensor deshalb, weil dieser T1 Rohwerte ohne feste Einheit mitsenden kann.

 * Hardware:
 *      Arduino mit ATMega328P 5V (hier in Form eines zweckentfremdeten alten S-OSD/iOSD Moduls mit 328P, es wird aber mehr oder weniger mit jedem Arduino 328P/328PB laufen)
 *      Es wird nur ein HW-Serial Eingang für das GPS-Singal und ein SW-Serial Port Ausgang für die SPort übertragung gebraucht. Evtl. ein LED-Ausgang.
 *      Somit ist bei anderer Hardware nur die Pinbelegung des Ein-/Ausgangs anzupassen und evtl. die Einstellungen für den Programmer in Arduino bzw beforzugte Art es zu flashen.
*
 *      In meinem Fall:
 *      -> Arduino IDE: Werkzeuge -> Board -> "Arduino Pro or Mini Pro" -> Processor: 16Mhz 5V -> Programmer -> STK 500 dev. -> Sketch -> Programmer upload (Strg+Shift+U)
 *      -> ÜBER ISP-KABEL AM ISP ANSCHLUSS -> BOOT BUTTON AM MODUL WÄHREND FLASHEN FEST GEDRÜCKT HALTEN.
 *         Der Atmega283P hat nur EINE serielle Schnittstelle, aktives GPS und serieller Monitor zum testen gleichzeitig nicht möglich.
 *
 * Anschlüsse:
 *      Atmega328P Pin PD7  : über R1k Widerstand zu SmartPort Leitung führen ("CH3 In THRO" auf meinem S-OSD Modul)
 *      Atmega328P Pin PD0  : Serial-RX-Pin (PD0 / RX) zum NAZA<->GPS Kabel-TX führen (Pin 2 orange, neben 1 GND schwarz).
 *      optional            : sicherheitshalber habe ich einen 3.3V zu 5V Pegelwandler für das serielle GPS-RX-Signal(3.3V) zum Arduino(5V) eingebaut.
 *                            1x Status LED (gültiges Paket): Atmega328P Pin 9 (am S-OSD Modul: "F1-In"-PIN mit LED-Vorwiderstand über LED und nach Masse führen)
 */

#include <Arduino.h>
// FrSky SmartPort Bibliotheken
#include <FrSkySportSensor.h>
#include <FrSkySportSensorGps.h>
#include <FrSkySportSensorVario.h>
#include <FrSkySportSensorRpm.h>
#include <FrSkySportTelemetry.h>
#include <FrSkySportSingleWireSerial.h>
// NazaDecoder Bibliothek
#include <NazaDecoder.h>

// Status LED
#define LED_BUILTIN 9

// ============================================================================
// COMPILER-SCHALTER FÜR DIE SERIELLE SCHNITTSTELLE / SIMULATION
// ============================================================================
// GPS Live Data aktiv:     0 = Live-Daten vom Naza1   1 = nur künstliche Dummy-Daten
#define USE_TESTDATA 0  //default:0
// Serial-Monitor Ausgabe:  0 = aus   1 = ein
#define SERIAL_MONITOR 0  //default:0 (WENN GPS AN IST GEHT KEIN SERIAL UND UMGEKEHRT, DA NUR 1 SERIELLE SCHNITTSTELLE VORHANDEN !)

// ============================================================================
// OBJEKTE
// ============================================================================
FrSkySportSensorGps gpsSensor;
FrSkySportSensorVario varioSensor;
FrSkySportSensorRpm rpmSensor;
FrSkySportTelemetry telemetry;
NazaDecoder naza;

// LED-Puls-Steuerung (GLOBAL!)
static uint32_t ledPulseStart = 0;
static const uint32_t LED_PULSE_DURATION = 50UL;  // 50ms

// ============================================================================
// DUMMY-TEST-DATEN (wird nur mitkompiliert, wenn USE_TESTDATA == 1)
// ============================================================================
#if USE_TESTDATA == 1
float dummyLatitude = 48.8584f;
float dummyLongitude = 2.2945f;
float dummyAltitude = 100.5f;
float dummySpeed = 5.5f;
float dummyCourse = 45.0f;
float dummyVertSpeed = 1.2f;
//uint8_t dummyYear = 26;
//uint8_t dummyMonth = 9;
//uint8_t dummyDay = 26;
//uint8_t dummyHour = 14;
//uint8_t dummyMinute = 35;
//uint8_t dummySecond = 0;
//uint8_t dummySatellites = 9;
//uint8_t dummyFixType = 3;
#endif

// ============================================================================
// SETUP
// ============================================================================
void setup() {

  // Status-LED 2x kurz blinken lassen (Start-Up)
  digitalWrite(LED_BUILTIN, HIGH);
  delay(130);
  digitalWrite(LED_BUILTIN, LOW);
  delay(130);
  digitalWrite(LED_BUILTIN, HIGH);
  delay(130);
  digitalWrite(LED_BUILTIN, LOW);
  delay(1000);

  pinMode(LED_BUILTIN, OUTPUT);

  // Initialisiert die serielle Hardware-Schnittstelle für beide Modi gleich (115200 Baud)
  Serial.begin(115200);
  delay(500);

// Serieller Text wird NUR kompiliert, wenn wir im Testmodus sind
#if SERIAL_DEBUG == 1
  Serial.println();
  Serial.println(F("========================================="));
  Serial.println(F(" NazaDecoder SmartPort"));
  Serial.println(F(" -> MODUS: DUMMY-TESTDATEN AKTIV <-"));
  Serial.println(F("========================================="));
  Serial.println();
  Serial.println(F("SmartPort wird initialisiert ..."));
  Serial.println(F("Pin 7 (Software-Halbduplex)"));
  Serial.println();
#endif

  /*
   * SmartPort ohne eigenes Polling starten
   * Registriert GPS, Vario und den RPM-Sensor für T1/T2 Daten
   */
  telemetry.begin(
    FrSkySportSingleWireSerial::SOFT_SERIAL_PIN_7,
    &gpsSensor,
    &varioSensor,
    &rpmSensor);

#if SERIAL_DEBUG == 1
  Serial.println(F("SmartPort erfolgreich initialisiert!"));
  Serial.println(F("Test-Daten werden vorinitialisiert:"));
  Serial.print(F("  Lat="));
  Serial.print(dummyLatitude, 6);
  Serial.print(F(" Lon="));
  Serial.println(dummyLongitude, 6);
  Serial.println();
#else
  // Wenn Live-Daten aktiv sind, leeren wir den TX-Puffer vor dem Start,
  // damit keine Reste den Naza-Stream stören.
  Serial.flush();
#endif
}

// ============================================================================
// HAUPTSCHLEIFE
// ============================================================================
void loop() {

// 1. ECHTE NAZA DATA STREAM VERARBEITUNG (NUR WENN USE_TESTDATA == 0)
#if USE_TESTDATA == 0
  while (Serial.available() > 0) {
    uint8_t msgType = naza.decode(Serial.read());
    // VERSION MIT ZEITSTEMPEL
    // if (msgType == NazaDecoder::NAZA_MESSAGE_GPS_TYPE) {
    //   gpsSensor.setData(
    //     naza.getLatitude(),   naza.getLongitude(), naza.getAltitude(),
    //     naza.getSpeed(),      naza.getHeading(),   naza.getYear(),
    //     naza.getMonth(),      naza.getDay(),       naza.getHour(),
    //     naza.getMinute(),     naza.getSecond());
    // VERSION OHNE ZEITSTEMPEL
    if (msgType == NazaDecoder::NAZA_MESSAGE_GPS_TYPE) {
      gpsSensor.setData(
        naza.getLatitude(), naza.getLongitude(), naza.getAltitude(),
        naza.getSpeed(), naza.getHeading(),
        0, 0, 0, 0, 0, 0);
      //Hilfswert T1 für Sats und Gfix
      varioSensor.setData(naza.getAltitude(), naza.getVerticalSpeedIndicator());
      uint32_t satFixData = (naza.getSatellites() * 10) + (uint8_t)naza.getFixType();
      rpmSensor.setData(0, (float)satFixData, 0.0f);

      // LED-Puls starten (GPS-Paket empfangen)
      digitalWrite(LED_BUILTIN, HIGH);
      ledPulseStart = millis();
    }
  }
#endif

  // 2. TIMED ACTIONS (Blinken & Testdaten-Generierung)
  static uint32_t lastUpdate = 0;
  static uint32_t loopCount = 0;

  if (millis() - lastUpdate >= 100UL) {
    lastUpdate = millis();
    loopCount++;

    // LED-Puls beenden (wenn aktiv und Zeit abgelaufen)
    if (ledPulseStart > 0 && millis() - ledPulseStart >= LED_PULSE_DURATION) {
      digitalWrite(LED_BUILTIN, LOW);
      ledPulseStart = 0;
    }

// SIMULATIONS-MODUS (NUR WENN USE_TESTDATA == 1)
#if USE_TESTDATA == 1
    float speedVariation = 5.5f + (sin(loopCount / 10.0f) * 0.5f);
    float altVariation = 100.5f + (sin(loopCount / 20.0f) * 5.0f);
    float vertSpeedVariation = 1.2f + (cos(loopCount / 15.0f) * 0.3f);

    gpsSensor.setData(
      dummyLatitude, dummyLongitude, altVariation, speedVariation, dummyCourse,
      dummyYear, dummyMonth, dummyDay, dummyHour, dummyMinute, dummySecond);

    varioSensor.setData(altVariation, vertSpeedVariation);

    uint32_t testSatFix = (dummySatellites * 10) + dummyFixType;
    rpmSensor.setData(0, (float)testSatFix, 0.0f);

    // LED-Puls starten (Test-Daten generiert)
    if (ledPulseStart == 0) {  // Nur wenn gerade kein Puls aktiv ist
      digitalWrite(LED_BUILTIN, HIGH);
      ledPulseStart = millis();
    }
#endif

// DEBUG-MONITOR AUSGABE (NUR WENN SERIAL_MONITOR == 1)
#if SERIAL_MONITOR == 1
    static uint32_t lastDebug = 0;
    if (millis() - lastDebug >= 500UL) {
      lastDebug = millis();

      Serial.print(F("[TEST] Alt="));
      Serial.print(100.5f + (sin(loopCount / 20.0f) * 5.0f), 1);
      Serial.print(F("m | Satelliten="));
      Serial.print(dummySatellites);
      Serial.print(F(" | Fix="));
      Serial.print(dummyFixType);
      Serial.print(F(" | Loops="));
      Serial.println(loopCount);
    }
#endif
  }

  // Telemetrie an Empfänger senden (muss permanent laufen)
  telemetry.send();
}