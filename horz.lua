-- Künstlicher Horizont und Telemetrie Sensor Anzeige für FrSky Sensoren (QX7 - EdgeTX 2.10/2.11 BW Display) -- @frittna 08.Okt.2026
--> Das LUA Script ist entsanden beim Projekt github.com/frittna/NazaDecoder-S.Port-Telemetrie-Bridge-MPU


local invPitch, invRoll, invHdg = 0, 0, 0
local groundMode, attitudeMode, viewMode = 0, 1, 1
local pitchSource, rollSource = "Ptch", "Roll"
local insideSource, insideEnabled = "Alt", 1
local altimeterSource = "Alt"
local graphSeconds = 30 -- Graph X-Time (10..999 s)
-- Archer seitlich: Nase unten = AccX+, rechte Tragfläche unten = AccZ+, unten = AccY+.
local fwdAxis, sideAxis, downAxis = "X+", "Z-", "Y+"
local filteredAlt, filteredHdg = 0, 0
local homeLat, homeLon
local gpsFix3Since, gpsLowFixSince, gpsWarningSince = nil, nil, nil
local menuActive, menuPage, selectedRow = false, 1, 1
local editField, editCharIdx, menuOpenTime = 0, 1, 0
local calibrationStep, calibrationLevel = 0, nil
local calibrationMessage = ""
local axisMessage = ""
local configSaveFailed = false
local configLoadWarning = false
local axisEditing = false
local configLoaded = false
local MENU_OPEN_DEBOUNCE = 50 -- getTime zaehlt in 10-ms-Ticks.
-- V2: Das Leselimit 1024 Byte laesst Reserve fuer zusaetzliche Einstellungen.
local CONFIG_READ_LIMIT = 1024
local ALTITUDE_TICK_METERS, ALTITUDE_METERS_PER_HALFBOX = 2.5, 5
-- Der Durchmesser enthaelt den Faktor 2 der Haversine-Distanz.
local EARTH_MEAN_DIAMETER_METERS = 12742000
local HOME_MIN_DISTANCE_METERS, COMPASS_PIXELS_PER_DEGREE = 5, 0.75
local SLOT_NAME_MAX, SLOT_NAME_VISIBLE = 12, 4
local atan2 = math.atan2 or function(y, x)
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + ((y >= 0) and math.pi or -math.pi) end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

local defaults = {
    names = { "RX", "Alt", "+/-", "Spd", "Dist", "Head", "Batt", "celD", "Amp" },
    sources = { "RSSI", "Alt", "VSpd", "GSpd", "Dist", "Hdg", "Cels", "celD", "Curr" },
    units = { "dB", "m", "m/s", "kmh", "m", "°", "V", "V", "A" }
}
local sName, sSrc, sUnit = {}, {}, {}

local catalog = {
    { "RSSI", "%.0f", 1, "dB" }, { "Alt", "%.0f", 1, "m" },
    { "GSpd", "%.0f", 1, "kmh" }, { "Dist", "%.0f", 1, "m" },
    { "VSpd", "%.1f", 1, "m/s" }, { "Hdg", "%.0f", 1, "°" },
    { "Cels", "%.1f", 1, "V" }, { "celD", "%.2f", 1, "V" },
    { "VFAS", "%.1f", 1, "V" }, { "Curr", "%.1f", 1, "A" },
    { "Tmp1", "%.0f", 1, "C" }, { "Tmp2", "%.0f", 1, "C" },
    { "Ptch", "%.0f", 1, "°" }, { "Roll", "%.0f", 1, "°" }, 
    { "AccX", "%.2f", 1, "g" }, { "AccY", "%.2f", 1, "g" },
    { "AccZ", "%.2f", 1, "g" }, { "GAlt", "%.0f", 1, "m" },
    { "Sats", "%.0f", 1, "" }, { "Gfix", "%.0f", 1, "" },
    { "A1", "%.2f", 1, "V" }, { "A2", "%.2f", 1, "V" }
      
}
local catalogByName = {}
for i = 1, #catalog do
    catalogByName[string.lower(catalog[i][1])] = catalog[i]
end
local slotValues, slotFormats = {}, {}
local headingLabels = {
    [0] = "N", [45] = "NO", [90] = "O", [135] = "SO",
    [180] = "S", [225] = "SW", [270] = "W", [315] = "NW"
}
local allowedChars = " aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ0123456789-+_.*() "  --Leerzeichen am Anfang (null-Abstand) und am Ende; Zeichenwahl ohne Endlosscrollen

local function trim(str)
    if not str then return "" end
    return (string.gsub(tostring(str), "^%s*(.-)%s*$", "%1"))
end

local function padStr(str, len)
    str = tostring(str or "")
    if #str < len then str = str .. string.rep(" ", len - #str) end
    return string.sub(str, 1, len)
end

local function modelPath()
    local info = model.getInfo()
    local name = string.gsub((info and info.name) or "model", "[ %c%p]", "_")
    return "/LOGS/hz_" .. name .. ".cfg"
end

local function setDefaults()
    invPitch, invRoll, invHdg = 0, 0, 0
    groundMode, attitudeMode, viewMode = 0, 1, 1
    pitchSource, rollSource = "Ptch", "Roll"
    insideSource, insideEnabled = "Alt", 1
    altimeterSource = "Alt"
    graphSeconds = 30
    fwdAxis, sideAxis, downAxis = "X+", "Z-", "Y+"
    for i = 1, 9 do
        sName[i], sSrc[i], sUnit[i] = defaults.names[i], defaults.sources[i], defaults.units[i]
    end
end

local function validAxis(value)
    return value == "X+" or value == "X-" or value == "Y+" or value == "Y-" or
        value == "Z+" or value == "Z-"
end

local function validText(value, maxLen)
    if #value > maxLen then return false end
    for i = 1, #value do
        if not string.find(allowedChars, string.sub(value, i, i), 1, true) then return false end
    end
    return true
end

local function loadConfig()
    setDefaults()
    configLoadWarning = false
    local f = io.open(modelPath(), "r")
    if f then
        local contents, total = "", 0
        while total < CONFIG_READ_LIMIT do
            local chunk = io.read(f, math.min(128, CONFIG_READ_LIMIT - total))
            if not chunk or #chunk == 0 then break end
            contents = contents .. chunk
            total = total + #chunk
        end
        io.close(f)
        if contents then
            local firstLine = true
            for line in string.gmatch(contents, "[^\r\n]+") do
                if firstLine then
                    firstLine = false
                    if line ~= "HORZCFG=2" then
                        configLoadWarning = true
                        break
                    end
                else
                    local key, value = string.match(line, "^([^=]+)=(.*)$")
                    if key == "MODE" and (value == "ANGLES" or value == "VECTOR") then
                        attitudeMode = (value == "VECTOR") and 2 or 1
                    elseif key == "VIEW" and (value == "CLASSIC" or value == "3D") then
                        viewMode = (value == "3D") and 1 or 0
                    elseif key == "INVERT" then
                        local p, r, h = string.match(value, "^(%d),(%d),(%d)$")
                        if p and tonumber(p) <= 1 and tonumber(r) <= 1 and tonumber(h) <= 1 then
                            invPitch, invRoll, invHdg = tonumber(p), tonumber(r), tonumber(h)
                        end
                    elseif key == "GROUND" then
                        local ground = tonumber(value)
                        if ground and ground % 1 == 0 and ground >= 0 and ground <= 2 then
                            groundMode = ground
                        end
                    elseif key == "SOURCES" then
                        local p, r = string.match(value, "^(.-),(.-)$")
                        if p ~= nil and r ~= nil and validText(p, 4) and validText(r, 4) then
                            pitchSource, rollSource = p, r
                        end
                    elseif key == "INSIDE" then
                        local source, enabled = string.match(value, "^(.-),([01])$")
                        if source and validText(source, 4) then
                            insideSource, insideEnabled = source, tonumber(enabled)
                        end
                    elseif key == "ALTIMETER-SCALE" and validText(value, 4) then
                        altimeterSource = value
                    elseif key == "GRAPHTIME" then
                        local secs = tonumber(value)
                        if secs and secs % 1 == 0 and secs >= 10 and secs <= 999 then
                            graphSeconds = secs
                        end
                    elseif key == "AXES" then
                        local fwd, side, down = string.match(value, "^([^,]+),([^,]+),([^,]+)$")
                        if fwd and side and down and validAxis(fwd) and validAxis(side) and validAxis(down) and
                            string.sub(fwd, 1, 1) ~= string.sub(side, 1, 1) and
                            string.sub(fwd, 1, 1) ~= string.sub(down, 1, 1) and
                            string.sub(side, 1, 1) ~= string.sub(down, 1, 1) then
                            fwdAxis, sideAxis, downAxis = fwd, side, down
                        end
                    elseif key == "SLOT" then
                        local iText, name, source, unit =
                            string.match(value, "^(%d+)|([^|]*)|([^|]*)|([^|]*)$")
                        local i = tonumber(iText)
                        if iText and name and source and unit and i and i % 1 == 0 and
                            i >= 1 and i <= 9 and validText(name, SLOT_NAME_MAX) and
                            validText(source, 4) and validText(unit, 3) then
                            sName[i], sSrc[i], sUnit[i] = name, source, unit
                        end
                    end
                end
            end
        end
    end
    configLoaded = true
end

local function saveConfig()
    -- Leerzeichen am Rand werden erst beim Beenden der Eingabe entfernt
    pitchSource, rollSource, altimeterSource = trim(pitchSource), trim(rollSource), trim(altimeterSource)
    for i = 1, 9 do sName[i], sSrc[i], sUnit[i] = trim(sName[i]), trim(sSrc[i]), trim(sUnit[i]) end
    local f = io.open(modelPath(), "w")
    if not f then
        configSaveFailed = true
        return false
    end
    io.write(f, "HORZCFG=2\n")
    io.write(f, "MODE=" .. ((attitudeMode == 1) and "ANGLES" or "VECTOR") .. "\n")
    io.write(f, "VIEW=" .. ((viewMode == 1) and "3D" or "CLASSIC") .. "\n")
    io.write(f, "INVERT=" .. invPitch .. "," .. invRoll .. "," .. invHdg .. "\n")
    io.write(f, "GROUND=" .. groundMode .. "\n")
    io.write(f, "SOURCES=" .. pitchSource .. "," .. rollSource .. "\n")
    io.write(f, "INSIDE=" .. insideSource .. "," .. insideEnabled .. "\n")
    io.write(f, "ALTIMETER-SCALE=" .. trim(altimeterSource) .. "\n")
    io.write(f, "GRAPHTIME=" .. graphSeconds .. "\n")
    io.write(f, "AXES=" .. fwdAxis .. "," .. sideAxis .. "," .. downAxis .. "\n")
    for i = 1, 9 do
        io.write(f, "SLOT=" .. i .. "|" .. trim(sName[i]) .. "|" ..
            trim(sSrc[i]) .. "|" .. trim(sUnit[i]) .. "\n")
    end
    io.close(f)
    configSaveFailed = false
    configLoadWarning = false
    return true
end

local charPos, charPosKey = 0, ""
local function changeChar(text, index, delta)
    local char = string.sub(text, index, index)
    local position = string.find(allowedChars, char, 1, true) or 1
    -- Leerzeichen gibt es am Anfang und am Ende der Liste: gemerkte Position nutzen
    local key = menuPage .. ":" .. selectedRow .. ":" .. editField .. ":" .. index
    if char == " " and charPosKey == key and string.sub(allowedChars, charPos, charPos) == " " then
        position = charPos
    end
    position = math.max(1, math.min(#allowedChars, position + delta))
    charPos, charPosKey = position, key
    return string.sub(text, 1, index - 1) .. string.sub(allowedChars, position, position) ..
        string.sub(text, index + 1)
end

local function slotIndex()
    return (menuPage == 2) and selectedRow or (selectedRow + 6)
end

local function menuContentRows()
    if menuPage == 1 then return 7 end
    if menuPage == 2 then return 6 end
    if menuPage == 3 then return 6 end
    return 6
end

local function menuRows()
    return menuContentRows() + 1
end

local function nextMenuPage()
    if axisEditing then saveConfig() end
    menuPage = (menuPage % 4) + 1
    selectedRow = 1
    axisEditing = false
end

local function cycleCatalog(slot, delta)
    local found = 1
    for i = 1, #catalog do
        if string.lower(catalog[i][1]) == string.lower(trim(sSrc[slot])) then
            found = i
            break
        end
    end
    found = math.max(1, math.min(#catalog, found + delta))
    sSrc[slot] = catalog[found][1]
    sUnit[slot] = catalog[found][4]
end

local function cycleInsideSource(delta)
    local found = 1
    for i = 1, #catalog do
        if string.lower(catalog[i][1]) == string.lower(trim(insideSource)) then
            found = i
            break
        end
    end
    found = math.max(1, math.min(#catalog, found + delta))
    insideSource = catalog[found][1]
end

local function cycleAxis(which, delta)
    local current = (which == 1) and fwdAxis or ((which == 2) and sideAxis or downAxis)
    local sign = string.sub(current, 2, 2)
    local axes = { "X", "Y", "Z" }
    local at = string.find("XYZ", string.sub(current, 1, 1), 1, true) or 1
    local candidateAxis = axes[((at - 1 + delta) % 3) + 1]
    local assignments = { fwdAxis, sideAxis, downAxis }
    local owner
    for i = 1, 3 do
        if i ~= which and string.sub(assignments[i], 1, 1) == candidateAxis then owner = i end
    end
    if owner then
        assignments[owner] = string.sub(current, 1, 1) .. string.sub(assignments[owner], 2, 2)
    end
    assignments[which] = candidateAxis .. sign
    fwdAxis, sideAxis, downAxis = assignments[1], assignments[2], assignments[3]
    return owner ~= nil
end

local function handleMenu(event)
    if getTime() - menuOpenTime < MENU_OPEN_DEBOUNCE then return true end
    local negative = event == EVT_MINUS_FIRST or event == EVT_ROT_LEFT or event == EVT_VIRTUAL_PREV
    local positive = event == EVT_PLUS_FIRST or event == EVT_ROT_RIGHT or event == EVT_VIRTUAL_NEXT
    if editField > 0 then
        if menuPage == 3 and selectedRow == 4 and editField == 4 then
            if negative or positive then
                cycleInsideSource(positive and 1 or -1)
            elseif event == EVT_ENTER_BREAK or event == EVT_EXIT_BREAK then
                editField = 0
                saveConfig()
            end
            return true
        end
        if menuPage == 3 and selectedRow == 6 and editField == 5 then
            if negative or positive then
                altimeterSource = changeChar(padStr(altimeterSource, 4), editCharIdx,
                    negative and -1 or 1)
            elseif event == EVT_ENTER_BREAK then
                editCharIdx = editCharIdx + 1
                if editCharIdx > 4 then editField = 0; saveConfig() end
            elseif event == EVT_ENTER_LONG or event == EVT_EXIT_BREAK then
                editField = 0
                saveConfig()
            end
            return true
        end
        if menuPage == 1 and selectedRow == 7 and editField == 6 then
            if negative or positive then
                -- Drehgeber: 1 s, +/- Tasten: 10 s
                local isRotary = event == EVT_ROT_LEFT or event == EVT_ROT_RIGHT or
                    event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_NEXT
                local step = (isRotary and 1 or 10) * (positive and 1 or -1)
                graphSeconds = math.max(10, math.min(999, graphSeconds + step))
            elseif event == EVT_ENTER_BREAK or event == EVT_ENTER_LONG or event == EVT_EXIT_BREAK then
                editField = 0
                saveConfig()
            end
            return true
        end
        local text, maxLen, target
        if menuPage == 1 then
            if selectedRow == 2 then
                target, text = "pitch", pitchSource
            elseif selectedRow == 4 then
                target, text = "roll", rollSource
            else
                return true
            end
            maxLen = 4
        else
            local slot = slotIndex()
            target = (editField == 1) and "name" or ((editField == 2) and "source" or "unit")
            text = (target == "name" and sName[slot]) or
                (target == "source" and sSrc[slot]) or sUnit[slot]
            maxLen = (target == "name") and SLOT_NAME_VISIBLE or ((target == "unit") and 3 or 4)
        end
        -- Bei Slot-Quellen waehlt +/- Katalogsensoren; der Drehgeber editiert Zeichen.
        local isRotary = event == EVT_ROT_LEFT or event == EVT_ROT_RIGHT or
            event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_NEXT
        local isCatalogCycle = (negative or positive) and menuPage ~= 1 and editField == 2 and not isRotary
        if isCatalogCycle then
            cycleCatalog(slotIndex(), negative and -1 or 1)
        elseif negative or positive then
            local updated = changeChar(padStr(text, maxLen), editCharIdx, negative and -1 or 1)
            if menuPage == 1 then
                if target == "pitch" then pitchSource = updated
                elseif target == "roll" then rollSource = updated
                end
            elseif target == "altimeter" then altimeterSource = updated
            elseif target == "name" then sName[slotIndex()] = updated
            elseif target == "source" then sSrc[slotIndex()] = updated
            else sUnit[slotIndex()] = updated end
        elseif event == EVT_ENTER_LONG then
            editCharIdx = 1
            editField = editField + 1
            local final = (menuPage == 1) and 1 or 3
            if editField > final then editField = 0; saveConfig() end
        elseif event == EVT_ENTER_BREAK then
            editCharIdx = editCharIdx + 1
            if editCharIdx > maxLen then
                editCharIdx = 1
                editField = editField + 1
                local final = (menuPage == 1) and 1 or 3
                if editField > final then editField = 0; saveConfig() end
            end
        elseif event == EVT_EXIT_BREAK then
            editField = 0
            saveConfig()
        end
        return true
    end

    if menuPage == 4 and axisEditing and selectedRow <= 3 and (negative or positive) then
        if cycleAxis(selectedRow, positive and 1 or -1) then
            axisMessage = "Axes changed"
        else
            axisMessage = ""
        end
    elseif negative or positive then
        local delta = positive and 1 or -1
        selectedRow = math.max(1, math.min(menuRows(), selectedRow + delta))
    elseif event == EVT_PAGE_BREAK then
        nextMenuPage()
    elseif event == EVT_EXIT_BREAK then
        saveConfig()
        menuActive = false
        axisEditing = false
    elseif event == EVT_ENTER_BREAK then
        if selectedRow > menuContentRows() then
            nextMenuPage()
        elseif menuPage == 1 then
            if selectedRow == 1 then groundMode = (groundMode + 1) % 3
            elseif selectedRow == 2 or selectedRow == 4 then editField = 1; editCharIdx = 1
            elseif selectedRow == 3 then invPitch = 1 - invPitch
            elseif selectedRow == 5 then invRoll = 1 - invRoll
            elseif selectedRow == 6 then invHdg = 1 - invHdg
            elseif selectedRow == 7 then editField = 6
            end
            if selectedRow == 1 or selectedRow == 3 or selectedRow == 5 or selectedRow == 6 then
                saveConfig()
            end
        elseif menuPage == 2 or menuPage == 3 then
            if menuPage == 3 and selectedRow == 4 then
                editField = 4
            elseif menuPage == 3 and selectedRow == 5 then
                insideEnabled = 1 - insideEnabled
                saveConfig()
            elseif menuPage == 3 and selectedRow == 6 then
                editField = 5
                editCharIdx = 1
            else
                editField = 1
                editCharIdx = 1
            end
        elseif menuPage == 4 then
            if selectedRow == 5 then
                attitudeMode = (attitudeMode == 1) and 2 or 1
                saveConfig()
            elseif selectedRow == 4 then
                viewMode = 1 - viewMode
                saveConfig()
            elseif selectedRow <= 3 then
                if axisEditing then
                    local axis = (selectedRow == 1 and fwdAxis) or (selectedRow == 2 and sideAxis) or downAxis
                    local value = string.sub(axis, 1, 1) ..
                        ((string.sub(axis, 2, 2) == "+") and "-" or "+")
                    if selectedRow == 1 then fwdAxis = value
                    elseif selectedRow == 2 then sideAxis = value
                    else downAxis = value end
                    axisEditing = false
                    saveConfig()
                else
                    axisEditing = true
                    axisMessage = ""
                end
            elseif selectedRow == 6 then
                calibrationStep = 1
                calibrationLevel = nil
                calibrationMessage = ""
            end
        end
    end
    return true
end

local function vectorValues()
    return {
        tonumber(getValue("AccX")) or 0,
        tonumber(getValue("AccY")) or 0,
        tonumber(getValue("AccZ")) or 0
    }
end

local function vectorMagnitude(values)
    return math.sqrt(values[1] * values[1] + values[2] * values[2] + values[3] * values[3])
end

local function axisValue(values, setting)
    local index = string.sub(setting, 1, 1) == "X" and 1 or
        (string.sub(setting, 1, 1) == "Y" and 2 or 3)
    return values[index] * ((string.sub(setting, 2, 2) == "-") and -1 or 1)
end

local function calibrate(event)
    local values = vectorValues()
    if calibrationStep == 1 and event == EVT_ENTER_BREAK then
        local magnitude = vectorMagnitude(values)
        if magnitude < 0.001 then
            calibrationMessage = "no Acc-Signal"
            return
        end
        local index = 1
        if math.abs(values[2]) > math.abs(values[index]) then index = 2 end
        if math.abs(values[3]) > math.abs(values[index]) then index = 3 end
        local axis = ({ "X", "Y", "Z" })[index]
        downAxis = axis .. ((values[index] >= 0) and "+" or "-")
        calibrationLevel = { values = values, down = index, magnitude = magnitude }
        calibrationStep = 2
        calibrationMessage = "Level set"
    elseif calibrationStep == 2 and (event == EVT_ENTER_BREAK) then
        local remain = {}
        for i = 1, 3 do if i ~= calibrationLevel.down then remain[#remain + 1] = i end end
        local magnitude = vectorMagnitude(values)
        local tilt = math.sqrt(values[remain[1]] ^ 2 + values[remain[2]] ^ 2)
        if magnitude < calibrationLevel.magnitude * 0.5 then
            calibrationMessage = "no Acc-Signal"
            return
        end
        if tilt < magnitude * 0.15 then
            calibrationMessage = "turn nose more"
            return
        end
        local forward = (math.abs(values[remain[1]]) >= math.abs(values[remain[2]])) and remain[1] or remain[2]
        local other = (forward == remain[1]) and remain[2] or remain[1]
        fwdAxis = ({ "X", "Y", "Z" })[forward] .. ((values[forward] >= 0) and "+" or "-")
        local fSign = string.sub(fwdAxis, 2, 2) == "+" and 1 or -1
        local dSign = string.sub(downAxis, 2, 2) == "+" and 1 or -1
        local fVec = { 0, 0, 0 }; fVec[forward] = fSign
        local sideVector = { 0, 0, 0 }
        sideVector[other] = 1
        local cross = {
            fVec[2] * sideVector[3] - fVec[3] * sideVector[2],
            fVec[3] * sideVector[1] - fVec[1] * sideVector[3],
            fVec[1] * sideVector[2] - fVec[2] * sideVector[1]
        }
        local sideSign = (cross[calibrationLevel.down] * dSign >= 0) and 1 or -1
        sideAxis = ({ "X", "Y", "Z" })[other] .. ((sideSign > 0) and "+" or "-")
        calibrationStep = 0
        calibrationLevel = nil
        calibrationMessage = "Calibration OK"
        saveConfig()
    end
end

local function editDisplay(value, length, selectedIndex)
    local padded = padStr(value, length)
    local index = selectedIndex or editCharIdx
    return string.sub(padded, 1, index - 1) .. "[" ..
        string.sub(padded, index, index) .. "]" ..
        string.sub(padded, index + 1)
end

local function drawMenu(event)
    local titles = {
        "--CONFIG PAGE--", "--SENSOR PAGE 1--",
        "--SENSOR PAGE 2--", "--AXIS SETTING--"
    }
    local heading = configSaveFailed and "SAVE FAILED" or
        (configLoadWarning and "OLD CFG: DEFAULTS" or titles[menuPage])
    lcd.drawText(1, 1, heading, INVERS + SMLSIZE)
    if calibrationStep > 0 then
        local values = vectorValues()
        lcd.drawText(1, 13, calibrationStep == 1 and "hold Model straigt" or "turn nose down", 0)
        lcd.drawText(1, 24, string.format("X:%.1f Y:%.1f Z:%.1f",
            tonumber(values[1]) or 0, tonumber(values[2]) or 0, tonumber(values[3]) or 0), SMLSIZE)
        lcd.drawText(1, 36, calibrationMessage, INVERS)
        lcd.drawText(1, 50, "ENTER: measure EXIT: end", SMLSIZE)
        return
    end
    if menuPage == 1 then
        local function line(n) return 9 + (n - 1) * 8 end
        local function checkbox(y, on, selected)
            lcd.drawText(80, y, "inv:", SMLSIZE)
            lcd.drawText(104, y, on and "[X]" or "[ ]", selected and INVERS or 0)
        end
        lcd.drawText(1, line(1), " ", 0)
        lcd.drawText(8, line(1), "Ground:", (selectedRow == 1) and INVERS or 0)
        lcd.drawText(73, line(1), ({ "White", "Lines", "Points" })[groundMode + 1], 0)
        for k = 0, 1 do
            local item, y = 2 + k * 2, line(2 + k)
            local source = (k == 0) and pitchSource or rollSource
            lcd.drawText(8, y, (k == 0) and "Pitch:" or "Roll:",
                (selectedRow == item and editField == 0) and INVERS or 0)
            if selectedRow == item and editField > 0 then
                lcd.drawText(48, y, editDisplay(source, 4), INVERS + SMLSIZE)
            else
                lcd.drawText(48, y, trim(source), 0)
            end
            checkbox(y, ((k == 0) and invPitch or invRoll) == 1, selectedRow == item + 1)
        end
        lcd.drawText(8, line(4), "Heading:", 0)
        checkbox(line(4), invHdg == 1, selectedRow == 6)
        lcd.drawText(8, line(5), "Graph X-Time:",
            (selectedRow == 7 and editField == 0) and INVERS or 0)
        lcd.drawText(86, line(5), "[" .. graphSeconds .. "]",
            (selectedRow == 7 and editField == 6) and INVERS or 0)
        lcd.drawText(86 + (#tostring(graphSeconds) + 2) * 6, line(5), "s", 0)
        lcd.drawText(1, 49, "For Graph just one Sensor may", SMLSIZE)
        lcd.drawText(1, 54, "be aktive on left side.", SMLSIZE)
    elseif menuPage == 2 or menuPage == 3 then
        local first, last = menuPage == 2 and 1 or 7, menuPage == 2 and 6 or 9
        for i = first, last do
            local row = (menuPage == 2) and i or (i - 6)
            local y = 10 + (row - 1) * 8
            local selected = row == selectedRow
            local prefix = selected and ">" or " "
            lcd.drawText(1, y, prefix, 0)
            local editing = selected and editField > 0
            local fullName = padStr(editing and sName[i] or trim(sName[i]), SLOT_NAME_MAX)
            local name = string.sub(fullName, 1, SLOT_NAME_VISIBLE)
            local source = editing and tostring(sSrc[i]) or trim(sSrc[i])
            local unit = editing and tostring(sUnit[i]) or trim(sUnit[i])
            local nameText, sourceText, unitText = name, source, unit
            if selected and editField > 0 then
                if editField == 1 then
                    local start = math.max(1, math.min(editCharIdx - SLOT_NAME_VISIBLE + 1,
                        SLOT_NAME_MAX - SLOT_NAME_VISIBLE + 1))
                    local visible = string.sub(fullName, start, start + SLOT_NAME_VISIBLE - 1)
                    nameText = editDisplay(visible, SLOT_NAME_VISIBLE, editCharIdx - start + 1)
                elseif editField == 2 then sourceText = editDisplay(source, 4)
                else unitText = editDisplay(unit, 3) end
            end
            lcd.drawText(9, y, nameText, (selected and editField == 1) and INVERS or 0)
            lcd.drawText(35, y, ":", 0)
            lcd.drawText(41, y, sourceText, (selected and editField == 2) and INVERS or 0)
            lcd.drawText(72, y, "[" .. unitText .. "]", (selected and editField == 3) and INVERS or 0)
        end
        if menuPage == 3 then
            local sourceRowY, enabledRowY = 34, 42
            local sourceSelected = selectedRow == 4
            local enabledSelected = selectedRow == 5
            lcd.drawText(1, sourceRowY, sourceSelected and ">" or " ", sourceSelected and INVERS or 0)
            lcd.drawText(9, sourceRowY, "    inside Horizon",
                (sourceSelected and editField == 0) and INVERS or 0)
            lcd.drawText(127, sourceRowY, " " .. insideSource .. " ",
                RIGHT + ((sourceSelected and editField == 4) and INVERS or 0))
            lcd.drawText(1, enabledRowY, enabledSelected and ">" or " ",
                enabledSelected and INVERS or 0)
            lcd.drawText(127, enabledRowY,
                (insideEnabled == 1) and "is visible?:     [X]  " or "is visible?:     [ ]  ",
                RIGHT + ((enabledSelected and editField == 0) and INVERS or 0))
            local altimeterSelected = selectedRow == 6
            lcd.drawText(8, 50, "Altimeter-Scale:",
                ((altimeterSelected and editField == 0) and INVERS or 0))
            local altimeterText = padStr((altimeterSelected and editField == 5) and altimeterSource or
                trim(altimeterSource), 4)
            for i = 1, 4 do
                local flags = (altimeterSelected and editField == 5 and editCharIdx == i) and INVERS or 0
                lcd.drawText(104 + (i - 1) * 6, 50, string.sub(altimeterText, i, i), flags)
            end
        end
    else
        local rows = {
            "Forward: " .. fwdAxis, "Side: " .. sideAxis, "Down: " .. downAxis,
            "View: " .. ((viewMode == 1) and "3D" or "Classic"),
            "Attitude: " .. ((attitudeMode == 1) and "ANGLES" or "VECTOR"),
            "Calibrate Attitude"
        }
        for i = 1, #rows do
            local y = 10 + (i - 1) * 8
            local selected = i == selectedRow
            lcd.drawText(1, y, (selected and "> " or "  ") .. rows[i], selected and INVERS or 0)
        end
        if selectedRow ~= 6 then
            if calibrationMessage ~= "" then
                lcd.drawText(1, 50, calibrationMessage, SMLSIZE)
            elseif axisMessage ~= "" then
                lcd.drawText(1, 50, axisMessage, SMLSIZE)
            end
        end
    end
    local scrollSelected = selectedRow > menuContentRows()
    lcd.drawText(1, 58, scrollSelected and ">" or " ", scrollSelected and INVERS or 0)
    lcd.drawText(127, 58, "[scroll]", SMLSIZE + RIGHT +
        (scrollSelected and INVERS or 0))
end

local function init()
    menuActive, menuPage, selectedRow = false, 1, 1
    editField, editCharIdx, menuOpenTime = 0, 1, 0
    axisEditing = false
    calibrationStep, calibrationLevel, calibrationMessage = 0, nil, ""
    axisMessage, configSaveFailed = "", false
    configLoadWarning = false
    configLoaded = false
end

local function readSlot(source, unit)
    if trim(source) == "" then return 0, "%.1f" end
    local raw = getValue(source)
    if type(raw) == "table" then
        local total = 0
        for _, value in ipairs(raw) do total = total + (tonumber(value) or 0) end
        raw = total
    end
    local value = tonumber(raw) or 0
    local fmt, scale = "%.1f", 1
    local entry = catalogByName[string.lower(source)]
    if entry then
        fmt, scale = entry[2], entry[3]
    end
    if string.lower(source) == "gspd" and trim(unit) ~= "kmh" then scale = 1 end
    return value * scale, fmt
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

local function drawHomePointer(bearing, heading, cx, topY, sizeW)
    local delta = ((bearing - heading + 180) % 360) - 180
    local visibleLimit = (sizeW - 1) / COMPASS_PIXELS_PER_DEGREE
    local function drawFilledSideArrow(x, direction)
        for row = -3, 3 do
            local inset = math.abs(row)
            if direction == "left" then
                lcd.drawLine(x, topY + 4 + row, x + 6 - inset, topY + 4 + row, SOLID, FORCE)
            else
                lcd.drawLine(x - 6 + inset, topY + 4 + row, x, topY + 4 + row, SOLID, FORCE)
            end
        end
    end
    if delta < -visibleLimit then
        local x = cx - sizeW + 1
        drawFilledSideArrow(x, "left")
    elseif delta > visibleLimit then
        local x = cx + sizeW - 1
        drawFilledSideArrow(x, "right")
    else
        local x = math.floor(cx + delta * COMPASS_PIXELS_PER_DEGREE + 0.5)
        for row = 0, 3 do
            local halfWidth = row
            lcd.drawLine(x - halfWidth, topY - 1 + row, x + halfWidth, topY - 1 + row, SOLID, FORCE)
        end
    end
end

local function getAttitude()
    local pitch, roll
    if attitudeMode == 1 then
        pitch = (trim(pitchSource) ~= "") and (tonumber(getValue(pitchSource)) or 0) or 0
        roll = (trim(rollSource) ~= "") and (tonumber(getValue(rollSource)) or 0) or 0
    else
        local values = vectorValues()
        local fwd, side, down = axisValue(values, fwdAxis), axisValue(values, sideAxis), axisValue(values, downAxis)
        local magnitude = math.sqrt(fwd * fwd + side * side + down * down)
        if magnitude > 0.001 then fwd, side, down = fwd / magnitude, side / magnitude, down / magnitude
        else fwd, side, down = 0, 0, 1 end
        pitch = atan2(-fwd, math.sqrt(side * side + down * down)) * 57.2957795
        roll = atan2(side, down) * 57.2957795
    end
    pitch = pitch * ((invPitch == 1) and -1 or 1)
    roll = roll * ((invRoll == 1) and -1 or 1)
    return pitch, roll
end

local function draw3DAttitude(cx, cy, sizeW, sizeH, pitch, roll)
    local left, right = cx - sizeW + 1, cx + sizeW - 1
    local top, bottom = cy - sizeH + 1, cy + sizeH - 1
    local focal = sizeW
    local pitchRad, rollRad = pitch * 0.01745329252, roll * 0.01745329252

    local function planeLine(angle, dotted)
        local p = angle * 0.01745329252
        local a = -math.sin(rollRad) * math.cos(p)
        local b = math.cos(rollRad) * math.cos(p)
        local c = -focal * math.sin(p)
        local points = {}
        local function addPoint(x, y)
            if x >= left - 0.01 and x <= right + 0.01 and
                y >= top - 0.01 and y <= bottom + 0.01 then
                for i = 1, #points do
                    if math.abs(points[i][1] - x) < 0.1 and math.abs(points[i][2] - y) < 0.1 then
                        return
                    end
                end
                points[#points + 1] = { x, y }
            end
        end
        if math.abs(b) > 0.0001 then
            addPoint(left, cy - (a * (left - cx) + c) / b)
            addPoint(right, cy - (a * (right - cx) + c) / b)
        end
        if math.abs(a) > 0.0001 then
            addPoint(cx - (b * (top - cy) + c) / a, top)
            addPoint(cx - (b * (bottom - cy) + c) / a, bottom)
        end
        if #points < 2 then return end

        local x1, y1, x2, y2 = points[1][1], points[1][2], points[2][1], points[2][2]
        if dotted then
            local steps = math.max(math.abs(x2 - x1), math.abs(y2 - y1))
            if steps < 1 then return end
            for i = 0, math.floor(steps) do
                if i % 2 == 0 then
                    local t = i / steps
                    lcd.drawPoint(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t)
                end
            end
        else
            lcd.drawLine(x1, y1, x2, y2, SOLID, FORCE)
        end
    end

    local a = -math.sin(rollRad) * math.cos(pitchRad)
    local b = math.cos(rollRad) * math.cos(pitchRad)
    local c = -focal * math.sin(pitchRad)
    for y = top, bottom do
        local row = y - cy
        local leftGround, rightGround = left, right
        local centerValue = b * row + c
        if math.abs(a) > 0.0001 then
            local cross = cx - centerValue / a
            if a > 0 then leftGround = math.max(leftGround, math.ceil(cross))
            else rightGround = math.min(rightGround, math.floor(cross)) end
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

    -- Dezente 45°- und 90°-Marken mit beweglicher Pitch-/Roll-Anzeige.
    local pitchMarks = { -90, -45, 0, 45, 90 }
    for i = 1, #pitchMarks do
        if math.abs(pitchMarks[i]) < 90 then
            local y = cy - (pitchMarks[i] / 90) * sizeH
            lcd.drawLine(left + 1, y, left + 2, y, SOLID, FORCE)
            lcd.drawLine(right - 1, y, right - 2, y, SOLID, FORCE)
        end
    end
    local pitchY = cy - (math.max(-90, math.min(90, pitch)) / 90) * sizeH
    lcd.drawLine(left + 2, pitchY - 1, left + 2, pitchY + 1, SOLID, FORCE)
    lcd.drawLine(right - 2, pitchY - 1, right - 2, pitchY + 1, SOLID, FORCE)
    local rollMarks = { -90, -45, 0, 45, 90 }
    for i = 1, #rollMarks do
        if math.abs(rollMarks[i]) < 90 then
            local x = cx + (rollMarks[i] / 90) * sizeW
            lcd.drawLine(x, top + 1, x, top + 2, SOLID, FORCE)
            lcd.drawLine(x, bottom - 1, x, bottom - 2, SOLID, FORCE)
        end
    end
    local rollX = cx + (math.max(-90, math.min(90, roll)) / 90) * sizeW
    lcd.drawLine(rollX - 1, top + 2, rollX + 1, top + 2, SOLID, FORCE)
    lcd.drawLine(rollX - 1, bottom - 2, rollX + 1, bottom - 2, SOLID, FORCE)
end

-- Linke Spalte (Slots 1..6): passt sich der Zahl aktiver Slots an
local leftActive = {}
local SPARK_N = 40 -- Abtastintervall = graphSeconds / SPARK_N
local sparkBuf, sparkCount, sparkHead, sparkLast, sparkSlot, sparkSrc, sparkInterval = {}, 0, 0, 0, 0, nil, 0
local FONTS_BIG = { { MIDSIZE, 8 }, { 0, 6 }, { SMLSIZE, 5 } }
local FONTS_NORMAL = { { 0, 6 }, { SMLSIZE, 5 } }

local function pickFont(text, limit, fonts)
    local len = #text
    for _, f in ipairs(fonts) do
        if len * f[2] <= limit then return f[1] end
    end
    return SMLSIZE
end

-- Name gross zeichnen; passt "name:" nicht, zuerst Doppelpunkt weglassen
local function drawName(x, y, name, limit)
    if #name * 8 + 8 <= limit then
        lcd.drawText(x, y, name .. ":", MIDSIZE)
    elseif #name * 8 <= limit then
        lcd.drawText(x, y, name, MIDSIZE)
    else
        lcd.drawText(x, y, name .. ":", pickFont(name .. ":", limit, FONTS_BIG))
    end
end

-- Wert immer MIDSIZE, Einheit klein dahinter; nur wenn es nicht passt: Fallback nach Breite
local function drawBigValue(x, y, both, value, unit, limit)
    if #value * 8 + #unit * 5 <= limit then
        lcd.drawText(x, y, value, MIDSIZE)
        if unit ~= "" then lcd.drawText(x + #value * 8 + 1, y + 7, unit, SMLSIZE) end
    else
        lcd.drawText(x, y, both, pickFont(both, limit, FONTS_BIG))
    end
end

local function drawSparkline(x0, y0, x1, y1)
    local lo, hi = sparkBuf[1], sparkBuf[1]
    for i = 2, sparkCount do
        local v = sparkBuf[i]
        if v < lo then lo = v elseif v > hi then hi = v end
    end
    lcd.drawLine(x0, y1, x1, y1, SOLID, FORCE)
    if sparkCount < 2 then return end
    local span, h = hi - lo, y1 - y0 - 1
    local start = (sparkCount < SPARK_N) and 0 or sparkHead
    local px, py
    for k = 0, sparkCount - 1 do
        local v = sparkBuf[((start + k) % SPARK_N) + 1]
        local y = (span == 0) and (y0 + h / 2) or (y1 - 1 - (v - lo) / span * h)
        local x = x0 + k
        if px then lcd.drawLine(px, py, x, y, SOLID, FORCE) end
        px, py = x, y
    end
end

local function drawLeftColumn()
    local n = 0
    for i = 1, 6 do
        if string.sub(trim(sName[i]), 1, 4) ~= "" then
            n = n + 1
            leftActive[n] = i
        end
    end
    if n ~= 1 then sparkCount, sparkHead, sparkSlot = 0, 0, 0 end
    if n == 0 then return end
    local function text(k)
        local i = leftActive[k]
        return string.sub(trim(sName[i]), 1, 4),
            string.format(slotFormats[i], slotValues[i]) .. trim(sUnit[i]),
            string.format(slotFormats[i], slotValues[i]), trim(sUnit[i])
    end
    if n >= 4 then
        local step = (n == 6) and 11 or math.floor(55 / (n - 1))
        for k = 1, n do
            local name, value = text(k)
            lcd.drawText(1, 2 + (k - 1) * step, name .. ":" .. value, SMLSIZE)
        end
    elseif n == 3 then
        -- 3 Sensoren: Name und Wert gleich gross (normale Schrift), sonst SMLSIZE
        for k = 1, 3 do
            local name, value = text(k)
            local y = 1 + (k - 1) * 21
            local limit = (k == 1) and 33 or 43
            lcd.drawText(1, y, name .. ":", pickFont(name .. ":", limit, FONTS_NORMAL))
            lcd.drawText(1, y + 9, value, pickFont(value, limit, FONTS_NORMAL))
        end
    elseif n == 2 then
        -- 2 Sensoren: Name und Wert ganz gross (MIDSIZE), erster Name im GPS-Bereich begrenzt
        for k = 1, 2 do
            local name, both, value, unit = text(k)
            local y = 2 + (k - 1) * 32
            drawName(1, y, name, (k == 1) and 33 or 43)
            drawBigValue(1, y + 14, both, value, unit, 43)
        end
        lcd.drawLine(0, 31, 40, 31, SOLID, FORCE)
    else
        local i = leftActive[1]
        local name, both, value, unit = text(1)
        drawName(1, 1, name, 33)
        drawBigValue(1, 15, both, value, unit, 43)
        local interval = math.floor(graphSeconds * 100 / SPARK_N)
        if sparkSlot ~= i or sparkSrc ~= sSrc[i] or sparkInterval ~= interval then
            sparkCount, sparkHead, sparkLast, sparkSlot, sparkSrc, sparkInterval =
                0, 0, 0, i, sSrc[i], interval
        end
        local now = getTime()
        if sparkCount == 0 or now - sparkLast >= interval then
            sparkLast = now
            sparkBuf[sparkHead + 1] = slotValues[i]
            sparkHead = (sparkHead + 1) % SPARK_N
            if sparkCount < SPARK_N then sparkCount = sparkCount + 1 end
        end
        drawSparkline(1, 34, 43, 60)
    end
end

local function run(event)
    lcd.clear()
    if not configLoaded then loadConfig() end
    if event == EVT_MENU_LONG then
        if menuActive and axisEditing then saveConfig() end
        menuActive, menuPage, selectedRow, editField = true, 1, 1, 0
        axisEditing = false
        menuOpenTime = getTime()
    end
    if menuActive then
        if calibrationStep > 0 then
            if event == EVT_EXIT_BREAK then
                calibrationStep = 0
                calibrationLevel = nil
                calibrationMessage = "Calib. aborted"
            else
                calibrate(event)
            end
        else
            handleMenu(event)
        end
        drawMenu(event)
        return 0
    end

    for i = 1, 9 do slotValues[i], slotFormats[i] = readSlot(trim(sSrc[i]), sUnit[i]) end
    filteredAlt = slotValues[2] * 0.25 + filteredAlt * 0.75
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
                    if dy > 0 then right = math.min(right, cross)
                    else left = math.max(left, cross) end
                elseif (pitchOffset >= 0 and not isUpsideDown) or (pitchOffset < 0 and isUpsideDown) then
                    if y <= cy + pitchOffset then left = right + 1 end
                elseif y >= cy + pitchOffset then left = right + 1 end
                if left <= right then
                    if groundMode == 1 and y % 2 == 0 then lcd.drawLine(left, y, right, y, SOLID, FORCE)
                    elseif groundMode == 2 then
                        for x = left + ((left + y) % 2), right, 2 do lcd.drawPoint(x, y) end
                    end
                end
            end
        end
    end
    lcd.drawRectangle(cx - sizeW, cy - sizeH, sizeW * 2, sizeH * 2, FORCE)
    lcd.drawLine(cx - sizeW - 5, cy, cx - sizeW - 1, cy, SOLID, FORCE)
    lcd.drawLine(cx + sizeW , cy, cx + sizeW + 4, cy, SOLID, FORCE)
    lcd.drawLine(cx - 2, cy, cx + 2, cy, SOLID, FORCE)
    lcd.drawLine(cx, cy - 2, cx, cy + 2, SOLID, FORCE)
    if viewMode == 0 then
        lcd.drawLine(cx - dx, cy - dy + pitchOffset, cx + dx, cy + dy + pitchOffset, SOLID, FORCE)
    end
    if trim(altimeterSource) ~= "" then
        local alt = readSlot(trim(altimeterSource), "")
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
    if fix > 0 then
        local blinkOn = (now % 80) < 60
        local satsX = cx - sizeW - 7
        if (fix ~= 1 or blinkOn) and (not warningActive or blinkOn) then
            drawSatellite(satsX - 8, cy - sizeH - 5, fix)
        end
        local sats = math.max(0, math.floor((tonumber(getValue("Sats")) or 0) + 0.5))
        lcd.drawText(satsX + 1 , cy - sizeH + 3, string.format("%.0f", sats), SMLSIZE)
    end
    --lcd.drawText(cx + sizeW - 1, cy - sizeH + 2, fix == 3 and "3D" or (fix == 2 and "2D" or "nF"), SMLSIZE + RIGHT)  --rausgenommen aus horiz.box, da jetzt mit satelliten symbol gelöst
    if insideEnabled == 1 then
        local entry = catalogByName[string.lower(trim(insideSource))]
        local insideUnit = entry and entry[4] or ""
        local insideValue, insideFormat = readSlot(trim(insideSource), insideUnit)
        if string.lower(trim(insideSource)) == "alt" then insideValue = filteredAlt end
        local insideName = entry and entry[1] or trim(insideSource)
        lcd.drawText(cx, cy - 13, insideName .. ":" ..
            string.format(insideFormat, insideValue) .. insideUnit, SMLSIZE + CENTER)
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
        local name, unit = string.sub(trim(sName[i]), 1, 4), trim(sUnit[i])
        if name ~= "" then
            local value = string.format(slotFormats[i], slotValues[i])
            do
                local row = i - 7
                lcd.drawText(127, 1 + row * 17, name .. ":", SMLSIZE + RIGHT)
                lcd.drawText(127, 9 + row * 17, value .. unit, SMLSIZE + RIGHT)
            end
        end
    end
    lcd.drawText(127, 51, string.format("%.0f", pitch) .. "°Y", SMLSIZE + RIGHT)
    lcd.drawText(128, 58, string.format("%.0f", roll) .. "°X", SMLSIZE + RIGHT)
    if configSaveFailed then lcd.drawText(42, 0, "SAVE FAILED", SMLSIZE + INVERS)
    elseif configLoadWarning then lcd.drawText(52, 0, "OLD CFG", SMLSIZE + INVERS) end
    return 0
end

return { init = init, run = run }
