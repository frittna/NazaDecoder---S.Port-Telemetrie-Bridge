#include <Wire.h>

// Die I2C-Adresse, die wir über Pin 9 (AD0 -> GND) erzwungen haben
#define MPU_ADDR 0x68  

// Standard-I2C Pins für den externen M5Stack Port A (Grove)
#define I2C_SDA 21
#define I2C_SCL 22

void setup() {
  Serial.begin(115200);
  while (!Serial); // Warten auf seriellen Monitor
  
  Serial.println("\n=== M5Stack I2C & MPU-Test startet ===");

  // I2C-Bus explizit mit den M5Stack-Pins initialisieren
  Wire.begin(I2C_SDA, I2C_SCL);

  // --- SCHRITT 1: I2C-SCANNER ---
  Serial.print("Scanne I2C-Bus... ");
  Wire.beginTransmission(MPU_ADDR);
  byte error = Wire.endTransmission();

  if (error == 0) {
    Serial.println("ERFOLG! Sensor unter Adresse 0x68 gefunden.");
  } else {
    Serial.print("FEHLER! Kein Gerät unter 0x68. Fehlercode: ");
    Serial.println(error);
    Serial.println("-> Bitte Lötbrücken (Pin 8 zu 3.3V / Pin 9 zu GND) und Kabel prüfen.");
    while(1); // Stop bei Fehler
  }

  // --- SCHRITT 2: SENSOR AUFWECKEN ---
  // Das Power-Management-Register (0x6B) muss auf 0 gesetzt werden,
  // da die MPU standardmäßig im Schlafmodus (Sleep Mode) startet!
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B); 
  Wire.write(0);    // Aufwecken!
  Wire.endTransmission(true);
  Serial.println("Sensor erfolgreich aufgeweckt.");
  delay(100);
}

void loop() {
  // --- SCHRITT 3: ROHDATEN AUSLESEN ---
  // Wir starten ab Register 0x3B (Accelerometer X-Achse High-Byte)
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);
  Wire.endTransmission(false);
  
  // 14 Bytes anfordern (6 Bytes Accel, 2 Bytes Temp, 6 Bytes Gyro)
  Wire.requestFrom(MPU_ADDR, 14, true);
  
  if(Wire.available() >= 14) {
    // Bits zusammenschieben (High-Byte << 8 | Low-Byte)
    int16_t accX = (Wire.read() << 8) | Wire.read();
    int16_t accY = (Wire.read() << 8) | Wire.read();
    int16_t accZ = (Wire.read() << 8) | Wire.read();
    int16_t temp = (Wire.read() << 8) | Wire.read();
    int16_t gyroX = (Wire.read() << 8) | Wire.read();
    int16_t gyroY = (Wire.read() << 8) | Wire.read();
    int16_t gyroZ = (Wire.read() << 8) | Wire.read();

    // Temperatur in Grad Celsius umrechnen laut Datenblatt Formula
    float celsius = (temp / 340.0) + 36.53;

    // Ausgabe im Seriellen Monitor
    Serial.print("ACC -> X: "); Serial.print(accX);
    Serial.print(" | Y: "); Serial.print(accY);
    Serial.print(" | Z: "); Serial.print(accZ);
    Serial.print("  ||  GYRO -> X: "); Serial.print(gyroX);
    Serial.print(" | Y: "); Serial.print(gyroY);
    Serial.print(" | Z: "); Serial.print(gyroZ);
    Serial.print("  ||  Temp: "); Serial.print(celsius, 1);
    Serial.println(" °C");
  }

  delay(200); // Alle 200ms aktualisieren
}
