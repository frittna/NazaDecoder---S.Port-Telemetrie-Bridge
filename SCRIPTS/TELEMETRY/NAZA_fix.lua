-- LUA Skript für OpenTX/EdgeTX passend zu "NazaSmartPort_Arduino-328P.ino" (mein Nazadecoder zu FrSky S.Port-Sensor Projekt) 
-- um den Hilfswert T1 (über RPM Sensor) zurück in Sats und Gfix zu wandeln welche im FrSky Paket nicht enthalten ist.  @frittna 1.Okt.2026

local satSensor = sportTelemetry.getSensor(0x5100) or sportTelemetry.createSensor(0x5100, "Sats", 0)
local fixSensor = sportTelemetry.getSensor(0x5101) or sportTelemetry.createSensor(0x5101, "GFix", 0)

local function run()
    -- 1. kombinierten Wert von T1 einlesen
    local t1Value = getValue("T1")

    -- 2. nur rechnen, wenn ein gültiger Wert vorhanden ist
    if t1Value and t1Value > 0 then
        -- trennen (Beispiel: 123)
        local sats = math.floor(t1Value / 10) -- Ergibt 12
        local fix  = t1Value % 10             -- Ergibt 3

        -- 3. neuen Wert in virtuellen Sensor schreiben
        satSensor:setValue(sats)
        fixSensor:setValue(fix)
    end
    
    return 0
end

return { run = run }
