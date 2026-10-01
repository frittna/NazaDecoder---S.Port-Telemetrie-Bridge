// NazaDecoder - S.Port Telemetrie Bridge 
// Naza-M V1/V2 to FrSky SmartPort - Arduino
// -> integriert die GPS- und Magn.-Daten vom DJI Naza-M V1/V2 in den FrSky SmartPort Telemetrie-Datenkanal S.Port.

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
uint8_t dummyYear = 26;
uint8_t dummyMonth = 9;
uint8_t dummyDay = 26;
uint8_t dummyHour = 14;
uint8_t dummyMinute = 35;
uint8_t dummySecond = 0;
uint8_t dummySatellites = 9;
uint8_t dummyFixType = 3;
#endif

// ============================================================================
// SETUP
// ============================================================================
void setup() {

  // KORREKTUR: Zuerst den Pin als Ausgang definieren!
  pinMode(LED_BUILTIN, OUTPUT);

  // Status-LED 2x kurz blinken lassen (Start-Up)
  digitalWrite(LED_BUILTIN, HIGH);
  delay(130);
  digitalWrite(LED_BUILTIN, LOW);
  delay(130);
  digitalWrite(LED_BUILTIN, HIGH);
  delay(130);
  digitalWrite(LED_BUILTIN, LOW);
  delay(500); // Kürzere Pause nach dem Startblinken

  // Initialisiert die serielle Hardware-Schnittstelle (115200 Baud)
  Serial.begin(115200);
  delay(500);

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

  // SmartPort initialisieren
  telemetry.begin(
    FrSkySportSingleWireSerial::SOFT_SERIAL_PIN_7,
    &gpsSensor,
    &varioSensor,
    &rpmSensor);

#if SERIAL_DEBUG == 1
  Serial.println(F("SmartPort erfolgreich initialisiert!"));
  Serial.println();
#else
  // Wenn Live-Daten aktiv sind, leeren wir den TX-Puffer
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

    if (msgType == NazaDecoder::NAZA_MESSAGE_GPS_TYPE) {
      gpsSensor.setData(
        naza.getLatitude(), naza.getLongitude(), naza.getAltitude(),
        naza.getSpeed(), naza.getHeading(),
        0, 0, 0, 0, 0, 0);

      varioSensor.setData(naza.getAltitude(), naza.getVerticalSpeedIndicator());
      
      // Hilfswert T1 für Sats und GFix berechnen
      uint32_t satFixData = (naza.getSatellites() * 10) + (uint8_t)naza.getFixType();
      rpmSensor.setData(0, (float)satFixData, 0.0f);

      // LED-Puls starten (GPS-Paket empfangen)
      digitalWrite(LED_BUILTIN, HIGH);
      ledPulseStart = millis();
    }
  }
#endif

  // KORREKTUR: LED-Puls-Ausschaltkontrolle direkt im loop() platzieren!
  // Läuft jetzt komplett unabhängig vom 100ms-Intervall und reagiert sofort nach Ablauf der 50ms.
  if (ledPulseStart > 0 && (millis() - ledPulseStart >= LED_PULSE_DURATION)) {
    digitalWrite(LED_BUILTIN, LOW);
    ledPulseStart = 0;
  }

  // 2. TIMED ACTIONS (Intervall-Aktionen)
  static uint32_t lastUpdate = 0;
  static uint32_t loopCount = 0;

  if (millis() - lastUpdate >= 100UL) {
    lastUpdate = millis();
    loopCount++;

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

    // LED-Puls starten im Testmodus (falls nicht aktiv)
    if (ledPulseStart == 0) {
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

  // Telemetrie an Empfänger senden (muss permanent und ungedrosselt laufen)
  telemetry.send();
}
