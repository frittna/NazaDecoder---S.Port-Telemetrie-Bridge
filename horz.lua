-- ======================================================================================================================
-- LUA: Horizon & Telemetry Sensor Display for FrSky Sensors (QX7 - EdgeTX 2.10/2.11 BW Display) -- @frittna Oct 10, 2026
-- ======================================================================================================================
--> This LUA script was created during the project: github.com/frittna/NazaDecoder-S.Port-Telemetrie-Bridge-MPU
--> Files (all three must be placed in the same directory under /SCRIPTS/TELEMETRY/ on your transmitter):
-->   horz.lua       Main view (this is the actual telemetry script, select only this one in your screen setup)
-->   horz_menu.lua  Menu/Calibration/Config-Editor (loaded only upon a long press of the MENU button)
-->   horz_cfg.lua   Config load/save + Sensor catalog (loaded dynamically and briefly when needed)
--> The auxiliary files have names longer than 6 characters and are loaded via loadScript() using their full
--> path. If they appear in your telemetry script selection menu: adjust the path in DIR and move both
--> auxiliary files into a subfolder (e.g., /SCRIPTS/TELEMETRY/horz/).

--DEUTSCH:
-- LUA: Horizont & Telemetrie Sensor Display for FrSky Sensoren (QX7 - EdgeTX 2.10/2.11 BW Display) -- @frittna 10.Okt.2026
--> Das LUA Script ist entstanden beim Projekt github.com/frittna/NazaDecoder-S.Port-Telemetrie-Bridge-MPU
--> Dateien (alle drei im selben Ordner /SCRIPTS/TELEMETRY/ auf dem Sender):
-->   horz.lua       Hauptansicht (das ist das Telemetry-Script, nur dieses im Screen-Setup waehlen)
-->   horz_menu.lua  Menue/Kalibrierung/Config-Editor, wird erst bei langem MENU-Druck geladen
-->   horz_cfg.lua   Config laden/speichern + Sensor-Katalog, wird nur kurz geladen
--> Die Nebendateien haben mehr als 6 Zeichen im Namen und werden per loadScript() mit vollem
--> Pfad geladen. Falls sie in der Telemetry-Script-Auswahl auftauchen: Pfad in DIR anpassen und
--> beide in einen Unterordner legen (z.B. /SCRIPTS/TELEMETRY/horz/).

--SKRIPT--

local DEBUG_MEM = false -- true: zeigt collectgarbage("count") in KB (jetzt/Spitze/nach init)
local DIR = "/SCRIPTS/TELEMETRY/"
local SLOT_COUNT, STANDARD_SLOT_COUNT = 15, 9
local CUSTOM_SLOT_FIRST = STANDARD_SLOT_COUNT + 1
local SLOT_NAME_VISIBLE = 4
local SPARK_N = 40
local SPARK_LABEL_CHAR_WIDTH, SPARK_LABEL_PAD = 5, 2 -- SMLSIZE character width and spacing in pixels
local SPARK_LABEL_X, SPARK_LABEL_HEIGHT = 1, 6
local SPARK_MIN_PLOT_WIDTH = 4
local SPARK_LABEL_COMPACT_DIGITS = 6
local ALTITUDE_TICK_METERS, ALTITUDE_METERS_PER_HALFBOX = 2.5, 5
-- Der Durchmesser enthaelt den Faktor 2 der Haversine-Distanz.
local EARTH_MEAN_DIAMETER_METERS = 12742000
local HOME_MIN_DISTANCE_METERS, COMPASS_PIXELS_PER_DEGREE = 5, 0.75
local DEGREE_UTF8 = "°"
local atan2 = math.atan2 or function(y, x)
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + ((y >= 0) and math.pi or -math.pi) end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

-- Gemeinsamer Zustand fuer Hauptansicht, Menue und Config-Modul
local cfg = {
    dir = DIR,
    invPitch = 0, invRoll = 0, invHdg = 0,
    groundMode = 2, attitudeMode = 1, viewMode = 1,
    pitchSource = "Ptch", rollSource = "Roll",
    insideSource = "Alt", insideEnabled = 1,
    altimeterSource = "Alt",
    graphSeconds = 30, graphEnabled = 1,
    fwdAxis = "X+", sideAxis = "Z-", downAxis = "Y+",
    sName = {}, sSrc = {}, sUnit = {}, sOn = {},
    sPrecision = {}, sMin = {}, sMax = {},
    configSaveFailed = false, configLoadWarning = false
}
local sMin, sMax = cfg.sMin, cfg.sMax
local menu, menuFailUntil = nil, 0
local ready, dirty = false, false
local memInit, memPeak = 0, 0

-- Vorberechnete Werte (nur in prepare() neu gesetzt)
local invPitch, invRoll, invHdg = 0, 0, 0
local groundMode, attitudeMode, viewMode = 2, 1, 1
local pitchSrc, rollSrc, altSrc, insideSrc = "", "", "", ""
local insideEnabled, insideFmt, insideIsAlt = 1, "%.1f", true
local graphEnabled, graphInterval = 1, 0
local axI, axS = { 1, 2, 3 }, { 1, 1, 1 }
local pSrc, pName, pLabel, pUnit, nameLen, uLen = {}, {}, {}, {}, {}, {}
local valFmt, fmtBoth, fmtLine, fmtMax, fmtMin = {}, {}, {}, {}, {}
local track, pShow = {}, {}
local leftActive, leftN, leftStep = {}, 0, 0
-- Werte und Texte, nur bei Wertaenderung neu formatiert
local slotValues, lastVal = {}, {}
local valText, bothText, lineText, vLen, bLen = {}, {}, {}, {}, {}

local sessionMin, sessionMax, sessionSource = {}, {}, {}
local sparkBuf, sparkCount, sparkHead, sparkLast, sparkSlot, sparkSrc, sparkInterval =
    {}, 0, 0, 0, 0, nil, 0
local filteredAlt, filteredHdg = 0, 0
local homeLat, homeLon
local gpsFix3Since, gpsLowFixSince, gpsWarningSince = nil, nil, nil
local vec = { 0, 0, 0 }

local headingLabels = {
    [0] = "N",
    [45] = "NO",
    [90] = "O",
    [135] = "SO",
    [180] = "S",
    [225] = "SW",
    [270] = "W",
    [315] = "NW"
}

local function isFinite(value)
    return value and value == value and value ~= math.huge and value ~= -math.huge
end

-- Zeichenzahl (das UTF-8-Gradzeichen zaehlt als 1), ohne Tabellen zu erzeugen
local function charLen(text)
    local count, at = #text, 1
    while true do
        local found = string.find(text, DEGREE_UTF8, at, true)
        if not found then return count end
        count, at = count - 1, found + 2
    end
end

local function escapeFormat(text)
    return (string.gsub(text, "%%", "%%%%"))
end

local function axisSetting(k, setting)
    local axis = string.sub(setting, 1, 1)
    axI[k] = (axis == "X") and 1 or ((axis == "Y") and 2 or 3)
    axS[k] = (string.sub(setting, 2, 2) == "-") and -1 or 1
end

-- Berechnet alles Abgeleitete aus cfg neu (beim Start und nach dem Menue)
local function prepare(C)
    local trim, textSlice = C.trim, C.textSlice
    invPitch, invRoll, invHdg = cfg.invPitch, cfg.invRoll, cfg.invHdg
    groundMode, attitudeMode, viewMode = cfg.groundMode, cfg.attitudeMode, cfg.viewMode
    pitchSrc, rollSrc, altSrc = trim(cfg.pitchSource), trim(cfg.rollSource), trim(cfg.altimeterSource)
    axisSetting(1, cfg.fwdAxis)
    axisSetting(2, cfg.sideAxis)
    axisSetting(3, cfg.downAxis)
    graphEnabled = cfg.graphEnabled
    graphInterval = math.floor(cfg.graphSeconds * 100 / SPARK_N)
    insideEnabled = cfg.insideEnabled
    insideSrc = trim(cfg.insideSource)
    insideIsAlt = string.lower(insideSrc) == "alt"
    local _, fmt, _, unit = C.catalogEntry(cfg, cfg.insideSource)
    insideFmt = ((fmt and insideSrc ~= "") and fmt or "%.1f") .. escapeFormat(unit or "")
    for i = 1, SLOT_COUNT do
        local src = trim(cfg.sSrc[i])
        pSrc[i] = src
        if sessionSource[i] ~= src then
            sessionSource[i], sessionMin[i], sessionMax[i] = src, nil, nil
        end
        track[i] = (i >= CUSTOM_SLOT_FIRST or cfg.sOn[i] == 1) and src ~= ""
        if not track[i] then sessionMin[i], sessionMax[i] = nil, nil end
        valFmt[i] = "%." .. cfg.sPrecision[i] .. "f"
        fmtMax[i], fmtMin[i] = "Max:" .. valFmt[i], "Min:" .. valFmt[i]
        lastVal[i] = nil
        if i <= STANDARD_SLOT_COUNT then
            local name, unitText = textSlice(trim(cfg.sName[i]), 1, SLOT_NAME_VISIBLE), trim(cfg.sUnit[i])
            pName[i], pLabel[i], pUnit[i] = name, name .. ":", unitText
            nameLen[i], uLen[i] = charLen(name), charLen(unitText)
            fmtBoth[i] = valFmt[i] .. escapeFormat(unitText)
            fmtLine[i] = escapeFormat(name) .. ":" .. fmtBoth[i]
            pShow[i] = cfg.sOn[i] == 1 and name ~= ""
        end
    end
    leftN = 0
    for i = 1, 6 do
        if pShow[i] and pSrc[i] ~= "" then
            leftN = leftN + 1
            leftActive[leftN] = i
        end
    end
    leftStep = (leftN == 6) and 11 or ((leftN > 1) and math.floor(55 / (leftN - 1)) or 0)
end

local function startup()
    local chunk = loadScript(DIR .. "horz_cfg")
    if not chunk then return end
    local C = chunk()
    C.load(cfg)
    prepare(C)
    ready = true
end

local function reprepare()
    local chunk = loadScript(DIR .. "horz_cfg")
    if not chunk then return false end
    prepare(chunk())
    return true
end

local function vectorValues()
    vec[1] = tonumber(getValue("AccX")) or 0
    vec[2] = tonumber(getValue("AccY")) or 0
    vec[3] = tonumber(getValue("AccZ")) or 0
    return vec
end

local function init()
    menu, menuFailUntil, ready, dirty = nil, 0, false, false
    sessionMin, sessionMax, sessionSource = {}, {}, {}
    sparkBuf, sparkCount, sparkHead, sparkLast, sparkSlot, sparkSrc, sparkInterval =
        {}, 0, 0, 0, 0, nil, 0
    startup()
    collectgarbage()
    memInit = collectgarbage("count")
    memPeak = memInit
end

local function readSlot(source)
    local raw = getValue(source)
    if type(raw) == "table" then
        local total = 0
        for _, value in ipairs(raw) do total = total + (tonumber(value) or 0) end
        raw = total
    end
    return tonumber(raw) or 0
end

local satelliteBase = {
    { 4, 0 }, { 5, 0 },
    { 1, 1 }, { 2, 1 }, { 3, 1 }, { 5, 1 },
    { 1, 2 }, { 4, 2 },
    { 0, 3 }, { 2, 3 }, { 3, 3 }, { 4, 3 }, { 5, 3 },
    { 0, 4 }, { 1, 4 }, { 3, 4 }, { 4, 4 }, { 5, 4 }
}
local satelliteInnerRays = {
    { 7, 3 }, { 7, 4 }, { 6, 5 }, { 5, 6 }, { 3, 7 }, { 4, 7 }
}
local satelliteOuterRays = {
    { 9, 4 }, { 9, 5 }, { 8, 6 }, { 7, 7 },
    { 6, 8 }, { 7, 8 }, { 4, 9 }, { 5, 9 }
}

local function updateGPSWarning(fix, now)
    if gpsWarningSince and now - gpsWarningSince >= 6000 then
        gpsWarningSince = nil
    end

    if fix == 3 then
        if gpsLowFixSince then gpsFix3Since = now end
        gpsLowFixSince = nil
        if not gpsFix3Since then gpsFix3Since = now end
    elseif gpsFix3Since then
        if now - gpsFix3Since <= 1000 then
            gpsFix3Since, gpsLowFixSince = nil, nil
        elseif not gpsLowFixSince then
            gpsLowFixSince = now
        elseif now - gpsLowFixSince > 300 and not gpsWarningSince then
            gpsWarningSince = now
            gpsFix3Since, gpsLowFixSince = nil, nil
        end
    end

    return gpsWarningSince ~= nil
end

local function drawSatellitePoints(x, y, points)
    for i = 1, #points do
        lcd.drawPoint(x + points[i][1], y + points[i][2])
    end
end

local function drawSatellite(x, y, fix)
    drawSatellitePoints(x, y, satelliteBase)
    if fix >= 2 then drawSatellitePoints(x, y, satelliteInnerRays) end
    if fix >= 3 then drawSatellitePoints(x, y, satelliteOuterRays) end
end

local function gpsCoordinates()
    local gps = getValue("GPS")
    if type(gps) ~= "table" then return nil, nil end
    local lat, lon = gps.lat, gps.lon
    if type(lat) ~= "number" or type(lon) ~= "number" or
        lat ~= lat or lon ~= lon or math.abs(lat) > 90 or math.abs(lon) > 180 then
        return nil, nil
    end
    return lat, lon
end

local function homeDirection(lat, lon)
    if not homeLat or not homeLon or not lat or not lon then return nil, nil end
    local toRadians = math.pi / 180
    local lat1, lat2 = homeLat * toRadians, lat * toRadians
    local deltaLat = (lat - homeLat) * toRadians
    local deltaLon = (lon - homeLon) * toRadians
    local sinLat, sinLon = math.sin(deltaLat / 2), math.sin(deltaLon / 2)
    local a = sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLon * sinLon
    a = math.max(0, math.min(1, a))
    local distance = EARTH_MEAN_DIAMETER_METERS * atan2(math.sqrt(a), math.sqrt(1 - a))
    if distance <= HOME_MIN_DISTANCE_METERS then return nil, distance end

    local homeLonDelta = (homeLon - lon) * toRadians
    local bearingY = math.sin(homeLonDelta) * math.cos(lat1)
    local bearingX = math.cos(lat2) * math.sin(lat1) -
        math.sin(lat2) * math.cos(lat1) * math.cos(homeLonDelta)
    local bearing = (atan2(bearingY, bearingX) / toRadians) % 360
    return bearing, distance
end
local function drawFilledSideArrow(x, direction, topY)
    for row = -3, 3 do
        local inset = math.abs(row)
        if direction == "left" then
            lcd.drawLine(x, topY + 4 + row, x + 4 - inset, topY + 4 + row, SOLID, FORCE)
        else
            lcd.drawLine(x - 4 + inset, topY + 4 + row, x, topY + 4 + row, SOLID, FORCE)
        end
    end
end

local function drawHomePointer(bearing, heading, cx, topY, sizeW)
    local delta = ((bearing - heading + 180) % 360) - 180
    local visibleLimit = (sizeW - 1) / COMPASS_PIXELS_PER_DEGREE
    if delta < -visibleLimit then
        drawFilledSideArrow(cx - sizeW, "left", topY)
    elseif delta > visibleLimit then
        drawFilledSideArrow(cx + sizeW - 1, "right", topY)
    else
        local x = math.floor(cx + delta * COMPASS_PIXELS_PER_DEGREE + 0.5)
        for row = 0, 3 do
            local halfWidth = 3 - row
            lcd.drawLine(x - halfWidth, topY + 1 + row, x + halfWidth, topY + 1 + row, SOLID, FORCE)
        end
    end
end

local function getAttitude()
    local pitch, roll
    if attitudeMode == 1 then
        pitch = (pitchSrc ~= "") and (tonumber(getValue(pitchSrc)) or 0) or 0
        roll = (rollSrc ~= "") and (tonumber(getValue(rollSrc)) or 0) or 0
    else
        local values = vectorValues()
        local fwd, side, down = values[axI[1]] * axS[1], values[axI[2]] * axS[2], values[axI[3]] * axS[3]
        local magnitude = math.sqrt(fwd * fwd + side * side + down * down)
        if magnitude > 0.001 then
            fwd, side, down = fwd / magnitude, side / magnitude, down / magnitude
        else
            fwd, side, down = 0, 0, 1
        end
        pitch = atan2(-fwd, math.sqrt(side * side + down * down)) * 57.2957795
        roll = atan2(side, down) * 57.2957795
    end
    pitch = pitch * ((invPitch == 1) and -1 or 1)
    roll = roll * ((invRoll == 1) and -1 or 1)
    return pitch, roll
end

-- Zustand der 3D-Ansicht (Modulebene statt Closures/Tabellen pro Frame)
local aLeft, aRight, aTop, aBottom, aCx, aCy, aFocal, aRoll, aPitch = 0, 0, 0, 0, 0, 0, 0, 0, 0
local p1x, p1y, p2x, p2y, pCount = 0, 0, 0, 0, 0
local MARKS = { -45, 0, 45 }

local function addPoint(x, y)
    if pCount < 2 and x >= aLeft - 0.01 and x <= aRight + 0.01 and
        y >= aTop - 0.01 and y <= aBottom + 0.01 then
        if pCount == 1 and math.abs(p1x - x) < 0.1 and math.abs(p1y - y) < 0.1 then
            return
        end
        pCount = pCount + 1
        if pCount == 1 then
            p1x, p1y = x, y
        else
            p2x, p2y = x, y
        end
    end
end

local function planeLine(angle, dotted, dashed)
    local p = angle * 0.01745329252
    local a = -math.sin(aRoll) * math.cos(p)
    local b = math.cos(aRoll) * math.cos(p)
    local c = -aFocal * math.sin(p)
    if dotted and math.abs(a) < 0.0001 and math.abs(b) < 0.0001 then
        local y = (angle > aPitch) and aTop or aBottom
        if dashed then
            for x = aLeft, aRight, 4 do
                lcd.drawLine(x, y, math.min(x + 2, aRight), y, SOLID, FORCE)
            end
        else
            for x = aLeft, aRight, 2 do lcd.drawPoint(x, y) end
        end
        return
    end
    pCount = 0
    if math.abs(b) > 0.0001 then
        addPoint(aLeft, aCy - (a * (aLeft - aCx) + c) / b)
        addPoint(aRight, aCy - (a * (aRight - aCx) + c) / b)
    end
    if math.abs(a) > 0.0001 then
        addPoint(aCx - (b * (aTop - aCy) + c) / a, aTop)
        addPoint(aCx - (b * (aBottom - aCy) + c) / a, aBottom)
    end
    if pCount < 2 then return end

    if dotted then
        local steps = math.max(math.abs(p2x - p1x), math.abs(p2y - p1y))
        if steps < 1 then return end
        local spacing = dashed and 4 or 2
        for i = 0, math.floor(steps), spacing do
            if dashed then
                local endT = math.min(steps, i + 2) / steps
                local startT = i / steps
                lcd.drawLine(p1x + (p2x - p1x) * startT, p1y + (p2y - p1y) * startT,
                    p1x + (p2x - p1x) * endT, p1y + (p2y - p1y) * endT, SOLID, FORCE)
            else
                local t = i / steps
                lcd.drawPoint(p1x + (p2x - p1x) * t, p1y + (p2y - p1y) * t)
            end
        end
    else
        lcd.drawLine(p1x, p1y, p2x, p2y, SOLID, FORCE)
    end
end

local function draw3DAttitude(cx, cy, sizeW, sizeH, pitch, roll)
    local left, right = cx - sizeW + 1, cx + sizeW - 1
    local top, bottom = cy - sizeH + 1, cy + sizeH - 1
    local pitchRad = pitch * 0.01745329252
    aLeft, aRight, aTop, aBottom, aCx, aCy = left, right, top, bottom, cx, cy
    aFocal, aRoll, aPitch = sizeW, roll * 0.01745329252, pitch

    local a = -math.sin(aRoll) * math.cos(pitchRad)
    local b = math.cos(aRoll) * math.cos(pitchRad)
    local c = -aFocal * math.sin(pitchRad)
    for y = top, bottom do
        local row = y - cy
        local leftGround, rightGround = left, right
        local centerValue = b * row + c
        if math.abs(a) > 0.0001 then
            local cross = cx - centerValue / a
            if a > 0 then
                leftGround = math.max(leftGround, math.ceil(cross))
            else
                rightGround = math.min(rightGround, math.floor(cross))
            end
        elseif centerValue < 0 then
            leftGround = rightGround + 1
        end
        if leftGround <= rightGround then
            if groundMode == 1 and y % 2 == 0 then
                lcd.drawLine(leftGround, y, rightGround, y, SOLID, FORCE)
            elseif groundMode == 2 then
                for x = leftGround + ((leftGround + y) % 2), rightGround, 2 do
                    lcd.drawPoint(x, y)
                end
            end
        end
    end

    planeLine(pitch, false)
    planeLine(pitch - 45, true)
    planeLine(pitch + 45, true)
    planeLine(pitch - 90, true, true)
    planeLine(pitch + 90, true, true)

    -- Dezente 45°-Marken mit beweglicher Pitch-/Roll-Anzeige.
    for i = 1, 3 do
        local y = cy - (MARKS[i] / 90) * sizeH
        lcd.drawLine(left + 1, y, left + 2, y, SOLID, FORCE)
        lcd.drawLine(right - 1, y, right - 2, y, SOLID, FORCE)
    end
    local pitchY = cy - (math.max(-90, math.min(90, pitch)) / 90) * sizeH
    lcd.drawLine(left + 2, pitchY - 1, left + 2, pitchY + 1, SOLID, FORCE)
    lcd.drawLine(right - 2, pitchY - 1, right - 2, pitchY + 1, SOLID, FORCE)
    for i = 1, 3 do
        local x = cx + (MARKS[i] / 90) * sizeW
        lcd.drawLine(x, top + 1, x, top + 2, SOLID, FORCE)
        lcd.drawLine(x, bottom - 1, x, bottom - 2, SOLID, FORCE)
    end
    local rollX = cx + (math.max(-90, math.min(90, roll)) / 90) * sizeW
    lcd.drawLine(rollX - 1, top + 2, rollX + 1, top + 2, SOLID, FORCE)
    lcd.drawLine(rollX - 1, bottom - 2, rollX + 1, bottom - 2, SOLID, FORCE)
end

-- Linke Spalte (Slots 1..6): passt sich der Zahl aktiver Slots an
local FONTS_BIG = { { MIDSIZE, 8 }, { 0, 6 }, { SMLSIZE, 5 } }
local FONTS_NORMAL = { { 0, 6 }, { SMLSIZE, 5 } }

local function pickFont(len, limit, fonts)
    for k = 1, #fonts do
        if len * fonts[k][2] <= limit then return fonts[k][1] end
    end
    return SMLSIZE
end

local function drawName(x, y, i, limit)
    local len = nameLen[i]
    if len * 8 + 8 <= limit then
        lcd.drawText(x, y, pLabel[i], MIDSIZE)
    elseif len * 8 <= limit then
        lcd.drawText(x, y, pName[i], MIDSIZE)
    else
        lcd.drawText(x, y, pLabel[i], pickFont(len + 1, limit, FONTS_BIG))
    end
end

-- Wert immer MIDSIZE, Einheit klein dahinter; nur wenn es nicht passt: Fallback nach Breite
local function drawBigValue(x, y, i, limit)
    local valueLength = vLen[i]
    if valueLength * 8 + uLen[i] * 5 <= limit then
        lcd.drawText(x, y, valText[i], MIDSIZE)
        if pUnit[i] ~= "" then
            lcd.drawText(x + valueLength * 8 + 1, y + 5, pUnit[i], SMLSIZE)
        end
    else
        lcd.drawText(x, y, bothText[i], pickFont(bLen[i], limit, FONTS_BIG))
    end
end

local function sparkScale(slot)
    local fixedLow = (sMin[slot] ~= 0) and sMin[slot] or nil
    local fixedHigh = (sMax[slot] ~= 0) and sMax[slot] or nil
    local graphLow, graphHigh
    if fixedLow or fixedHigh then
        graphLow, graphHigh = sMin[slot], sMax[slot]
        if graphLow == 0 then
            graphLow = math.min(sessionMin[slot] or (graphHigh - 1), graphHigh - 1)
        elseif graphHigh == 0 then
            graphHigh = math.max(sessionMax[slot] or (graphLow + 1), graphLow + 1)
        end
        if graphHigh <= graphLow then graphHigh = graphLow + 1 end
    end
    return graphLow, graphHigh, fixedLow, fixedHigh
end

local function sparkLabel(value, slot, maxChars)
    local precision = cfg.sPrecision[slot] or 0
    local text = string.format("%." .. precision .. "f", value)
    if charLen(text) <= maxChars then return text end
    for decimals = precision - 1, 0, -1 do
        text = string.format("%." .. decimals .. "f", value)
        if charLen(text) <= maxChars then return text end
    end
    -- Fall back to a compact significant-digit form only when fixed-point text cannot fit.
    for digits = SPARK_LABEL_COMPACT_DIGITS, 1, -1 do
        text = string.format("%." .. digits .. "g", value)
        if charLen(text) <= maxChars then return text end
    end
    return string.format("%.1g", value)
end

local function sparkSample(start, k)
    return sparkBuf[((start + k) % SPARK_N) + 1]
end

local function sparkWindowExtremes(start)
    local windowLow, windowHigh
    for k = 0, sparkCount - 1 do
        local value = sparkSample(start, k)
        if windowLow == nil then
            windowLow, windowHigh = value, value
        else
            if value < windowLow then windowLow = value end
            if value > windowHigh then windowHigh = value end
        end
    end
    return windowLow, windowHigh
end

local function drawSparkline(x0, y0, x1, y1, slot)
    if sparkCount == 0 or slot == nil then return end
    local start = (sparkCount < SPARK_N) and 0 or sparkHead
    local lo, hi, fixedLow, fixedHigh = sparkScale(slot)
    local windowLow, windowHigh = sparkWindowExtremes(start)
    if lo == nil or hi == nil then lo, hi = windowLow, windowHigh end
    local maxLabelChars = math.max(1, math.floor(
        (x1 - SPARK_LABEL_X - SPARK_LABEL_PAD - SPARK_MIN_PLOT_WIDTH) / SPARK_LABEL_CHAR_WIDTH))
    -- Unconfigured labels follow the session-derived scale edge used by the trace.
    local highText = sparkLabel(fixedHigh or hi, slot, maxLabelChars)
    local lowText = sparkLabel(fixedLow or lo, slot, maxLabelChars)
    -- The live reading can advance beyond the buffered window between graph sampling ticks.
    local currentValue = slotValues[slot]
    -- Only sensors without stored MM limits invert labels when the live reading exceeds the window.
    local noFixedLimits = not fixedLow and not fixedHigh
    local numericCurrent = type(currentValue) == "number"
    local highLabelStyle, lowLabelStyle = SMLSIZE, SMLSIZE
    if noFixedLimits and numericCurrent then
        if currentValue > windowHigh then
            highLabelStyle = SMLSIZE + INVERS
        elseif currentValue < windowLow then
            lowLabelStyle = SMLSIZE + INVERS
        end
    end
    lcd.drawText(SPARK_LABEL_X, y0, highText, highLabelStyle)
    lcd.drawText(SPARK_LABEL_X, y1 - SPARK_LABEL_HEIGHT, lowText, lowLabelStyle)
    local labelWidth = math.max(charLen(highText), charLen(lowText)) * SPARK_LABEL_CHAR_WIDTH
    local maxPlotX0 = math.max(x0, x1 - SPARK_MIN_PLOT_WIDTH)
    local plotX0 = math.min(maxPlotX0, math.max(x0, SPARK_LABEL_X + labelWidth + SPARK_LABEL_PAD))
    lcd.drawLine(plotX0, y0, x1, y0, SOLID, FORCE)
    lcd.drawLine(plotX0, y1, x1, y1, SOLID, FORCE)
    if sparkCount < 2 then return end
    local span, h = hi - lo, y1 - y0
    local px, py
    local previousOutside = false
    for k = 0, sparkCount - 1 do
        local v = sparkSample(start, k)
        local ratio = (span == 0) and 0.5 or math.max(0, math.min(1, (v - lo) / span))
        local y = math.floor(y1 - ratio * h + 0.5)
        local outside = (fixedHigh and v > fixedHigh) or (fixedLow and v < fixedLow) or false
        -- Fixed spacing keeps the time scale constant; the trace reaches x1 only when full.
        local x = math.floor(plotX0 + k * (x1 - plotX0) / (SPARK_N - 1) + 0.5)
        if px then
            lcd.drawLine(px, py, x, y, (outside or previousOutside) and DOTTED or SOLID, FORCE)
        end
        px, py = x, y
        previousOutside = outside
    end
end
local function drawLeftColumn()
    local n = leftN
    if n ~= 1 then sparkCount, sparkHead, sparkSlot = 0, 0, 0 end
    if n == 0 then return end
    if n >= 4 then
        for k = 1, n do
            lcd.drawText(1, 2 + (k - 1) * leftStep, lineText[leftActive[k]], SMLSIZE)
        end
    elseif n == 3 then
        -- 3 Sensoren: Name und Wert gleich gross (normale Schrift), sonst SMLSIZE
        for k = 1, 3 do
            local i = leftActive[k]
            local y = 1 + (k - 1) * 21
            local limit = (k == 1) and 33 or 43
            -- eine gemeinsame Schrift pro Block (nach dem breiteren Text)
            local font = pickFont((bLen[i] > nameLen[i] + 1) and bLen[i] or (nameLen[i] + 1),
                limit, FONTS_NORMAL)
            lcd.drawText(1, y, pLabel[i], font)
            lcd.drawText(1, y + 9, bothText[i], font)
        end
    elseif n == 2 then
        -- 2 Sensoren: Name und Wert ganz gross (MIDSIZE), erster Name im GPS-Bereich begrenzt
        for k = 1, 2 do
            local i = leftActive[k]
            local y = 2 + (k - 1) * 32
            drawName(1, y, i, (k == 1) and 33 or 43)
            drawBigValue(1, y + 14, i, 43)
        end
        lcd.drawLine(0, 31, 40, 31, SOLID, FORCE)
    else
        local slot = leftActive[1]
        drawName(1, 1, slot, 33)
        drawBigValue(1, 15, slot, 43)
        if graphEnabled ~= 1 then
            sparkCount, sparkHead, sparkSlot = 0, 0, 0
            local low = sessionMin[slot] or slotValues[slot]
            local high = sessionMax[slot] or slotValues[slot]
            lcd.drawText(1, 36, string.format(fmtMax[slot], high), SMLSIZE)
            lcd.drawText(1, 51, string.format(fmtMin[slot], low), SMLSIZE)
            return
        end
        local interval = graphInterval
        if sparkSlot ~= slot or sparkSrc ~= pSrc[slot] or sparkInterval ~= interval then
            sparkCount, sparkHead, sparkLast, sparkSlot, sparkSrc, sparkInterval =
                0, 0, 0, slot, pSrc[slot], interval
        end
        local now = getTime()
        if sparkCount == 0 or now - sparkLast >= interval then
            sparkLast = now
            sparkBuf[sparkHead + 1] = slotValues[slot]
            sparkHead = (sparkHead + 1) % SPARK_N
            if sparkCount < SPARK_N then sparkCount = sparkCount + 1 end
        end
        drawSparkline(1, 34, 43, 60, slot)
    end
end

local function run(event)
    lcd.clear()
    if not ready then startup() end
    if not ready then
        lcd.drawText(1, 1, "horz_cfg.lua?", SMLSIZE + INVERS)
        return 0
    end
    if event == EVT_MENU_LONG and not menu then
        local chunk = loadScript(DIR .. "horz_menu")
        if chunk then
            menu = chunk()
        else
            menuFailUntil = getTime() + 200
        end
    end
    if menu then
        local status = menu.run(event, cfg)
        if status == "save" then
            dirty = true
        elseif status == "exit" then
            menu, dirty = nil, true
            collectgarbage()
        end
        if status ~= "exit" then return 0 end
    end
    if dirty then
        dirty = not reprepare()
        collectgarbage()
    end

    for i = 1, SLOT_COUNT do
        local value = 0
        if pSrc[i] ~= "" then value = readSlot(pSrc[i]) end
        slotValues[i] = value
        if track[i] then
            sessionMin[i] = math.min(sessionMin[i] or value, value)
            sessionMax[i] = math.max(sessionMax[i] or value, value)
        end
        if value ~= lastVal[i] then
            lastVal[i] = value
            if i <= STANDARD_SLOT_COUNT then
                valText[i] = string.format(valFmt[i], value)
                bothText[i] = string.format(fmtBoth[i], value)
                lineText[i] = string.format(fmtLine[i], value)
                vLen[i], bLen[i] = charLen(valText[i]), charLen(bothText[i])
            end
        end
    end
    local alt = 0
    if altSrc ~= "" then
        alt = readSlot(altSrc)
        if isFinite(alt) then
            filteredAlt = alt * 0.25 + filteredAlt * 0.75
        end
    end
    local pitch, roll = getAttitude()
    local rawHdg = (tonumber(getValue("Hdg")) or 0) * ((invHdg == 1) and -1 or 1)
    rawHdg = (rawHdg % 360 + 360) % 360
    local headingDiff = ((rawHdg - filteredHdg + 180) % 360) - 180
    filteredHdg = (filteredHdg + headingDiff * 0.3) % 360
    local hdg = math.floor(filteredHdg + 0.5) % 360
    local fix = math.max(0, math.min(3, math.floor(tonumber(getValue("Gfix")) or 0)))
    local gpsLat, gpsLon = gpsCoordinates()
    -- Home wird beim ersten gueltigen 3D-Fix nach Lua-Start gesetzt.
    if fix == 3 and not homeLat and gpsLat and gpsLon then
        homeLat, homeLon = gpsLat, gpsLon
    end
    local homeBearing = homeDirection(gpsLat, gpsLon)

    local cx, sizeW, cy, sizeH = 76, 26, 35, 28
    local pitchOffset, dx, dy
    if viewMode == 1 then
        draw3DAttitude(cx, cy, sizeW, sizeH, pitch, roll)
    else
        pitchOffset = math.max(math.min(pitch * 0.6, sizeH - 2), -(sizeH - 2))
        local rollAngle = roll * 0.01745329252
        dx, dy = math.cos(rollAngle) * (sizeW - 1), math.sin(rollAngle) * (sizeW - 1)
        local isUpsideDown = math.abs(roll) > 90
        if groundMode > 0 then
            for y = cy - sizeH + 1, cy + sizeH - 1 do
                local left, right = cx - sizeW + 1, cx + sizeW - 1
                if math.abs(dy) > 0.01 then
                    local cross = math.floor(cx + ((y - cy - pitchOffset) * dx) / dy)
                    if dy > 0 then
                        right = math.min(right, cross)
                    else
                        left = math.max(left, cross)
                    end
                elseif (pitchOffset >= 0 and not isUpsideDown) or (pitchOffset < 0 and isUpsideDown) then
                    if y <= cy + pitchOffset then left = right + 1 end
                elseif y >= cy + pitchOffset then
                    left = right + 1
                end
                if left <= right then
                    if groundMode == 1 and y % 2 == 0 then
                        lcd.drawLine(left, y, right, y, SOLID, FORCE)
                    elseif groundMode == 2 then
                        for x = left + ((left + y) % 2), right, 2 do lcd.drawPoint(x, y) end
                    end
                end
            end
        end
    end
    lcd.drawRectangle(cx - sizeW, cy - sizeH, sizeW * 2, sizeH * 2, FORCE)
    lcd.drawLine(cx - sizeW - 5, cy, cx - sizeW - 1, cy, SOLID, FORCE)
    lcd.drawLine(cx + sizeW, cy, cx + sizeW + 4, cy, SOLID, FORCE)
    lcd.drawLine(cx - 2, cy, cx + 2, cy, SOLID, FORCE)
    lcd.drawLine(cx, cy - 2, cx, cy + 2, SOLID, FORCE)
    if viewMode == 0 then
        lcd.drawLine(cx - dx, cy - dy + pitchOffset, cx + dx, cy + dy + pitchOffset, SOLID, FORCE)
    end
    if altSrc ~= "" then
        -- Eine halbe Boxhoehe entspricht 5 m; kleine Striche liegen bei 2,5-m-Schritten.
        local metersPerPixel = ALTITUDE_METERS_PER_HALFBOX / sizeH
        local halfStep = math.floor(alt / ALTITUDE_TICK_METERS)
        for tick = -4, 4 do
            local level = halfStep + tick
            local tickAltitude = level * ALTITUDE_TICK_METERS
            local y = math.floor(cy + (tickAltitude - alt) / metersPerPixel + 0.5)
            if y >= cy - sizeH + 2 and y <= cy + sizeH - 2 then
                local length = (level % 2 == 0) and 5 or 3
                lcd.drawLine(cx - sizeW, y, cx - sizeW + length, y, SOLID, FORCE)
            end
        end
    end
    local now = getTime()
    local warningActive = updateGPSWarning(fix, now)
    local satelliteVisible = false
    local satelliteX, satelliteY = cx - sizeW - 14, cy - sizeH - 7
    if fix > 0 then
        local blinkOn = (now % 80) < 60
        local satsX = cx - sizeW - 7
        if (fix ~= 1 or blinkOn) and (not warningActive or blinkOn) then
            satelliteVisible = true
        end
        local sats = math.max(0, math.floor((tonumber(getValue("Sats")) or 0) + 0.5))
        lcd.drawText(satsX + 7, cy - sizeH + 3, string.format("%.0f", sats), SMLSIZE + RIGHT)
    end
    if insideEnabled == 1 then
        local insideValue = 0
        if insideIsAlt then
            insideValue = filteredAlt
        elseif insideSrc ~= "" then
            insideValue = readSlot(insideSrc)
        end
        lcd.drawText(cx, cy - 13, string.format(insideFmt, insideValue), SMLSIZE + CENTER)
    end

    local yBottom = cy - sizeH - 1
    lcd.drawLine(cx, yBottom, cx, yBottom - 3, SOLID, FORCE)
    for i = -6, 6 do
        local angle = (math.floor(hdg / 5) + i) * 5
        local normalized = math.floor((angle % 360 + 360) % 360)
        local diff = ((angle - hdg + 180) % 360) - 180
        local x = cx + diff * COMPASS_PIXELS_PER_DEGREE
        if x >= cx - sizeW and x <= cx + sizeW then
            lcd.drawLine(x, yBottom - 2, x, yBottom, SOLID, FORCE)
            if normalized % 45 == 0 then
                lcd.drawText(x - ((#headingLabels[normalized] == 2) and 4 or 2),
                    yBottom - 6, headingLabels[normalized], SMLSIZE)
            end
        end
    end
    if homeBearing and fix >= 2 then
        drawHomePointer(homeBearing, hdg, cx, cy - sizeH, sizeW)
    end

    drawLeftColumn()
    for i = 7, 9 do
        if pShow[i] then
            local row = i - 7
            lcd.drawText(127, 1 + row * 17, pLabel[i], SMLSIZE + RIGHT)
            lcd.drawText(127, 9 + row * 17, bothText[i], SMLSIZE + RIGHT)
        end
    end
    lcd.drawText(127, 51, string.format("%.0fP°", pitch), SMLSIZE + RIGHT)
    lcd.drawText(127, 58, string.format("%.0fR°", roll), SMLSIZE + RIGHT)
    if satelliteVisible then drawSatellite(satelliteX, satelliteY, fix) end
    if cfg.configSaveFailed then
        lcd.drawText(42, 0, "SAVE FAILED", SMLSIZE + INVERS)
    elseif cfg.configLoadWarning then
        lcd.drawText(52, 0, "OLD CFG", SMLSIZE + INVERS)
    end
    if menuFailUntil > 0 then
        if getTime() < menuFailUntil then
            lcd.drawText(1, 58, "horz_menu.lua?", SMLSIZE + INVERS)
        else
            menuFailUntil = 0
        end
    end
    if DEBUG_MEM then
        local used = collectgarbage("count")
        if used > memPeak then memPeak = used end
        lcd.drawText(1, 0, string.format("%d/%d/%dK", used, memPeak, memInit), SMLSIZE + INVERS)
    end
    return 0
end

return { init = init, run = run }
