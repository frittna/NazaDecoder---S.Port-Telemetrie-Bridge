-- LUA Skript für OpenTX/EdgeTX passend zu "NazaSmartPort_Arduino-328P.ino" (mein Nazadecoder zu FrSky S.Port-Sensor Projekt) 
-- um den Hilfswert T1 (über RPM Sensor) zurück in Sats und Gfix zu wandeln welche im FrSky Paket nicht enthalten sind.  @frittna 1.Okt.2026
-- in den SCRIPTS\FUNCTIONS Ordner am Sender kopieren und mit Spezialfunktionen -> wenn Act (Sender aktiv), starte lua skript, programmieren.
local satSensor, fixSensor

local function init()    
    satSensor = sportTelemetry.getSensor(0x5100) or sportTelemetry.createSensor(0x5100, "Sats", 0)
    fixSensor = sportTelemetry.getSensor(0x5101) or sportTelemetry.createSensor(0x5101, "GFix", 0)
end

local function background()
    local t1Value = getValue("T1")

    if t1Value then
        local sats = math.floor(t1Value / 10) 
        local fix  = t1Value % 10             

        satSensor:setValue(sats)
        fixSensor:setValue(fix)
    else
        -- Wenn Empfänger aus dann = 0
        satSensor:setValue(0)
        fixSensor:setValue(0)
    end
end

local function run()
    return 0
end

return { init = init, background = background, run = run }
