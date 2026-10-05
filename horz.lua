-- Künstlicher Horizont für FrSky Sensoren und QX7 (EdgeTX 2.10 BW)

local invPitch = 0
local invRoll  = 0
local invHdg   = 0
local groundMode = 0 -- 0 = White, 1 = Lines, 2 = Points
local filteredAlt = 0
local filteredHdg = 0

-- Menü-Steuerungsvariablen
local menuActive = false
local selectedRow = 1
local menuOpenTime = 0 
local configLoaded = false

-- Speicherpfad im Logs-Systemordner
local configPath = "/LOGS/hrzn_DJI.txt"

local function loadConfig()
    local f = io.open(configPath, "r")
    if f then
        local pStr = io.read(f, 1)
        io.read(f, 1) -- Ueberspringe das "\n"
        local rStr = io.read(f, 1)
        io.read(f, 1) -- Ueberspringe das "\n"
        local hStr = io.read(f, 1)
        io.read(f, 1) -- Ueberspringe das "\n"
        local gStr = io.read(f, 1)
        io.close(f)
        
        invPitch   = tonumber(pStr) or 0
        invRoll    = tonumber(rStr) or 0
        invHdg     = tonumber(hStr) or 0
        groundMode = tonumber(gStr) or 0
    else
        invPitch   = 0
        invRoll    = 0
        invHdg     = 0
        groundMode = 0
    end
    configLoaded = true
end

-- 2. SICHERE SPEICHER-ROUTINE
local function saveConfig()
    local f = io.open(configPath, "w")
    if f then
        io.write(f, tostring(invPitch) .. "\n")
        io.write(f, tostring(invRoll) .. "\n")
        io.write(f, tostring(invHdg) .. "\n")
        io.write(f, tostring(groundMode) .. "\n")
        io.close(f)
    end
end

-- 3. INITIALISIERUNG
local function init()
    menuActive = false
    selectedRow = 1
    menuOpenTime = 0
    configLoaded = false
end

-- 4. HAUPTFUNKTION
local function run(event)
    lcd.clear()

    -- Einmaliges Laden beim allerersten Start des Screens
    if not configLoaded then
        loadConfig()
    end

    -- ============================================================================
    -- TASTEN-ABFRAGE IM MENÜ
    -- ============================================================================
    if menuActive then
        local lockActive = (getTime() - menuOpenTime) < 50

        if not lockActive then
            if event == EVT_MINUS_FIRST or event == EVT_ROT_LEFT then
                selectedRow = selectedRow - 1
                if selectedRow < 1 then selectedRow = 5 end
            elseif event == EVT_PLUS_FIRST or event == EVT_ROT_RIGHT then
                selectedRow = selectedRow + 1
                if selectedRow > 5 then selectedRow = 1 end
            elseif event == EVT_ENTER_BREAK then
                if selectedRow == 1 then invPitch = (invPitch == 0) and 1 or 0
                elseif selectedRow == 2 then invRoll  = (invRoll == 0) and 1 or 0
                elseif selectedRow == 3 then invHdg   = (invHdg == 0) and 1 or 0
                elseif selectedRow == 4 then 
                    -- Schaltet durch: 0 -> 1 -> 2 -> 0
                    groundMode = groundMode + 1
                    if groundMode > 2 then groundMode = 0 end
                elseif selectedRow == 5 then
                    saveConfig()
                    menuActive = false
                end
            end
        end

        -- Menü-Grafik darstellen
        lcd.drawText(1, 2, "-- CONFIG MENU --", INVERS)
        
        local groundText = "White"
        if groundMode == 1 then groundText = "Lines"
        elseif groundMode == 2 then groundText = "Points" end

        lcd.drawText(1, 13, (selectedRow == 1 and "> " or "  ") .. "Pitch Invert: " .. (invPitch == 1 and "YES" or "NO"), selectedRow == 1 and INVERS or 0)
        lcd.drawText(1, 22, (selectedRow == 2 and "> " or "  ") .. "Roll Invert : " .. (invRoll == 1 and "YES" or "NO"), selectedRow == 2 and INVERS or 0)
        lcd.drawText(1, 31, (selectedRow == 3 and "> " or "  ") .. "Hdg Invert  : " .. (invHdg == 1 and "YES" or "NO"), selectedRow == 3 and INVERS or 0)
        lcd.drawText(1, 40, (selectedRow == 4 and "> " or "  ") .. "Ground      : " .. groundText, selectedRow == 4 and INVERS or 0)
        lcd.drawText(1, 51, (selectedRow == 5 and "> " or "  ") .. "     >> SAVE <<", selectedRow == 5 and INVERS or 0)
        
        if lockActive then
            lcd.drawText(1, 57, "[ ..... ]", SMLSIZE)
        end
        return 0
    end

    -- TRIGGER FÜR MENÜ (Langer Druck auf MENU)
    if event == EVT_MENU_LONG then
        menuActive = true
        menuOpenTime = getTime() 
        selectedRow = 1 
    end
    
    -- SPEICHER WERTE
    local pFact = (invPitch == 1) and -1 or 1
    local rFact = (invRoll == 1)  and -1 or 1
    local hFact = (invHdg == 1)   and -1 or 1

    -- SENSOREN ABFRAGEN
    local rssi  = getValue("RSSI") or 0
    local gfix  = getValue("Gfix") or 0
    local sats  = getValue("Sats") or 0
    local dist  = getValue("Dist") or 0
    local vspd  = getValue("VSpd") or 0
    local cmin  = getValue("celD") or 0 
    local amp   = getValue("Curr") or 0
    local gspd  = (getValue("Gspd") or 0) * 1.852

    -- 1. HÖHEN-GLÄTTUNG (Alpha = 0.25)
    local rawAlt = getValue("Alt") or 0
    filteredAlt = (rawAlt * 0.25) + (filteredAlt * 0.75)
    local alt = filteredAlt or 0

    -- Cels Tabellen-Abfrage fuer EdgeTX/OpenTX
    local cels_raw = getValue("Cels") or 0
    local cels = 0
    if type(cels_raw) == "table" then
        for _, cell_volt in ipairs(cels_raw) do
            cels = cels + cell_volt
        end
    else
        cels = tonumber(cels_raw) or 0
    end

    -- ============================================================================
    -- REINE AUSWERTUNG ÜBER ACC-SENSOREN (Keine Ptch/Roll Konflikte mehr!)
    -- Skalierung auf echte 90° korrigiert
    -- ============================================================================
    local pitch = (getValue("AccX") or 0) * 90 * pFact
    local roll  = (getValue("AccY") or 0) * 90 * rFact

    -- 2. HEADING-GLÄTTUNG (Berücksichtigt den 360° auf 0° Umschlag!)
    local rawHdg = (getValue("Hdg") or 0) * hFact
    if rawHdg < 0 then rawHdg = rawHdg + 360 end

    -- Sonderfall für den Kompass: Verhindert wildes Drehen beim Sprung über Nord (359° -> 0°)
    local diff = rawHdg - filteredHdg
    if diff > 180 then diff = diff - 360 end
    if diff < -180 then diff = diff + 360 end
    
    filteredHdg = filteredHdg + (diff * 0.3) 
    local hdg = (filteredHdg % 360 + 360) % 360


    -- GRAFIK-LAYOUT HINTERGRUND
    local cx = 76    
    local sizeW = 26 
    local cy = 35    
    local sizeH = 28 

    -- Horizont-Linie berechnen (Winkel normalisieren auf volle 360 Grad)
    local pitchOffset = math.max(math.min(pitch * 0.6, sizeH - 2), -(sizeH - 2)) 
    local rollAngle = (roll / 57.2957)
    local dx = math.cos(rollAngle) * (sizeW - 1)
    local dy = math.sin(rollAngle) * (sizeW - 1)

    -- Erkennung, ob der Copter auf dem Rücken fliegt (Rollen über 90° oder unter -90°)
    local isUpsideDown = false
    local absRoll = math.abs(roll % 360)
    if absRoll > 90 and absRoll < 270 then
        isUpsideDown = true
    end

    -- HIGH-SPEED BODEN EFFEKTE (Mit echter 360° Rückenflug-Inversion!)
    if groundMode > 0 then
        local startX = cx - sizeW + 1
        local endX = cx + sizeW - 1
        for y = cy - sizeH + 1, cy + sizeH - 1 do
            local xLeft = startX
            local xRight = endX
            
            if dy ~= 0 then
                local intersectX = math.floor(cx + ((y - cy - pitchOffset) * dx) / dy)
                
                -- Die entscheidende Weiche: Wenn überkopf, vertauschen wir links und rechts!
                if (dy > 0 and not isUpsideDown) or (dy < 0 and isUpsideDown) then
                    xRight = math.min(endX, intersectX)
                else
                    xLeft = math.max(startX, intersectX)
                end
            else
                -- Fallback bei genau 0° oder 180° Rollen
                if (pitchOffset >= 0 and not isUpsideDown) or (pitchOffset < 0 and isUpsideDown) then
                    if y <= (cy + pitchOffset) then xLeft = endX + 1 end
                else
                    if y >= (cy + pitchOffset) then xLeft = endX + 1 end
                end
            end
            
            if xLeft <= xRight then
                if groundMode == 1 then
                    if y % 2 == 0 then
                        lcd.drawLine(xLeft, y, xRight, y, SOLID, FORCE)
                    end
                elseif groundMode == 2 then
                    local xStartMod = (xLeft + y) % 2
                    local xLoopStart = xLeft + xStartMod
                    for x = xLoopStart, xRight, 2 do
                        lcd.drawPoint(x, y)
                    end
                end
            end
        end
    end

    -- Rahmenbox und Zentrumskreuz zeichnen
    lcd.drawRectangle(cx - sizeW, cy - sizeH, sizeW * 2, sizeH * 2, FORCE)
    lcd.drawLine(cx - sizeW - 5, cy, cx - sizeW - 1, cy, SOLID, FORCE)
    lcd.drawLine(cx + sizeW + 1, cy, cx + sizeW + 5, cy, SOLID, FORCE)
    
    lcd.drawLine(cx - 2, cy, cx + 2, cy, SOLID, FORCE)
    lcd.drawLine(cx, cy - 2, cx, cy + 2, SOLID, FORCE)

    -- Horizont-Linie zeichnen
    lcd.drawLine(cx - dx, cy - dy + pitchOffset, cx + dx, cy + dy + pitchOffset, SOLID, FORCE)

    -- Höhen-Tick alle 5m am linken Rand der Box
    if alt and sizeH and sizeH > 0 then
        local altTickY = cy + ((alt % 5) * (sizeH / 5)) - (sizeH / 2)
        if altTickY >= (cy - sizeH + 2) and altTickY <= (cy + sizeH - 2) then
            lcd.drawLine(cx - sizeW + 1, altTickY, cx - sizeW + 4, altTickY, SOLID, FORCE)
        end
    end
    
    -- Text-Overlays IN der Box
    -- Satellitenanzahl (5px eingerückt)
    local satX = cx - sizeW + 5
    local satY = cy - sizeH + 2
    lcd.drawText(satX, satY, "S:" .. string.format("%.0f", sats), SMLSIZE)
    
    -- GPS-Fix Modus (Optimiert: Nur 1x aufgerufen)
    local fixStr = "nF"
    if gfix == 3 then fixStr = "3D" elseif gfix == 2 then fixStr = "2D" end
    lcd.drawText(cx + sizeW - 11, satY, fixStr, SMLSIZE)

    -- Höhe in der Box (Zentriert)
    lcd.drawText(cx, cy - 13, string.format("%.0f", alt) .. "m", SMLSIZE + CENTER)

    -- KOMPASS SKALA (Mit Dreiecken & N S O W Buchstaben)
    if hdg and hdg >= 0 and hdg <= 360 then
        local yBottom = cy - sizeH - 1
        lcd.drawPoint(cx, yBottom - 4)
        
        for i = -3, 3 do
            local tickAngle = (math.floor(hdg / 10) + i) * 10
            local normalizedAngle = (tickAngle % 360 + 360) % 360
            
            local diff = tickAngle - hdg
            if diff > 180 then diff = diff - 360 end
            if diff < -180 then diff = diff + 360 end

            local tickX = cx + (diff * 0.75)
            if tickX >= (cx - sizeW) and tickX <= (cx + sizeW) and tickX >= 0 and tickX <= 128 then
                if normalizedAngle % 90 == 0 then
                    lcd.drawLine(tickX - 1, yBottom - 6, tickX + 1, yBottom - 6, SOLID, FORCE)
                    lcd.drawLine(tickX,     yBottom - 5, tickX,     yBottom - 4, SOLID, FORCE)
                    local letter = ""
                    if normalizedAngle == 0 or normalizedAngle == 360 then letter = "N"
                    elseif normalizedAngle == 90 then letter = "O"
                    elseif normalizedAngle == 180 then letter = "S"
                    elseif normalizedAngle == 270 then letter = "W"
                    end
                    lcd.drawText(tickX - 2, yBottom - 3, letter, SMLSIZE)
                elseif normalizedAngle % 30 == 0 then
                    lcd.drawLine(tickX, yBottom - 4, tickX, yBottom, SOLID, FORCE)
                else
                    lcd.drawLine(tickX, yBottom - 2, tickX, yBottom, SOLID, FORCE)
                end
            end
        end
    end

    -- LINKER TEXTBLOCK (Navigationsdaten)
    lcd.drawText(1, 2,  "RSSI: " .. string.format("%d", rssi) .. "dB", SMLSIZE)
    lcd.drawText(1, 13, "Alt : " .. string.format("%.0f", alt) .. "m", SMLSIZE)
    lcd.drawText(1, 24, "Spd:" .. string.format("%.0f", gspd) .. "km/h", SMLSIZE)
    lcd.drawText(1, 35, "Dist: " .. string.format("%.0f", dist) .. "m", SMLSIZE)
    lcd.drawText(1, 46, "VSpd:" .. string.format("%.0f", vspd) .. "m/s", SMLSIZE)
    lcd.drawText(1, 57, "Hdg : " .. string.format("%03d", hdg) .. "°", SMLSIZE)

    -- RECHTER TEXTBLOCK (Akkukennwerte)    
    local rx = 104
    local rEdge = 127    
    lcd.drawText(rx+3, 1,  "Batt:", SMLSIZE)
    lcd.drawText(rEdge, 9, string.format("%.1f", cels) .. "V", SMLSIZE + RIGHT)
    lcd.drawText(rx, 19, "CellD:", SMLSIZE)
    lcd.drawText(rEdge, 27, string.format("%.2f", cmin) .. "V", SMLSIZE + RIGHT)
    lcd.drawText(rx+4, 36, " Amp:", SMLSIZE)
    lcd.drawText(rEdge, 43, string.format("%.1f", amp) .. "A", SMLSIZE + RIGHT)
    lcd.drawText(rEdge, 51, string.format("%.0f", pitch) .. "°=Y", SMLSIZE + RIGHT)
    lcd.drawText(rEdge+1, 58, string.format("%.0f", roll)  .. "°=X", SMLSIZE + RIGHT)

    return 0
end

return { init=init, run=run }
