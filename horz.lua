-- Künstlicher Horizont für FrSky Sensoren und QX7 (EdgeTX 2.10 BW)

local invPitch = 0
local invRoll  = 0
local invHdg   = 0

-- Menü-Steuerungsvariablen
local menuActive = false
local selectedRow = 1
local menuOpenTime = 0 
local configLoaded = false

-- Speicherpfad im Logs-Systemordner
local configPath = "/LOGS/hrzn_cfg.txt"

local function loadConfig()
    local f = io.open(configPath, "r")
    if f then
        -- 1 Zeichen lesen ("1"), springen ueber den Umbruch, und lesen das naechste Zeichen
        local pStr = io.read(f, 1)
        io.read(f, 1) -- Ueberspringe das "\n"
        local rStr = io.read(f, 1)
        io.read(f, 1) -- Ueberspringe das "\n"
        local hStr = io.read(f, 1)
        io.close(f)
        
        invPitch = tonumber(pStr) or 0
        invRoll  = tonumber(rStr) or 0
        invHdg   = tonumber(hStr) or 0
    else
        invPitch = 0
        invRoll  = 0
        invHdg   = 0
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
                if selectedRow < 1 then selectedRow = 4 end
            elseif event == EVT_PLUS_FIRST or event == EVT_ROT_RIGHT then
                selectedRow = selectedRow + 1
                if selectedRow > 4 then selectedRow = 1 end
            elseif event == EVT_ENTER_BREAK then
                if selectedRow == 1 then invPitch = (invPitch == 0) and 1 or 0
                elseif selectedRow == 2 then invRoll  = (invRoll == 0) and 1 or 0
                elseif selectedRow == 3 then invHdg   = (invHdg == 0) and 1 or 0
                elseif selectedRow == 4 then
                    saveConfig()
                    menuActive = false
                end
            end
        end

        -- Menü-Grafik darstellen
        lcd.drawText(1, 2, "-- MENU: INVERT AXIS ? --", INVERS)
        
        if selectedRow == 1 then
            lcd.drawText(1, 16, ">     Pitch Invert: " .. (invPitch == 1 and "YES" or "NO"), INVERS)
        else
            lcd.drawText(1, 16, "      Pitch Invert: " .. (invPitch == 1 and "YES" or "NO"), 0)
        end
        
        if selectedRow == 2 then
            lcd.drawText(1, 26, ">     Roll Invert : " .. (invRoll == 1 and "YES" or "NO"), INVERS)
        else
            lcd.drawText(1, 26, "      Roll Invert : " .. (invRoll == 1 and "YES" or "NO"), 0)
        end
        
        if selectedRow == 3 then
            lcd.drawText(1, 36, ">     Hdg Invert  : " .. (invHdg == 1 and "YES" or "NO"), INVERS)
        else
            lcd.drawText(1, 36, "      Hdg Invert  : " .. (invHdg == 1 and "YES" or "NO"), 0)
        end

        if selectedRow == 4 then
            lcd.drawText(1, 48, ">          >> SAVE <<", INVERS)
        else
            lcd.drawText(1, 48, "           >> SAVE <<", 0)
        end
        
        if lockActive then
            lcd.drawText(1, 56, "[ ..... ]", SMLSIZE)
        end
        return 0
    end

    -- TRIGGER FÜR MENÜ (Langer Druck auf MENU)
    if event == EVT_MENU_LONG then
        menuActive = true
        menuOpenTime = getTime() 
        selectedRow = 1 
    end

    -- FAKTOREN-ZWEISUNG BASIEREND ON SPEICHERWERTEN
    local pFact = (invPitch == 1) and -1 or 1
    local rFact = (invRoll == 1)  and -1 or 1
    local hFact = (invHdg == 1)   and -1 or 1

    -- Sensoren abfragen (Ptch/Roll oder Fallback auf G-Kräfte)
    local pitch = getValue("Ptch") or 0
    local roll  = getValue("Roll") or 0
    if pitch == 0 and roll == 0 then
        pitch = (getValue("AccX") or 0) * 45 * pFact
        roll  = (getValue("AccY") or 0) * 45 * rFact
    else
        pitch = pitch * pFact
        roll  = roll * rFact
    end

    local hdg   = (getValue("Hdg") or 0) * hFact
    if hdg < 0 then hdg = hdg + 360 end
    
    local dist  = getValue("Dist") or 0
    local alt   = getValue("GAlt") or getValue("Alt") or 0
    local rssi  = getValue("RSSI") or 0
    local sats  = getValue("Tmp1") or getValue("Sats") or 0
    
    -- Cels Tabellen-Abfrage fuer EdgeTX/OpenTX
    local cels_raw = getValue("Cels") or 0
    local cels = 0
    if type(cels_raw) == "table" then
        -- Wenn es eine Tabelle ist, addieren wir alle Einzelzellen zur Gesamtspannung auf
        for _, cell_volt in ipairs(cels_raw) do
            cels = cels + cell_volt
        end
    else
        -- Fallback, falls es ein reiner Zahlenwert oder 0 ist
        cels = tonumber(cels_raw) or 0
    end

    local cmin  = getValue("cell-min") or 0 
    local gfix  = getValue("Tmp2") or 0
    local amp   = getValue("Curr") or 0
    local vspd  = getValue("VSpd") or 0

    -- GRAFIK-LAYOUT HINTERGRUND
    local cx = 76    
    local sizeW = 26 
    local cy = 35    
    local sizeH = 28 

    -- Rahmenbox zeichnen
    lcd.drawRectangle(cx - sizeW, cy - sizeH, sizeW * 2, sizeH * 2, FORCE)
    lcd.drawLine(cx - sizeW - 5, cy, cx - sizeW - 1, cy, SOLID, FORCE)
    lcd.drawLine(cx + sizeW + 1, cy, cx + sizeW + 5, cy, SOLID, FORCE)
    
    -- Senkrechtes 4x4 Pixel Kreuz als Zentrumspunkt
    lcd.drawLine(cx - 2, cy, cx + 2, cy, SOLID, FORCE)
    lcd.drawLine(cx, cy - 2, cx, cy + 2, SOLID, FORCE)

    -- Horizont-Linie berechnen & zeichnen
    local pitchOffset = math.max(math.min(pitch * 0.6, sizeH - 2), -(sizeH - 2)) 
    local rollAngle = (roll / 57.2957)
    local dx = math.cos(rollAngle) * (sizeW - 1)
    local dy = math.sin(rollAngle) * (sizeW - 1)
    lcd.drawLine(cx - dx, cy - dy + pitchOffset, cx + dx, cy + dy + pitchOffset, SOLID, FORCE)
    
    -- Höhen-Wert alle 5m als Strich am linken inneren Rand der Box
    if alt and sizeH and sizeH > 0 then
        local altTickY = cy + ((alt % 5) * (sizeH / 5)) - (sizeH / 2)
        if altTickY >= (cy - sizeH + 2) and altTickY <= (cy + sizeH - 2) then
            lcd.drawLine(cx - sizeW + 1, altTickY, cx - sizeW + 4, altTickY, SOLID, FORCE)
        end
    end

    -- Sats als S: links oben in Box
    lcd.drawText(cx - sizeW + 2, cy - sizeH + 2, "S:" .. string.format("%.0f", sats), SMLSIZE)

    -- 2D oder 3D Fix-Typ rechts oben in Box
    local fixStr = "0D"
    if gfix == 3 then fixStr = "3D" elseif gfix == 2 then fixStr = "2D" end
    lcd.drawText(cx + sizeW - 11, cy - sizeH + 2, fixStr, SMLSIZE)

    -- Fluglagewinkel Y und X IN die Box links und rechts mittig legen
    lcd.drawText(cx - sizeW + 2, cy +20, "Y:" .. string.format("%.0f", pitch), SMLSIZE)
    lcd.drawText(cx + sizeW - 18, cy +20, "X:" .. string.format("%.0f", roll), SMLSIZE)

    -- KOMPASS SKALA
    if hdg and hdg >= 0 and hdg <= 360 then
        local yBottom = cy - sizeH - 1
        lcd.drawPoint(cx, yBottom - 4)
        for i = -3, 3 do
            local tickAngle = (math.floor(hdg / 10) + i) * 10
            local diff = tickAngle - hdg
            if diff > 180 then diff = diff - 360 end
            if diff < -180 then diff = diff + 360 end

            local tickX = cx + (diff * 0.75)
            if tickX >= (cx - sizeW) and tickX <= (cx + sizeW) and tickX >= 0 and tickX <= 128 then
                if tickAngle % 90 == 0 then
                    lcd.drawLine(tickX, yBottom - 6, tickX, yBottom, SOLID, FORCE)
                elseif tickAngle % 30 == 0 then
                    lcd.drawLine(tickX, yBottom - 4, tickX, yBottom, SOLID, FORCE)
                else
                    lcd.drawLine(tickX, yBottom - 2, tickX, yBottom, SOLID, FORCE)
                end
            end
        end
    end

    -- LINKER TEXTBLOCK (Navigationsdaten)
    lcd.drawText(1, 2,  "RSSI: " .. string.format("%d", rssi) .. "dB", SMLSIZE)
    lcd.drawText(1, 13, "Sats: " .. string.format("%.0f", sats), SMLSIZE)
    lcd.drawText(1, 24, "Alt :  " .. string.format("%.0f", alt) .. "m", SMLSIZE)
    lcd.drawText(1, 35, "Dist: " .. string.format("%.0f", dist) .. "m", SMLSIZE)
    lcd.drawText(1, 46, "VSpd:" .. string.format("%.0f", vspd) .. "kmh", SMLSIZE)
    lcd.drawText(1, 57, "Hdg : " .. string.format("%03d", hdg) .. "°", SMLSIZE)

    -- RECHTER TEXTBLOCK (Akkukennwerte)
    local rx = 104
    lcd.drawText(rx, 2,  "Batt:", SMLSIZE)
    lcd.drawText(rx, 10, string.format("%.1f", cels) .. "V", SMLSIZE)
    lcd.drawText(rx, 20, "CelD:", SMLSIZE)
    lcd.drawText(rx, 28, string.format("%.2f", cmin) .. "V", SMLSIZE)
    lcd.drawText(rx, 48, "Amp:", SMLSIZE)
    lcd.drawText(rx, 56, string.format("%.1f", amp) .. "A", SMLSIZE)

    return 0
end

return { init=init, run=run }
