-- Künstlicher Horizont für FrSky Sensoren (QX7 - EdgeTX 2.10/2.11 BW Display) --  		       @frittna 06.Okt.2026
---> Das LUA Script ist entsanden mit dem Projekt https://github.com

local invPitch     = 0
local invRoll      = 0
local invHdg       = 0
local groundMode   = 0
local filteredAlt  = 0
local filteredHdg  = 0

-- Achsen-Mapping (1 = AccX, 2 = AccY, 3 = AccZ)
local mapPitch     = 1
local mapRoll      = 2

-- Dynamisches Sensor-Array für volle Konfigurierbarkeit (Exakt 4, 4 und 3 Zeichen reserviert)
local sName        = { "RSSI", "Alt ", "Spd ", "Dist", "VSpd", "Hdg ", "Batt", "CellD", "Curr" }
local sSrc         = { "RSSI", "Alt ", "Gspd", "Dist", "VSpd", "Hdg ", "Cels", "celD", "Curr" }
local sUnit        = { "dB ", "m  ", "kmh", "m  ", "m/s", "°  ", "V  ", "V  ", "A  " }

-- Menü-Steuerungsvariablen
local menuActive   = false
local menuPage     = 1
local selectedRow  = 1
local editField    = 0
local editCharIdx  = 1
local menuOpenTime = 0
local configLoaded = false

-- HILFSFUNKTIONEN
local function padStr(str, len)
    str = (str == nil) and "" or tostring(str)
    while #str < len do str = str .. " " end
    return string.sub(str, 1, len)
end

local function trim(str)
    if not str then return "" end
    return string.gsub(str, "^%s*(.-)%s*$", "%1")
end

-- 1. ERWEITERTE LADE-ROUTINE
local function loadConfig()
    local modelInfo = model.getInfo()
    local modelName = string.gsub(modelInfo.name, "[ %c%p]", "_")
    local configPath = "/LOGS/hz_" .. modelName .. ".txt"

    local f = io.open(configPath, "r")
    if f then
        invPitch = tonumber(io.read(f, 1)) or 0; io.read(f, 1)
        invRoll = tonumber(io.read(f, 1)) or 0; io.read(f, 1)
        invHdg = tonumber(io.read(f, 1)) or 0; io.read(f, 1)
        groundMode = tonumber(io.read(f, 1)) or 0; io.read(f, 1)
        mapPitch = tonumber(io.read(f, 1)) or 1; io.read(f, 1)
        mapRoll = tonumber(io.read(f, 1)) or 2; io.read(f, 1)

        for i = 1, 9 do
            sName[i] = padStr(io.read(f, 4) or sName[i], 4); io.read(f, 1)
            sSrc[i] = padStr(io.read(f, 4) or sSrc[i], 4); io.read(f, 1)
            sUnit[i] = padStr(io.read(f, 3) or sUnit[i], 3); io.read(f, 1) -- HIER BEHOBEN: padStr auf 3 erhöht!
        end
        io.close(f)
    else
        invPitch, invRoll, invHdg, groundMode, mapPitch, mapRoll = 0, 0, 0, 0, 1, 2
    end
    configLoaded = true
end

-- 2. ERWEITERTE SPEICHER-ROUTINE
local function saveConfig()
    local modelInfo = model.getInfo()
    local modelName = string.gsub(modelInfo.name, "[ %c%p]", "_")
    local configPath = "/LOGS/hz_" .. modelName .. ".txt"

    local f = io.open(configPath, "w")
    if f then
        io.write(f, tostring(invPitch) .. "\n")
        io.write(f, tostring(invRoll) .. "\n")
        io.write(f, tostring(invHdg) .. "\n")
        io.write(f, tostring(groundMode) .. "\n")
        io.write(f, tostring(mapPitch) .. "\n")
        io.write(f, tostring(mapRoll) .. "\n")

        for i = 1, 9 do
            io.write(f, padStr(sName[i], 4) .. "\n")
            io.write(f, padStr(sSrc[i], 4) .. "\n")
            io.write(f, padStr(sUnit[i], 3) .. "\n")
        end
        io.close(f)
    end
end

-- 3. INITIALISIERUNG
local function init()
    menuActive = false
    menuPage = 1
    selectedRow = 1
    editField = 0
    editCharIdx = 1
    menuOpenTime = 0
    configLoaded = false
end

-- Hilfsliste der erlaubten Zeichen für den Namen-Editor
local allowedChars = " ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789°/%:-"

local function changeChar(str, idx, delta)
    local curChar = string.sub(str, idx, idx)
    local charPos = string.find(allowedChars, curChar, 1, true) or 1

    charPos = charPos + delta
    if charPos > #allowedChars then
        charPos = 1
    elseif charPos < 1 then
        charPos = #allowedChars
    end

    local newChar = string.sub(allowedChars, charPos, charPos)
    return string.sub(str, 1, idx - 1) .. newChar .. string.sub(str, idx + 1)
end

-- TASTEN-ABFRAGE & MENÜ-LOGIK
local function handleMenu(event)
    local lockActive = (getTime() - menuOpenTime) < 50
    if lockActive then return true end

    -- 1. FALL: SENSOR-ZEICHEN EDITIEREN
    if editField > 0 then
        local idx = (selectedRow <= 6) and selectedRow or (selectedRow - 6)
        if menuPage == 3 then idx = idx + 6 end

        local currentText = (editField == 1) and sSrc[idx] or sUnit[idx]
        local maxLen = (editField == 1) and 4 or 3

        if event == EVT_MINUS_FIRST or event == EVT_ROT_LEFT then
            currentText = changeChar(currentText, editCharIdx, -1)
            if editField == 1 then sSrc[idx] = currentText else sUnit[idx] = currentText end
        elseif event == EVT_PLUS_FIRST or event == EVT_ROT_RIGHT then
            currentText = changeChar(currentText, editCharIdx, 1)
            if editField == 1 then sSrc[idx] = currentText else sUnit[idx] = currentText end
        elseif event == EVT_ENTER_BREAK then
            editCharIdx = editCharIdx + 1
            if editCharIdx > maxLen then
                editCharIdx = 1
                editField = editField + 1
                if editField > 2 then editField = 0 end
            end
        end
        return true
    end

    -- 2. FALL: NAVIGIEREN / BLÄTTERN
    local maxRows = (menuPage == 1) and 5 or ((menuPage == 4) and 3 or ((menuPage == 3) and 4 or 7))
    if event == EVT_MINUS_FIRST or event == EVT_ROT_LEFT then
        selectedRow = selectedRow - 1
        if selectedRow < 1 then selectedRow = maxRows end
    elseif event == EVT_PLUS_FIRST or event == EVT_ROT_RIGHT then
        selectedRow = selectedRow + 1
        if selectedRow > maxRows then selectedRow = 1 end
    elseif event == EVT_PAGE_BREAK then
        menuPage = menuPage + 1
        if menuPage > 4 then menuPage = 1 end
        selectedRow = 1
    elseif event == EVT_ENTER_BREAK then
        if menuPage == 1 then
            if selectedRow == 1 then
                invPitch = (invPitch == 0) and 1 or 0
            elseif selectedRow == 2 then
                invRoll = (invRoll == 0) and 1 or 0
            elseif selectedRow == 3 then
                invHdg = (invHdg == 0) and 1 or 0
            elseif selectedRow == 4 then
                groundMode = groundMode + 1
                if groundMode > 2 then groundMode = 0 end
            elseif selectedRow == 5 then
                saveConfig()
                menuActive = false
            end
        elseif menuPage == 2 or menuPage == 3 then
            local maxSel = (menuPage == 2) and 6 or 3
            if selectedRow <= maxSel then
                editField = 1
                editCharIdx = 1
            else
                menuPage = menuPage + 1
                if menuPage > 4 then menuPage = 1 end
                selectedRow = 1
            end
        elseif menuPage == 4 then
            if selectedRow == 1 then
                mapPitch = mapPitch + 1; if mapPitch > 3 then mapPitch = 1 end
            elseif selectedRow == 2 then
                mapRoll = mapRoll + 1; if mapRoll > 3 then mapRoll = 1 end
            elseif selectedRow == 3 then
                saveConfig()
                menuActive = false
            end
        end
    end
    return true
end

-- MENÜ-GRAFIK
local function drawMenu()
    local blink = (math.floor(getTime() / 30) % 2 == 0)

    if menuPage == 1 then
        lcd.drawText(1, 2, "-- CONFIG MENU (1/4) --", INVERS)
        local groundText = "White"
        if groundMode == 1 then
            groundText = "Lines"
        elseif groundMode == 2 then
            groundText = "Points"
        end

        lcd.drawText(1, 13, (selectedRow == 1 and "> " or "  ") .. "Pitch Invert: " .. (invPitch == 1 and "YES" or "NO"),
            selectedRow == 1 and INVERS or 0)
        lcd.drawText(1, 22, (selectedRow == 2 and "> " or "  ") .. "Roll Invert : " .. (invRoll == 1 and "YES" or "NO"),
            selectedRow == 2 and INVERS or 0)
        lcd.drawText(1, 31, (selectedRow == 3 and "> " or "  ") .. "Hdg Invert  : " .. (invHdg == 1 and "YES" or "NO"),
            selectedRow == 3 and INVERS or 0)
        lcd.drawText(1, 40, (selectedRow == 4 and "> " or "  ") .. "Ground      : " .. groundText,
            selectedRow == 4 and INVERS or 0)
        lcd.drawText(1, 51, (selectedRow == 5 and "> " or "  ") .. "     >> SAVE <<", selectedRow == 5 and INVERS or 0)
    elseif menuPage == 2 or menuPage == 3 then
        local pTitle = (menuPage == 2) and "-- SENSORS LEFT (2/4) --" or "-- SENSORS RIGHT (3/4) --"
        lcd.drawText(1, 2, pTitle, INVERS)

        local startIdx = (menuPage == 2) and 1 or 7
        local endIdx   = (menuPage == 2) and 6 or 9
        local yPos     = 13

        for i = startIdx, endIdx do
            local rowIdx = (menuPage == 2) and i or (i - 6)
            local isSel = (selectedRow == rowIdx)
            local prefix = isSel and "> " or "  "

            lcd.drawText(1, yPos, prefix .. sName[i] .. ":", 0)

            local srcStr = sSrc[i]
            local unitStr = sUnit[i]

            if isSel and editField > 0 then
                local txt = (editField == 1) and srcStr or unitStr
                if blink then
                    txt = string.sub(txt, 1, editCharIdx - 1) .. "_" .. string.sub(txt, editCharIdx + 1)
                end
                if editField == 1 then srcStr = txt else unitStr = txt end
            end

            --Direktes Rendering der bereinigten Werte (Verhindert Text-Verschiebungen)
            lcd.drawText(60, yPos, trim(srcStr), (isSel and editField == 1) and INVERS or 0)
            lcd.drawText(104, yPos, "[" .. trim(unitStr) .. "]", (isSel and editField == 2) and INVERS or 0, RIGHT)
            yPos = yPos + 8
        end

        -- Markierung für den Page-Wechsel ganz unten am Pfeil
        local maxSel = (menuPage == 2) and 6 or 3
        if selectedRow == (maxSel + 1) then
            lcd.drawRectangle(90, 55, 36, 9, FORCE)
        end
    elseif menuPage == 4 then
        lcd.drawText(1, 2, "-- AXIS MAPPING (4/4) --", INVERS)
        local axNames = { "AccX", "AccY", "AccZ" }
        lcd.drawText(1, 15, (selectedRow == 1 and "> " or "  ") .. "Map Pitch -> " .. axNames[mapPitch],
            selectedRow == 1 and INVERS or 0)
        lcd.drawText(1, 27, (selectedRow == 2 and "> " or "  ") .. "Map Roll  -> " .. axNames[mapRoll],
            selectedRow == 2 and INVERS or 0)
        lcd.drawText(1, 48, (selectedRow == 3 and "> " or "  ") .. "     >> SAVE <<", selectedRow == 3 and INVERS or 0)
    end
end
-- ============================================================================
-- HAUPTFUNKTION (FLUGMODUS & HAUPTSCHLEIFE)
-- ============================================================================
local function run(event)
    lcd.clear()
    if not configLoaded then
        loadConfig()
    end
    if event == EVT_MENU_LONG then
        menuActive = true
        menuPage = 1
        selectedRow = 1
        editField = 0
        menuOpenTime = getTime()
    end
    if menuActive then
        handleMenu(event)
        drawMenu()
        return 0
    end
    -- ============================================================================
    -- FLUGMODUS: HOCH DYNAMISCHE SENSOR-AUSWERTUNG
    -- ============================================================================
    local pFact    = (invPitch == 1) and -1 or 1
    local rFact    = (invRoll == 1) and -1 or 1
    local hFact    = (invHdg == 1) and -1 or 1
    local rssi     = getValue(trim(sSrc[1])) or 0
    local sats     = getValue("Sats") or 0
    local rawAlt   = getValue(trim(sSrc[2])) or 0
    local rawGspd  = getValue(trim(sSrc[3])) or 0
    local dist     = getValue(trim(sSrc[4])) or 0
    local vspd     = getValue(trim(sSrc[5])) or 0
    local rawHdg   = getValue(trim(sSrc[6])) or 0
    local cels_raw = getValue(trim(sSrc[7])) or 0
    local cmin     = getValue(trim(sSrc[8])) or 0
    local amp      = getValue(trim(sSrc[9])) or 0
    filteredAlt    = (rawAlt * 0.25) + (filteredAlt * 0.75)
    local alt      = filteredAlt or 0
    local gspd     = rawGspd * 1.852
    local cels     = 0
    if type(cels_raw) == "table" then
        for _, cell_volt in ipairs(cels_raw) do cels = cels + cell_volt end
    else
        cels = tonumber(cels_raw) or 0
    end
    local accValues = { getValue("AccX") or 0, getValue("AccY") or 0, getValue("AccZ") or 0 }
    local pitch     = accValues[mapPitch] * 90 * pFact
    local roll      = accValues[mapRoll] * 90 * rFact
    rawHdg          = rawHdg * hFact
    if rawHdg < 0 then rawHdg = rawHdg + 360 end
    local diff = rawHdg - filteredHdg
    if diff > 180 then diff = diff - 360 end
    if diff < -180 then diff = diff + 360 end
    filteredHdg = filteredHdg + (diff * 0.3)
    local hdg = (filteredHdg % 360 + 360) % 360
    -- ============================================================================
    -- GRAFIK-RENDERING (KÜNSTLICHER HORIZONT)
    -- ============================================================================
    local cx, sizeW, cy, sizeH = 76, 26, 35, 28
    local pitchOffset = math.max(math.min(pitch * 0.6, sizeH - 2), -(sizeH - 2))
    local rollAngle = (roll / 57.2957)
    local dx = math.cos(rollAngle) * (sizeW - 1)
    local dy = math.sin(rollAngle) * (sizeW - 1)
    local isUpsideDown = false
    local absRoll = math.abs(roll % 360)
    if absRoll > 90 and absRoll < 270 then isUpsideDown = true end
    if groundMode > 0 then
        local startX, endX = cx - sizeW + 1, cx + sizeW - 1
        for y = cy - sizeH + 1, cy + sizeH - 1 do
            local xLeft, xRight = startX, endX
            if dy ~= 0 then
                local intersectX = math.floor(cx + ((y - cy - pitchOffset) * dx) / dy)
                if (dy > 0 and not isUpsideDown) or (dy < 0 and isUpsideDown) then
                    xRight = math.min(endX, intersectX)
                else
                    xLeft = math.max(startX, intersectX)
                end
            else
                if (pitchOffset >= 0 and not isUpsideDown) or (pitchOffset < 0 and isUpsideDown) then
                    if y <= (cy + pitchOffset) then xLeft = endX + 1 end
                else
                    if y >= (cy + pitchOffset) then xLeft = endX + 1 end
                end
            end
            if xLeft <= xRight then
                if groundMode == 1 and y % 2 == 0 then
                    lcd.drawLine(xLeft, y, xRight, y, SOLID, FORCE)
                elseif groundMode == 2 then
                    local xLoopStart = xLeft + ((xLeft + y) % 2)
                    for x = xLoopStart, xRight, 2 do lcd.drawPoint(x, y) end
                end
            end
        end
    end
    lcd.drawRectangle(cx - sizeW, cy - sizeH, sizeW * 2, sizeH * 2, FORCE)
    lcd.drawLine(cx - sizeW - 5, cy, cx - sizeW - 1, cy, SOLID, FORCE)
    lcd.drawLine(cx + sizeW + 1, cy, cx + sizeW + 5, cy, SOLID, FORCE)
    lcd.drawLine(cx - 2, cy, cx + 2, cy, SOLID, FORCE)
    lcd.drawLine(cx, cy - 2, cx, cy + 2, SOLID, FORCE)
    lcd.drawLine(cx - dx, cy - dy + pitchOffset, cx + dx, cy + dy + pitchOffset, SOLID, FORCE)
    if alt and sizeH > 0 then
        local altTickY = cy + ((alt % 5) * (sizeH / 5)) - (sizeH / 2)
        if altTickY >= (cy - sizeH + 2) and altTickY <= (cy + sizeH - 2) then
            lcd.drawLine(cx - sizeW + 1, altTickY, cx - sizeW + 4, altTickY, SOLID, FORCE)
        end
    end
    lcd.drawText(cx - sizeW + 5, cy - sizeH + 2, "S:" .. string.format("%.0f", sats), SMLSIZE)
    local gfix = getValue("Gfix") or 0
    local fixStr = (gfix == 3) and "3D" or ((gfix == 2) and "2D" or "nF")
    lcd.drawText(cx + sizeW - 11, cy - sizeH + 2, fixStr, SMLSIZE)
    lcd.drawText(cx, cy - 13, string.format("%.0f", alt) .. trim(sUnit[2]), SMLSIZE + CENTER)
    if hdg and hdg >= 0 and hdg <= 360 then
        local yBottom = cy - sizeH - 1
        lcd.drawPoint(cx, yBottom - 4)
        for i = -3, 3 do
            local tickAngle = (math.floor(hdg / 10) + i) * 10
            local normalizedAngle = (tickAngle % 360 + 360) % 360
            local diffH = tickAngle - hdg
            if diffH > 180 then diffH = diffH - 360 elseif diffH < -180 then diffH = diffH + 360 end
            local tickX = cx + (diffH * 0.75)
            if tickX >= (cx - sizeW) and tickX <= (cx + sizeW) and tickX >= 0 and tickX <= 128 then
                if normalizedAngle % 90 == 0 then
                    lcd.drawLine(tickX - 1, yBottom - 6, tickX + 1, yBottom - 6, SOLID, FORCE)
                    lcd.drawLine(tickX, yBottom - 5, tickX, yBottom - 4, SOLID, FORCE)
                    local letter = (normalizedAngle == 0 or normalizedAngle == 360) and "N" or
                    (normalizedAngle == 90 and "O" or (normalizedAngle == 180 and "S" or "W"))
                    lcd.drawText(tickX - 2, yBottom - 3, letter, SMLSIZE)
                elseif normalizedAngle % 30 == 0 then
                    lcd.drawLine(tickX, yBottom - 4, tickX, yBottom, SOLID, FORCE)
                else
                    lcd.drawLine(tickX, yBottom - 2, tickX, yBottom, SOLID, FORCE)
                end
            end
        end
    end
    -- LINKE SEITE
    lcd.drawText(1, 2, trim(sName[1]) .. ":" .. string.format("%d", rssi) .. trim(sUnit[1]), SMLSIZE)
    lcd.drawText(1, 13, trim(sName[2]) .. ":" .. string.format("%.0f", alt) .. trim(sUnit[2]), SMLSIZE)
    lcd.drawText(1, 24, trim(sName[3]) .. ":" .. string.format("%.0f", gspd) .. trim(sUnit[3]), SMLSIZE)
    lcd.drawText(1, 35, trim(sName[4]) .. ":" .. string.format("%.0f", dist) .. trim(sUnit[4]), SMLSIZE)
    lcd.drawText(1, 46, trim(sName[5]) .. ":" .. string.format("%.0f", vspd) .. trim(sUnit[5]), SMLSIZE)
    lcd.drawText(1, 57, trim(sName[6]) .. ":" .. string.format("%03d", hdg) .. trim(sUnit[6]), SMLSIZE)
    -- RECHTER TEXTBLOCK
    local rx = 104
    local rEdge = 127
    lcd.drawText(rx, 1, trim(sName[7]) .. ":", SMLSIZE)
    lcd.drawText(rEdge, 9, string.format("%.1f", cels) .. trim(sUnit[7]), SMLSIZE + RIGHT)
    lcd.drawText(rx, 19, trim(sName[8]) .. ":", SMLSIZE)
    lcd.drawText(rEdge, 27, string.format("%.2f", cmin) .. trim(sUnit[8]), SMLSIZE + RIGHT)
    lcd.drawText(rx, 36, trim(sName[9]) .. ":", SMLSIZE)
    lcd.drawText(rEdge, 43, string.format("%.1f", amp) .. trim(sUnit[9]), SMLSIZE + RIGHT)
    lcd.drawText(rEdge - 1, 51, string.format("%.0f", pitch) .. "°=Y", SMLSIZE + RIGHT)
    lcd.drawText(rEdge, 58, string.format("%.0f", roll) .. "°=X", SMLSIZE + RIGHT)
    return 0
end
return { init = init, run = run }
