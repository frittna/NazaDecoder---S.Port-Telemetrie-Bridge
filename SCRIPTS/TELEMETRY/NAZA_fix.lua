-- LUA Skript für OpenTX/EdgeTX passend zu "NazaSmartPort_Arduino-328P.ino" (mein Nazadecoder zu FrSky S.Port-Sensor Projekt) 
-- um den Hilfswert T1 (über RPM Sensor) zurück in Sats und Gfix zu wandeln welche im FrSky Paket nicht enthalten sind.  @frittna 1.Okt.2026
-- in den SCRIPTS\FUNCTIONS Ordner am Sender kopieren und mit Spezialfunktionen -> wenn Act (Sender aktiv), starte lua skript, programmieren.
local satSensor, fixSensor
-- Die init-Funktion läuft einmal beim Laden des Modells
local function init()
    satSensor = sportTelemetry.getSensor(0x5100) or sportTelemetry.createSensor(0x5100, "Sats", 0)
    fixSensor = sportTelemetry.getSensor(0x5101) or sportTelemetry.createSensor(0x5101, "GFix", 0)
end

-- Diese Funktion läuft IMMER im Hintergrund
local function background()
    local t1Value = getValue("T1")

    if t1Value and t1Value > 0 then
        local sats = math.floor(t1Value / 10) 
        local fix  = t1Value % 10             

        satSensor:setValue(sats)
        fixSensor:setValue(fix)
    end
end

-- Die run-Funktion wird nur aufgerufen, WENN man die Telemetrieseite aktiv anschaut
local function run()
    -- Da wir keine Anzeige brauchen, lassen wir sie leer
    return 0
end

return { init = init, background = background, run = run }
