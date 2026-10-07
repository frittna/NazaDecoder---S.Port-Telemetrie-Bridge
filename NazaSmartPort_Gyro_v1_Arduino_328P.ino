// NazaDecoder - S.Port Telemetrie Bridge                                                   @frittna 7.Okt.2026
// Naza-M V1/V2 to FrSky SmartPort - Arduino + MPU6000/MPU6050 Gyro-Chip
// Lagewerte als gefilterter Gravitationsvektor; Heading kommt weiterhin von der Naza.
// Eigenständiger Sketch; nicht zusammen mit der Basis-Skizze kompilieren.

#include <Arduino.h>
#include <Wire.h>
#include <FrSkySportSensor.h>
#include <FrSkySportSensorGps.h>
#include <FrSkySportSensorVario.h>
#include <FrSkySportSensorRpm.h>
#include <FrSkySportTelemetry.h>
#include <FrSkySportSingleWireSerial.h>
#include <NazaDecoder.h>

// Montageanpassung: Index 0/1/2 = gX/gY/gZ; Vorzeichen nach Bedarf ändern.
// SPORT-Z folgt dem fusionierten Schwerkraftvektor: bei Modell-Level etwa -1 g.
#define SPORT_X_SOURCE 0
#define SPORT_X_SIGN 1
#define SPORT_Y_SOURCE 1
#define SPORT_Y_SIGN 1
#define SPORT_Z_SOURCE 2
#define SPORT_Z_SIGN 1
// Der Empfänger zeigt bei 100 bisher nur etwa 0,1 g; 1000 liefert den vollen g-Wert.
#define ACC_SPORT_SCALE 1000.0f
#define PITCH_GYRO_SIGN 1
#define ROLL_GYRO_SIGN 1

#undef LED_BUILTIN
#define LED_BUILTIN 9
#define MPU_ADDR 0x68
#define USE_TESTDATA 0
#define SERIAL_MONITOR 0

// Diese SmartPort-IDs bilden die von horz.lua gelesenen AccX/AccY/AccZ-Sensoren.
static const uint8_t ACC_SENSOR_ID = 0x1B;
static const uint16_t ACC_X_DATA_ID = 0x0700;
static const uint16_t ACC_Y_DATA_ID = 0x0710;
static const uint16_t ACC_Z_DATA_ID = 0x0720;

class FrSkySportSensorAccCustom : public FrSkySportSensor {
public:
  FrSkySportSensorAccCustom()
    : FrSkySportSensor((FrSkySportSensor::SensorId)ACC_SENSOR_ID),
      accXData(0), accYData(0), accZData(0), sendStage(0) {}

  void setData(float accX, float accY, float accZ) {
    accXData = (int32_t)(accX * ACC_SPORT_SCALE);
    accYData = (int32_t)(accY * ACC_SPORT_SCALE);
    accZData = (int32_t)(accZ * ACC_SPORT_SCALE);
  }

  virtual uint16_t send(FrSkySportSingleWireSerial& serial, uint8_t id, uint32_t now) {
    (void)now;
    if (id != sensorId) return 0;
    switch (sendStage) {
      case 0:
        serial.sendData(ACC_X_DATA_ID, accXData);
        sendStage = 1;
        return ACC_X_DATA_ID;
      case 1:
        serial.sendData(ACC_Y_DATA_ID, accYData);
        sendStage = 2;
        return ACC_Y_DATA_ID;
      default:
        serial.sendData(ACC_Z_DATA_ID, accZData);
        sendStage = 0;
        return ACC_Z_DATA_ID;
    }
  }

private:
  int32_t accXData, accYData, accZData;
  uint8_t sendStage;
};

FrSkySportSensorGps gpsSensor;
FrSkySportSensorVario varioSensor;
FrSkySportSensorRpm rpmSensor;
FrSkySportSensorAccCustom gyroSensor;
FrSkySportTelemetry telemetry;
NazaDecoder naza;

static const uint32_t GYRO_WARMUP_TIME = 25000UL;
static const uint32_t MPU_UPDATE_INTERVAL = 40UL;
static uint32_t systemStartTime = 0;
static uint32_t warmupCompleteLedStart = 0;
static uint32_t ledPulseStart = 0;
static uint32_t lastUpdate = 0;
static uint32_t lastFilterTime = 0;
static const uint32_t LED_PULSE_DURATION = 50UL;
static const uint32_t WARMUP_LED_DURATION = 1500UL;
static bool gyroWarmedUp = false;
static bool angleInitialized = false;
static float anglePitch = 0.0f;
static float angleRoll = 0.0f;

#if USE_TESTDATA == 1
float dummyLatitude = 48.8584f;
float dummyLongitude = 2.2945f;
float dummyAltitude = 100.5f;
float dummySpeed = 5.5f;
float dummyCourse = 45.0f;
float dummyVertSpeed = 1.2f;
uint8_t dummySatellites = 9;
uint8_t dummyFixType = 3;
uint8_t dummyYear = 26;
uint8_t dummyMonth = 9;
uint8_t dummyDay = 26;
uint8_t dummyHour = 14;
uint8_t dummyMinute = 35;
uint8_t dummySecond = 0;
#endif

static void writeMpuRegister(uint8_t reg, uint8_t value) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.write(value);
  Wire.endTransmission(true);
}

static int16_t readMpuWord() {
  const uint16_t highByte = (uint8_t)Wire.read();
  const uint16_t lowByte = (uint8_t)Wire.read();
  return (int16_t)((highByte << 8) | lowByte);
}

static float wrapAngle(float angle) {
  while (angle > 180.0f) angle -= 360.0f;
  while (angle < -180.0f) angle += 360.0f;
  return angle;
}

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, HIGH);
  delay(130);
  digitalWrite(LED_BUILTIN, LOW);
  delay(130);
  digitalWrite(LED_BUILTIN, HIGH);
  delay(130);
  digitalWrite(LED_BUILTIN, LOW);
  delay(500);

  Serial.begin(115200);
  Wire.begin();
  Wire.setClock(400000);
  writeMpuRegister(0x6B, 0x00);  // MPU aufwecken
  writeMpuRegister(0x1C, 0x00);  // Beschleunigung: +/-2 g (16384 LSB/g)
  writeMpuRegister(0x1B, 0x00);  // Gyro: +/-250 Grad/s (131 LSB/(Grad/s))

  telemetry.begin(
    FrSkySportSingleWireSerial::SOFT_SERIAL_PIN_7,
    &gpsSensor, &varioSensor, &rpmSensor, &gyroSensor);

  systemStartTime = millis();
  lastFilterTime = systemStartTime;
  lastUpdate = systemStartTime;
  Serial.flush();
}

void loop() {
#if USE_TESTDATA == 0
  while (Serial.available() > 0) {
    uint8_t msgType = naza.decode(Serial.read());
    if (msgType == NazaDecoder::NAZA_MESSAGE_GPS_TYPE) {
      gpsSensor.setData(naza.getLatitude(), naza.getLongitude(), naza.getAltitude(),
                        naza.getSpeed(), naza.getHeading(), naza.getYear(),
                        naza.getMonth(), naza.getDay(), naza.getHour(),
                        naza.getMinute(), naza.getSecond());
      varioSensor.setData(naza.getAltitude(), naza.getVerticalSpeedIndicator());
      rpmSensor.setData(0, (float)naza.getSatellites(), (float)naza.getFixType());
      digitalWrite(LED_BUILTIN, HIGH);
      ledPulseStart = millis();
    }
  }
#endif

  const uint32_t now = millis();
  if (ledPulseStart > 0 && now - ledPulseStart >= LED_PULSE_DURATION) {
    if (warmupCompleteLedStart == 0 || now - warmupCompleteLedStart >= WARMUP_LED_DURATION) {
      digitalWrite(LED_BUILTIN, LOW);
      ledPulseStart = 0;
    }
  }
  if (warmupCompleteLedStart > 0 && now - warmupCompleteLedStart >= WARMUP_LED_DURATION) {
    digitalWrite(LED_BUILTIN, LOW);
    warmupCompleteLedStart = 0;
  }

  if (now - lastUpdate >= MPU_UPDATE_INTERVAL) {
    lastUpdate = now;
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(0x3B);
    Wire.endTransmission(false);
    Wire.requestFrom(MPU_ADDR, (uint8_t)14, (uint8_t)true);
    if (Wire.available() >= 14) {
      const int16_t accRawX = readMpuWord();
      const int16_t accRawY = readMpuWord();
      const int16_t accRawZ = readMpuWord();
      const int16_t tempRaw = readMpuWord();
      const int16_t gyroRawX = readMpuWord();
      const int16_t gyroRawY = readMpuWord();
      const int16_t gyroRawZ = readMpuWord();
      (void)tempRaw;
      (void)gyroRawZ;

      const float accX = (float)accRawX / 16384.0f;
      const float accY = (float)accRawY / 16384.0f;
      const float accZ = (float)accRawZ / 16384.0f;
      const float accPitch = atan2f(-accX, sqrtf(accY * accY + accZ * accZ)) * 57.2957795f;
      const float accRoll = atan2f(accY, accZ) * 57.2957795f;
      const uint32_t filterNow = millis();
      const float dt = (float)(filterNow - lastFilterTime) / 1000.0f;
      lastFilterTime = filterNow;

      if (!angleInitialized || dt <= 0.0f || dt > 0.25f) {
        anglePitch = accPitch;
        angleRoll = accRoll;
        angleInitialized = true;
      } else {
        const float gyroPitchRate = ((float)gyroRawY / 131.0f) * PITCH_GYRO_SIGN;
        const float gyroRollRate = ((float)gyroRawX / 131.0f) * ROLL_GYRO_SIGN;
        const float alpha = 0.98f;
        anglePitch = alpha * (anglePitch + gyroPitchRate * dt) + (1.0f - alpha) * accPitch;
        angleRoll = wrapAngle(angleRoll + alpha * gyroRollRate * dt +
                              (1.0f - alpha) * wrapAngle(accRoll - angleRoll));
      }

      const float pitchRad = anglePitch * 0.01745329252f;
      const float rollRad = angleRoll * 0.01745329252f;
      // Fusion erzeugt die kanonische Schwerkraft mit negativem Z bei Modell-Level.
      const float gravity[3] = {
        -sinf(pitchRad),
        sinf(rollRad) * cosf(pitchRad),
        -cosf(rollRad) * cosf(pitchRad)
      };
      const float outX = gravity[SPORT_X_SOURCE] * SPORT_X_SIGN;
      const float outY = gravity[SPORT_Y_SOURCE] * SPORT_Y_SIGN;
      const float outZ = gravity[SPORT_Z_SOURCE] * SPORT_Z_SIGN;
      gyroSensor.setData(outX, outY, outZ);
    }
  }

  if (!gyroWarmedUp && now - systemStartTime >= GYRO_WARMUP_TIME) {
    gyroWarmedUp = true;
    warmupCompleteLedStart = now;
    digitalWrite(LED_BUILTIN, HIGH);
  }

#if USE_TESTDATA == 1
  static uint32_t loopCount = 0;
  static uint32_t lastTestUpdate = 0;
  if (now - lastTestUpdate >= 40UL) {
    lastTestUpdate = now;
    loopCount++;
    const float speedVariation = dummySpeed + sinf(loopCount / 10.0f) * 0.5f;
    const float altVariation = dummyAltitude + sinf(loopCount / 20.0f) * 5.0f;
    const float vertSpeedVariation = dummyVertSpeed + cosf(loopCount / 15.0f) * 0.3f;
    gpsSensor.setData(dummyLatitude, dummyLongitude, altVariation, speedVariation, dummyCourse,
                      dummyYear, dummyMonth, dummyDay, dummyHour, dummyMinute, dummySecond);
    varioSensor.setData(altVariation, vertSpeedVariation);
    rpmSensor.setData(0, (float)dummySatellites, (float)dummyFixType);
    if (ledPulseStart == 0) {
      digitalWrite(LED_BUILTIN, HIGH);
      ledPulseStart = now;
    }
  }
#endif

#if SERIAL_MONITOR == 1
  static uint32_t lastDebug = 0;
  if (now - lastDebug >= 500UL) {
    lastDebug = now;
    Serial.print(F("Pitch="));
    Serial.print(anglePitch, 1);
    Serial.print(F(" Roll="));
    Serial.println(angleRoll, 1);
  }
#endif
  telemetry.send();
}
