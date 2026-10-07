-- Künstlicher Horizont für FrSky Sensoren (QX7 - EdgeTX 2.10/2.11 BW Display) -- @frittna 07.Okt.2026

local invPitch, invRoll, invHdg = 0, 0, 0
local groundMode, attitudeMode = 0, 1
local pitchSource, rollSource = "Ptch", "Roll"
-- Archer seitlich: Nase unten = AccX+, rechte Tragfläche unten = AccZ+, unten = AccY+.
local fwdAxis, sideAxis, downAxis = "X+", "Z-", "Y+"
local filteredAlt, filteredHdg = 0, 0
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
-- V2: max. 338 Byte (77 fest + 9*29 je Slot); Leselimit 1024 laesst Reserve.
local CONFIG_READ_LIMIT = 1024
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
    { "GSpd", "%.0f", 1.852, "kmh" }, { "Dist", "%.0f", 1, "m" },
    { "VSpd", "%.1f", 1, "m/s" }, { "Hdg", "%.0f", 1, "°" },
    { "Cels", "%.1f", 1, "V" }, { "VFAS", "%.1f", 1, "V" },
    { "Curr", "%.1f", 1, "A" }, { "Sats", "%.0f", 1, "" },
    { "GFix", "%.0f", 1, "" }, { "Ptch", "%.0f", 1, "°" },
    { "Roll", "%.0f", 1, "°" }, { "AccX", "%.2f", 1, "g" },
    { "AccY", "%.2f", 1, "g" }, { "AccZ", "%.2f", 1, "g" },
    { "Tmp1", "%.0f", 1, "C" }, { "Tmp2", "%.0f", 1, "C" },
    { "A1", "%.2f", 1, "V" }, { "A2", "%.2f", 1, "V" },
    { "celD", "%.2f", 1, "V" }
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
local allowedChars = " ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-+_.:*()&$"

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
    groundMode, attitudeMode = 0, 1
    pitchSource, rollSource = "Ptch", "Roll"
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
        local chunks, total = {}, 0
        while total < CONFIG_READ_LIMIT do
            local chunk = io.read(f, math.min(128, CONFIG_READ_LIMIT - total))
            if not chunk or #chunk == 0 then break end
            chunks[#chunks + 1] = chunk
            total = total + #chunk
        end
        io.close(f)
        local contents = table.concat(chunks)
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
    local f = io.open(modelPath(), "w")
    if not f then
        configSaveFailed = true
        return false
    end
    io.write(f, "HORZCFG=2\n")
    io.write(f, "MODE=" .. ((attitudeMode == 1) and "ANGLES" or "VECTOR") .. "\n")
    io.write(f, "INVERT=" .. invPitch .. "," .. invRoll .. "," .. invHdg .. "\n")
    io.write(f, "GROUND=" .. groundMode .. "\n")
    io.write(f, "SOURCES=" .. pitchSource .. "," .. rollSource .. "\n")
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

local function changeChar(text, index, delta)
    local char = string.sub(text, index, index)
    local position = string.find(allowedChars, char, 1, true) or 1
    position = math.max(1, math.min(#allowedChars, position + delta))
    return string.sub(text, 1, index - 1) .. string.sub(allowedChars, position, position) ..
        string.sub(text, index + 1)
end

local function slotIndex()
    return (menuPage == 2) and selectedRow or (selectedRow + 6)
end

local function menuContentRows()
    if menuPage == 1 then return 7 end
    if menuPage == 2 then return 6 end
    if menuPage == 3 then return 3 end
    return 4
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
        local text, maxLen, target
        if menuPage == 1 then
            target = (selectedRow == 2) and "pitch" or "roll"
            text = (target == "pitch") and pitchSource or rollSource
            maxLen = 4
        else
            local slot = slotIndex()
            target = (editField == 1) and "name" or ((editField == 2) and "source" or "unit")
            text = (target == "name" and sName[slot]) or
                (target == "source" and sSrc[slot]) or sUnit[slot]
            maxLen = (target == "name") and SLOT_NAME_MAX or ((target == "unit") and 3 or 4)
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
                if target == "pitch" then pitchSource = trim(updated) else rollSource = trim(updated) end
            elseif target == "name" then sName[slotIndex()] = trim(updated)
            elseif target == "source" then sSrc[slotIndex()] = trim(updated)
            else sUnit[slotIndex()] = trim(updated) end
        elseif event == EVT_ENTER_LONG and menuPage ~= 1 and editField == 2 then
            cycleCatalog(slotIndex(), 1)
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
            axisMessage = "Achsen getauscht"
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
            if selectedRow == 1 then attitudeMode = (attitudeMode == 1) and 2 or 1
            elseif selectedRow == 2 or selectedRow == 3 then editField = 1; editCharIdx = 1
            elseif selectedRow == 4 then invPitch = 1 - invPitch
            elseif selectedRow == 5 then invRoll = 1 - invRoll
            elseif selectedRow == 6 then invHdg = 1 - invHdg
            elseif selectedRow == 7 then groundMode = (groundMode + 1) % 3
            end
            if selectedRow == 1 or selectedRow >= 4 then saveConfig() end
        elseif menuPage == 2 or menuPage == 3 then
            editField = 1
            editCharIdx = 1
        elseif menuPage == 4 then
            if selectedRow <= 3 then
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
            elseif selectedRow == 4 then
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
            calibrationMessage = "Acc-Signal fehlt"
            return
        end
        local index = 1
        if math.abs(values[2]) > math.abs(values[index]) then index = 2 end
        if math.abs(values[3]) > math.abs(values[index]) then index = 3 end
        local axis = ({ "X", "Y", "Z" })[index]
        downAxis = axis .. ((values[index] >= 0) and "+" or "-")
        calibrationLevel = { values = values, down = index, magnitude = magnitude }
        calibrationStep = 2
        calibrationMessage = "Level erfasst"
    elseif calibrationStep == 2 and (event == EVT_ENTER_BREAK) then
        local remain = {}
        for i = 1, 3 do if i ~= calibrationLevel.down then remain[#remain + 1] = i end end
        local magnitude = vectorMagnitude(values)
        local tilt = math.sqrt(values[remain[1]] ^ 2 + values[remain[2]] ^ 2)
        if magnitude < calibrationLevel.magnitude * 0.5 then
            calibrationMessage = "Acc-Signal fehlt"
            return
        end
        if tilt < magnitude * 0.15 then
            calibrationMessage = "Nase staerker neigen"
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
        calibrationMessage = "Kalibrierung OK"
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
        "-- CONFIG (1/4) --", "-- SENSORS LEFT (2/4) --",
        "-- SENSORS RIGHT (3/4) --", "-- AXIS MAPPING (4/4) --"
    }
    local heading = configSaveFailed and "SAVE FAILED" or
        (configLoadWarning and "OLD CFG: DEFAULTS" or titles[menuPage])
    lcd.drawText(1, 1, heading, (configSaveFailed or configLoadWarning) and
        (SMLSIZE + INVERS) or SMLSIZE)
    if calibrationStep > 0 then
        local values = vectorValues()
        lcd.drawText(1, 13, calibrationStep == 1 and "Modell waagrecht halten" or "Nase nach unten halten", 0)
        lcd.drawText(1, 24, string.format("X:%.1f Y:%.1f Z:%.1f",
            tonumber(values[1]) or 0, tonumber(values[2]) or 0, tonumber(values[3]) or 0), SMLSIZE)
        lcd.drawText(1, 36, calibrationMessage, INVERS)
        lcd.drawText(1, 50, "ENTER: messen EXIT: Ende", SMLSIZE)
        return
    end
    if menuPage == 1 then
        local rows = {
            { "Attitude:", (attitudeMode == 1) and "ANGLES" or "VECTOR" },
            { "Pitch src:", pitchSource }, { "Roll src:", rollSource },
            { "Pitch inv:", (invPitch == 1) and "YES" or "NO" },
            { "Roll inv:", (invRoll == 1) and "YES" or "NO" },
            { "Hdg inv:", (invHdg == 1) and "YES" or "NO" },
            { "Ground:", ({ "White", "Lines", "Points" })[groundMode + 1] }
        }
        for i = 1, #rows do
            local y = 9 + (i - 1) * 7
            local selected = i == selectedRow
            lcd.drawText(1, y, selected and ">" or " ", selected and INVERS or 0)
            lcd.drawText(8, y, rows[i][1], selected and editField == 0 and INVERS or 0)
            local value = rows[i][2]
            local valueX = (i == 2 or i == 3) and 77 or 73
            if editField > 0 and (i == 2 or i == 3) then
                local source = (i == 2) and pitchSource or rollSource
                lcd.drawText(valueX, y, editDisplay(source, 4), INVERS + SMLSIZE)
            else
                lcd.drawText(valueX, y, value, 0)
            end
        end
    elseif menuPage == 2 or menuPage == 3 then
        local first, last = menuPage == 2 and 1 or 7, menuPage == 2 and 6 or 9
        for i = first, last do
            local row = (menuPage == 2) and i or (i - 6)
            local y = 10 + (row - 1) * 8
            local selected = row == selectedRow
            local prefix = selected and ">" or " "
            lcd.drawText(1, y, prefix, selected and INVERS or 0)
            local fullName = padStr(trim(sName[i]), SLOT_NAME_MAX)
            local name = string.sub(fullName, 1, SLOT_NAME_VISIBLE)
            local source = trim(sSrc[i])
            local unit = trim(sUnit[i])
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
    else
        local rows = {
            "Fwd : " .. fwdAxis, "Side: " .. sideAxis,
            "Down: " .. downAxis, "Calibrate"
        }
        for i = 1, #rows do
            local y = 10 + (i - 1) * 8
            local selected = i == selectedRow
            lcd.drawText(1, y, (selected and "> " or "  ") .. rows[i], selected and INVERS or 0)
        end
        if calibrationMessage ~= "" then
            lcd.drawText(1, 44, calibrationMessage, SMLSIZE)
        elseif axisMessage ~= "" then
            lcd.drawText(1, 44, axisMessage, SMLSIZE)
        end
    end
    local scrollSelected = selectedRow > menuContentRows()
    lcd.drawText(1, 56, scrollSelected and ">" or " ", scrollSelected and INVERS or 0)
    lcd.drawText(127, 56, "[scroll]", SMLSIZE + RIGHT +
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
                calibrationMessage = "Abgebrochen"
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

    local cx, sizeW, cy, sizeH = 76, 26, 35, 28
    local pitchOffset = math.max(math.min(pitch * 0.6, sizeH - 2), -(sizeH - 2))
    local rollAngle = roll * 0.01745329252
    local dx, dy = math.cos(rollAngle) * (sizeW - 1), math.sin(rollAngle) * (sizeW - 1)
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
    lcd.drawRectangle(cx - sizeW, cy - sizeH, sizeW * 2, sizeH * 2, FORCE)
    lcd.drawLine(cx - sizeW - 5, cy, cx - sizeW - 1, cy, SOLID, FORCE)
    lcd.drawLine(cx + sizeW + 1, cy, cx + sizeW + 5, cy, SOLID, FORCE)
    lcd.drawLine(cx - 2, cy, cx + 2, cy, SOLID, FORCE)
    lcd.drawLine(cx, cy - 2, cx, cy + 2, SOLID, FORCE)
    lcd.drawLine(cx - dx, cy - dy + pitchOffset, cx + dx, cy + dy + pitchOffset, SOLID, FORCE)
    local alt = filteredAlt
    if string.lower(trim(sSrc[2])) == "alt" then
        local altTickY = cy + ((alt % 5) * (sizeH / 5)) - (sizeH / 2)
        if altTickY >= cy - sizeH + 2 and altTickY <= cy + sizeH - 2 then
            lcd.drawLine(cx - sizeW + 1, altTickY, cx - sizeW + 4, altTickY, SOLID, FORCE)
        end
    end
    lcd.drawText(cx - sizeW - 7, cy - sizeH + 2, string.format("%.0f", tonumber(getValue("Sats")) or 0), SMLSIZE)
    local fix = tonumber(getValue("GFix")) or 0
    lcd.drawText(cx + sizeW - 1, cy - sizeH + 2, fix == 3 and "3D" or (fix == 2 and "2D" or "nF"), SMLSIZE + RIGHT)
    lcd.drawText(cx, cy - 13, trim(sName[2]) .. ":" ..
        string.format(slotFormats[2], alt) .. trim(sUnit[2]), SMLSIZE + CENTER)

    local yBottom = cy - sizeH - 1
    lcd.drawLine(cx, yBottom, cx, yBottom - 3, SOLID, FORCE)
    for i = -6, 6 do
        local angle = (math.floor(hdg / 5) + i) * 5
        local normalized = math.floor((angle % 360 + 360) % 360)
        local diff = ((angle - hdg + 180) % 360) - 180
        local x = cx + diff * 0.75
        if x >= cx - sizeW and x <= cx + sizeW then
            lcd.drawLine(x, yBottom - 2, x, yBottom, SOLID, FORCE)
            if normalized % 45 == 0 then
                lcd.drawText(x - ((#headingLabels[normalized] == 2) and 4 or 2),
                    yBottom - 6, headingLabels[normalized], SMLSIZE)
            end
        end
    end

    for i = 1, 9 do
        local name, unit = string.sub(trim(sName[i]), 1, 4), trim(sUnit[i])
        if name ~= "" then
            local value = string.format(slotFormats[i], slotValues[i])
            if i <= 6 then
                lcd.drawText(1, 2 + (i - 1) * 11, name .. ":" .. value .. unit, SMLSIZE)
            else
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
