-- horz_menu.lua: Menue, Kalibrierung und Config-Editor fuer horz.lua
-- Wird von horz.lua erst bei langem MENU-Druck per loadScript() geladen und beim
-- Verlassen wieder verworfen. Liegt im selben Ordner wie horz.lua und horz_cfg.lua.
-- run(event, cfg) liefert nil (Menue aktiv), "save" (gespeichert) oder "exit" (zurueck).

local SLOT_NAME_MAX, SLOT_NAME_VISIBLE = 4, 4
local MM_LIMIT = 1000000
local MENU_OPEN_DEBOUNCE = 50 -- getTime zaehlt in 10-ms-Ticks.

local cfg, C
local done, saved = false, false
local menuPage, selectedRow, selectedColumn = 1, 1, 1
local editField, editCharIdx, menuOpenTime = 0, 1, 0
local mmEditSlot, mmRow = nil, 1
local calibrationStep, calibrationLevel = 0, nil
local calibrationMessage, axisMessage = "", ""
local axisEditing = false
local trim, textSlice, textCharacters, joinCharacters, padStr, allowedCharList

local function save()
    saved = true
    C.save(cfg)
end

local function roundToPrecision(value, precision)
    local scale = 10 ^ precision
    return (value >= 0 and math.floor(value * scale + 0.5) or
        math.ceil(value * scale - 0.5)) / scale
end

local charPos, charPosKey = 0, ""
local function changeChar(text, index, delta)
    local characters = textCharacters(text)
    local char = characters[index]
    local position = 1
    for i = 1, #allowedCharList do
        if allowedCharList[i] == char then
            position = i
            break
        end
    end
    local key = menuPage .. ":" .. selectedRow .. ":" .. editField .. ":" .. index
    if char == " " and charPosKey == key and allowedCharList[charPos] == " " then
        position = charPos
    end
    position = math.max(1, math.min(#allowedCharList, position + delta))
    charPos, charPosKey = position, key
    characters[index] = allowedCharList[position]
    return joinCharacters(characters)
end

local function slotIndex()
    if menuPage == 2 then return selectedRow end
    if menuPage == 3 then return selectedRow + 6 end
    return selectedRow + 9
end

local function isSensorPage()
    return menuPage == 2 or menuPage == 3 or menuPage == 4
end

local function sensorSlotRows()
    if menuPage == 3 then return 3 end
    return 6
end

local function sensorColumnCount(row, page)
    row, page = row or selectedRow, page or menuPage
    if page == 1 and row >= 7 then return 2 end
    if page == 2 and row <= 6 then return 6 end
    if page == 4 and row <= 6 then return 3 end
    if page == 3 and row <= 3 then return 6 end
    if page == 3 and (row == 4 or row == 5) then return 2 end
    return 1
end

local function menuContentRows()
    if menuPage == 1 then return 8 end
    if menuPage == 2 then return 6 end
    if menuPage == 3 then return 6 end
    if menuPage == 4 then return 6 end
    return 6
end

local function menuRows()
    return menuContentRows() + ((menuPage == 1) and 0 or 1)
end

local function moveHorizontal(delta)
    local row = selectedRow
    local column = selectedColumn + delta
    local columnCount = sensorColumnCount()
    if column < 1 then
        row = math.max(1, row - 1)
        column = sensorColumnCount(row)
    elseif column > columnCount then
        row = math.min(menuRows(), row + 1)
        column = 1
    end
    if row ~= selectedRow then
        selectedRow, selectedColumn = row, column
    else
        selectedColumn = math.max(1, math.min(sensorColumnCount(), column))
    end
end

local function nextMenuPage()
    if axisEditing then save() end
    if menuPage == 2 then
        menuPage, selectedRow = 3, 1
    elseif menuPage == 3 then
        menuPage, selectedRow = 4, 1
    elseif menuPage == 4 then
        menuPage, selectedRow = 1, 1
    else
        menuPage, selectedRow = 1, 1
    end
    selectedColumn = 1
    axisEditing = false
end

local function cycleCatalogValue(source, delta)
    local found = 1
    local count = C.catalogCount(cfg)
    for i = 1, count do
        local name = C.catalogEntryAt(cfg, i)
        if string.lower(name) == string.lower(trim(source)) then
            found = i
            break
        end
    end
    found = math.max(1, math.min(count, found + delta))
    local name, _, _, unit = C.catalogEntryAt(cfg, found)
    return name, unit
end

local function cycleSlotSource(slot, delta)
    cfg.sSrc[slot], cfg.sUnit[slot] = cycleCatalogValue(cfg.sSrc[slot], delta)
    local customSlot = C.customSlotForSource(cfg, cfg.sSrc[slot])
    if customSlot then cfg.sPrecision[slot] = cfg.sPrecision[customSlot] end
end

local function cycleAxis(which, delta)
    local current = (which == 1) and cfg.fwdAxis or ((which == 2) and cfg.sideAxis or cfg.downAxis)
    local sign = string.sub(current, 2, 2)
    local axes = { "X", "Y", "Z" }
    local at = string.find("XYZ", string.sub(current, 1, 1), 1, true) or 1
    local candidateAxis = axes[((at - 1 + delta) % 3) + 1]
    local assignments = { cfg.fwdAxis, cfg.sideAxis, cfg.downAxis }
    local owner
    for i = 1, 3 do
        if i ~= which and string.sub(assignments[i], 1, 1) == candidateAxis then owner = i end
    end
    if owner then
        assignments[owner] = string.sub(current, 1, 1) .. string.sub(assignments[owner], 2, 2)
    end
    assignments[which] = candidateAxis .. sign
    cfg.fwdAxis, cfg.sideAxis, cfg.downAxis = assignments[1], assignments[2], assignments[3]
    return owner ~= nil
end
local function handleMenu(event)
    if getTime() - menuOpenTime < MENU_OPEN_DEBOUNCE then return true end
    local negative = event == EVT_MINUS_FIRST or event == EVT_ROT_LEFT or event == EVT_VIRTUAL_PREV
    local positive = event == EVT_PLUS_FIRST or event == EVT_ROT_RIGHT or event == EVT_VIRTUAL_NEXT
    local horizontalLeft = event == EVT_ROT_LEFT or
        (EVT_LEFT ~= nil and event == EVT_LEFT) or
        (EVT_VIRTUAL_LEFT ~= nil and event == EVT_VIRTUAL_LEFT)
    local horizontalRight = event == EVT_ROT_RIGHT or
        (EVT_RIGHT ~= nil and event == EVT_RIGHT) or
        (EVT_VIRTUAL_RIGHT ~= nil and event == EVT_VIRTUAL_RIGHT)
    if mmEditSlot then
        if (negative or positive) and mmRow <= 2 then
            local rotary = event == EVT_ROT_LEFT or event == EVT_ROT_RIGHT or
                event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_NEXT
            local step = 10 ^ -cfg.sPrecision[mmEditSlot]
            if not rotary then step = step * 10 end
            local target = (mmRow == 1) and cfg.sMin or cfg.sMax
            local value = target[mmEditSlot] + (positive and step or -step)
            target[mmEditSlot] = math.max(-MM_LIMIT, math.min(MM_LIMIT,
                roundToPrecision(value, cfg.sPrecision[mmEditSlot])))
        elseif event == EVT_ENTER_BREAK then
            if mmRow >= 3 then
                mmEditSlot = nil
                save()
            else
                mmRow = mmRow + 1
            end
        elseif event == EVT_EXIT_BREAK or event == EVT_ENTER_LONG then
            mmEditSlot = nil
            save()
        end
        return true
    end
    local sensorRow = isSensorPage() and selectedRow <= menuContentRows()
    local configLinks = menuPage == 1 and selectedRow >= 7 and selectedRow <= 8
    if editField == 0 and (sensorRow or configLinks) and (horizontalLeft or horizontalRight) then
        local delta = horizontalRight and 1 or -1
        moveHorizontal(delta)
        return true
    end
    if editField > 0 then
        if menuPage == 1 and (selectedRow == 2 or selectedRow == 4) and editField == 2 then
            if negative or positive then
                local source = (selectedRow == 2) and cfg.pitchSource or cfg.rollSource
                source = cycleCatalogValue(source, positive and 1 or -1)
                if selectedRow == 2 then cfg.pitchSource = source else cfg.rollSource = source end
            elseif event == EVT_ENTER_BREAK or event == EVT_ENTER_LONG or event == EVT_EXIT_BREAK then
                editField = 0
                save()
            end
            return true
        end
        if menuPage == 3 and selectedRow == 4 and editField == 4 then
            if negative or positive then
                cfg.insideSource = cycleCatalogValue(cfg.insideSource, positive and 1 or -1)
            elseif event == EVT_ENTER_BREAK or event == EVT_EXIT_BREAK then
                editField = 0
                save()
            end
            return true
        end
        if menuPage == 3 and selectedRow == 6 and editField == 5 then
            if negative or positive then
                cfg.altimeterSource = cycleCatalogValue(cfg.altimeterSource, positive and 1 or -1)
            elseif event == EVT_ENTER_BREAK or event == EVT_ENTER_LONG or event == EVT_EXIT_BREAK then
                editField = 0
                save()
            end
            return true
        end
        if menuPage == 3 and selectedRow == 5 and editField == 6 then
            if negative or positive then
                -- Drehgeber: 1 s, +/- Tasten: 10 s
                local isRotary = event == EVT_ROT_LEFT or event == EVT_ROT_RIGHT or
                    event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_NEXT
                local step = (isRotary and 1 or 10) * (positive and 1 or -1)
                cfg.graphSeconds = math.max(10, math.min(999, cfg.graphSeconds + step))
            elseif event == EVT_ENTER_BREAK or event == EVT_ENTER_LONG or event == EVT_EXIT_BREAK then
                editField = 0
                save()
            end
            return true
        end
        if menuPage == 4 and selectedRow <= 6 then
            local slot = slotIndex()
            if editField == 1 or editField == 4 then
                local values = (editField == 1) and cfg.sName or cfg.sUnit
                local maxChars = (editField == 1) and SLOT_NAME_MAX or 3
                if negative or positive then
                    values[slot] = changeChar(padStr(values[slot], maxChars), editCharIdx,
                        negative and -1 or 1)
                    cfg.sSrc[slot] = trim(cfg.sName[slot])
                elseif event == EVT_ENTER_BREAK then
                    editCharIdx = editCharIdx + 1
                    if editCharIdx > maxChars then
                        editCharIdx, editField = 1, 0
                        save()
                    end
                elseif event == EVT_EXIT_BREAK then
                    editField = 0
                    save()
                end
            elseif editField == 3 then
                if negative or positive then
                    cfg.sPrecision[slot] = math.max(0, math.min(4,
                        cfg.sPrecision[slot] + (positive and 1 or -1)))
                elseif event == EVT_ENTER_BREAK or event == EVT_EXIT_BREAK then
                    editField = 0
                    save()
                end
            end
            return true
        end
        if menuPage == 2 or (menuPage == 3 and selectedRow <= 3) then
            local slot = slotIndex()
            if editField == 1 then
                if negative or positive then
                    cfg.sName[slot] = changeChar(padStr(cfg.sName[slot], SLOT_NAME_MAX), editCharIdx,
                        negative and -1 or 1)
                elseif event == EVT_ENTER_BREAK then
                    editCharIdx = editCharIdx + 1
                    if editCharIdx > SLOT_NAME_MAX then
                        editCharIdx, editField, selectedColumn = 1, 0, 2
                        save()
                    end
                end
            elseif editField == 2 then
                if negative or positive then
                    cycleSlotSource(slot, positive and 1 or -1)
                elseif event == EVT_ENTER_BREAK then
                    editField = 0
                    save()
                end
            elseif editField == 3 then
                if negative or positive then
                    cfg.sPrecision[slot] = math.max(0, math.min(4,
                        cfg.sPrecision[slot] + (positive and 1 or -1)))
                elseif event == EVT_ENTER_BREAK then
                    editField = 0
                    save()
                end
            end
            if event == EVT_EXIT_BREAK then
                editField = 0
                save()
            end
            return true
        end
        return true
    end

    if menuPage == 5 and axisEditing and selectedRow <= 3 and (negative or positive) then
        if cycleAxis(selectedRow, positive and 1 or -1) then
            axisMessage = "Axes changed"
        else
            axisMessage = ""
        end
    elseif negative or positive then
        local delta = positive and 1 or -1
        selectedRow = math.max(1, math.min(menuRows(), selectedRow + delta))
        if isSensorPage() or menuPage == 1 then
            selectedColumn = 1
        end
    elseif event == EVT_PAGE_BREAK then
        if menuPage ~= 1 then nextMenuPage() end
    elseif event == EVT_EXIT_BREAK then
        if menuPage ~= 1 then
            save()
            menuPage, selectedRow, selectedColumn = 1, 1, 1
            axisEditing = false
        else
            save()
            done = true
            axisEditing = false
        end
    elseif event == EVT_ENTER_BREAK then
        if selectedRow > menuContentRows() then
            nextMenuPage()
        elseif menuPage == 1 then
            if selectedRow == 1 then
                cfg.groundMode = (cfg.groundMode + 1) % 3
                save()
            elseif selectedRow == 2 or selectedRow == 4 then
                if cfg.attitudeMode ~= 2 then editField = 2 end
            elseif selectedRow == 3 then
                cfg.invPitch = 1 - cfg.invPitch
                save()
            elseif selectedRow == 5 then
                cfg.invRoll = 1 - cfg.invRoll
                save()
            elseif selectedRow == 6 then
                cfg.invHdg = 1 - cfg.invHdg
                save()
            elseif selectedRow == 7 then
                if selectedColumn == 1 then
                    menuPage, selectedRow = 2, 1
                else
                    menuPage, selectedRow = 5, 1
                end
                selectedColumn = 1
            elseif selectedRow == 8 then
                if selectedColumn == 1 then
                    cfg.attitudeMode = (cfg.attitudeMode == 1) and 2 or 1
                else
                    cfg.viewMode = 1 - cfg.viewMode
                end
                save()
            end
        elseif isSensorPage() then
            if selectedRow <= sensorSlotRows() then
                if menuPage == 4 then
                    if selectedColumn == 1 then
                        editField, editCharIdx = 1, 1
                    elseif selectedColumn == 2 then
                        editField, editCharIdx = 4, 1
                    elseif selectedColumn == 3 then
                        editField = 3
                    end
                elseif selectedColumn == 1 then
                    editField, editCharIdx = 1, 1
                elseif selectedColumn == 2 or selectedColumn == 3 then
                    editField = 2
                elseif selectedColumn == 4 then
                    editField = 3
                elseif selectedColumn == 5 then
                    mmEditSlot = slotIndex()
                    mmRow = 1
                elseif selectedColumn == 6 then
                    local slot = slotIndex()
                    cfg.sOn[slot] = 1 - cfg.sOn[slot]
                    save()
                end
            elseif menuPage == 3 and selectedRow == 4 then
                if selectedColumn == 1 then editField = 4
                else
                    cfg.insideEnabled = 1 - cfg.insideEnabled
                    save()
                end
            elseif menuPage == 3 and selectedRow == 5 then
                if selectedColumn == 1 then
                    cfg.graphEnabled = 1 - cfg.graphEnabled
                    save()
                else
                    editField = 6
                end
            elseif menuPage == 3 and selectedRow == 6 then
                editField = 5
            end
        elseif menuPage == 5 then
            if selectedRow == 5 then
                cfg.attitudeMode = (cfg.attitudeMode == 1) and 2 or 1
                save()
            elseif selectedRow == 4 then
                cfg.viewMode = 1 - cfg.viewMode
                save()
            elseif selectedRow <= 3 then
                if axisEditing then
                    local axis = (selectedRow == 1 and cfg.fwdAxis) or (selectedRow == 2 and cfg.sideAxis) or cfg.downAxis
                    local value = string.sub(axis, 1, 1) ..
                        ((string.sub(axis, 2, 2) == "+") and "-" or "+")
                    if selectedRow == 1 then
                        cfg.fwdAxis = value
                    elseif selectedRow == 2 then
                        cfg.sideAxis = value
                    else
                        cfg.downAxis = value
                    end
                    axisEditing = false
                    save()
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

local vector = { 0, 0, 0 }
local function vectorValues()
    vector[1] = tonumber(getValue("AccX")) or 0
    vector[2] = tonumber(getValue("AccY")) or 0
    vector[3] = tonumber(getValue("AccZ")) or 0
    return vector
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
        cfg.downAxis = axis .. ((values[index] >= 0) and "+" or "-")
        calibrationLevel = { down = index, magnitude = magnitude }
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
        cfg.fwdAxis = ({ "X", "Y", "Z" })[forward] .. ((values[forward] >= 0) and "+" or "-")
        local fSign = string.sub(cfg.fwdAxis, 2, 2) == "+" and 1 or -1
        local dSign = string.sub(cfg.downAxis, 2, 2) == "+" and 1 or -1
        local fVec = { 0, 0, 0 }; fVec[forward] = fSign
        local sideVector = { 0, 0, 0 }
        sideVector[other] = 1
        local cross = {
            fVec[2] * sideVector[3] - fVec[3] * sideVector[2],
            fVec[3] * sideVector[1] - fVec[1] * sideVector[3],
            fVec[1] * sideVector[2] - fVec[2] * sideVector[1]
        }
        local sideSign = (cross[calibrationLevel.down] * dSign >= 0) and 1 or -1
        cfg.sideAxis = ({ "X", "Y", "Z" })[other] .. ((sideSign > 0) and "+" or "-")
        calibrationStep = 0
        calibrationLevel = nil
        calibrationMessage = "Calibration OK"
        save()
    end
end
local function editDisplay(value, length, selectedIndex)
    local padded = padStr(value, length)
    local index = selectedIndex or editCharIdx
    return textSlice(padded, 1, index - 1) .. "[" ..
        textSlice(padded, index, index) .. "]" ..
        textSlice(padded, index + 1)
end

local titles = {
    "--CONFIG PAGE--", "--Sensors Left 1/3--",
    "--Sensors Right 2/3--", "--Custom Sensors 3/3--",
    "--AXIS SETTING--"
}
local groundNames = { "White", "Lines", "Points" }
local axisRows = { "", "", "", "", "", "Calibrate Attitude" }

local function line(n) return 9 + (n - 1) * 8 end

local function checkbox(y, on, selected)
    lcd.drawText(80, y, "inv:", SMLSIZE)
    lcd.drawText(104, y, on and "[X]" or "[ ]", selected and INVERS or 0)
end

local function drawMenu(event)
    if mmEditSlot then
        lcd.drawText(1, 1, "-- SENSOR MIN/MAX --", INVERS + SMLSIZE)
        lcd.drawText(1, 13, trim(cfg.sName[mmEditSlot]) .. " / " .. trim(cfg.sSrc[mmEditSlot]), SMLSIZE)
        lcd.drawText(1, 25, (mmRow == 1 and ">" or " ") .. "MIN: " ..
            string.format("%." .. cfg.sPrecision[mmEditSlot] .. "f", cfg.sMin[mmEditSlot]), SMLSIZE)
        lcd.drawText(1, 37, (mmRow == 2 and ">" or " ") .. "MAX: " ..
            string.format("%." .. cfg.sPrecision[mmEditSlot] .. "f", cfg.sMax[mmEditSlot]), SMLSIZE)
        lcd.drawText(1, 52, (mmRow == 3 and ">" or " ") .. "Done", SMLSIZE)
        lcd.drawText(74, 52, "ENTER: next", SMLSIZE)
        return
    end
    local heading = cfg.configSaveFailed and "SAVE FAILED" or
        (cfg.configLoadWarning and "OLD CFG: DEFAULTS" or titles[menuPage])
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
        lcd.drawText(8, line(1), "Ground as:", (selectedRow == 1) and INVERS or 0)
        lcd.drawText(73, line(1), groundNames[cfg.groundMode + 1], 0)
        for k = 0, 1 do
            local item, y = 2 + k * 2, line(2 + k)
            local source = (k == 0) and cfg.pitchSource or cfg.rollSource
            lcd.drawText(8, y, (k == 0) and "Pitch:" or "Roll:",
                (selectedRow == item and editField == 0) and INVERS or 0)
            local sourceText = (cfg.attitudeMode == 2) and "----" or source
            lcd.drawText(48, y, sourceText,
                (cfg.attitudeMode == 2) and SMLSIZE or
                ((selectedRow == item and editField == 2) and INVERS or 0))
            checkbox(y, ((k == 0) and cfg.invPitch or cfg.invRoll) == 1, selectedRow == item + 1)
        end
        lcd.drawText(8, line(4), "Heading:", 0)
        checkbox(line(4), cfg.invHdg == 1, selectedRow == 6)
        local sensorsFlags = (selectedRow == 7 and selectedColumn == 1) and INVERS or 0
        local axesFlags = (selectedRow == 7 and selectedColumn == 2) and INVERS or 0
        local attitudeFlags = (selectedRow == 8 and selectedColumn == 1) and INVERS or 0
        local viewFlags = (selectedRow == 8 and selectedColumn == 2) and INVERS or 0
        lcd.drawText(8, line(5), "SENSORS", sensorsFlags + SMLSIZE)
        lcd.drawText(78, line(5), "AXES", axesFlags + SMLSIZE)
        lcd.drawText(8, line(6), "ATTITUDE:" ..
            ((cfg.attitudeMode == 1) and "ANGLES" or "VECTOR"), attitudeFlags + SMLSIZE)
        lcd.drawText(78, line(6), "BOX:" ..
            ((cfg.viewMode == 1) and "FULL" or "SIMPLE"), viewFlags + SMLSIZE)
    elseif isSensorPage() then
        local first, last
        if menuPage == 2 then
            first, last = 1, 6
        elseif menuPage == 3 then
            first, last = 7, 9
        else
            first, last = 10, 15
        end
        local headerY = 8
        if menuPage == 4 then
            lcd.drawText(4, headerY, "Name", INVERS + SMLSIZE)
            lcd.drawText(52, headerY, "Unit", INVERS + SMLSIZE)
            lcd.drawText(86, headerY, "Prec", INVERS + SMLSIZE)
        else
            lcd.drawText(4, headerY, "Name", INVERS + SMLSIZE)
            lcd.drawText(27, headerY, "Src", INVERS + SMLSIZE)
            lcd.drawText(52, headerY, "Uni", INVERS + SMLSIZE)
            lcd.drawText(69, headerY, "Prec", INVERS + SMLSIZE)
            lcd.drawText(94, headerY, "MM", INVERS + SMLSIZE)
            lcd.drawText(108, headerY, "ON", INVERS + SMLSIZE)
        end
        for i = first, last do
            local row = (menuPage == 2) and i or
                ((menuPage == 3) and (i - 6) or (i - 9))
            local y = 15 + (row - 1) * 7
            local selected = row == selectedRow
            local editing = selected and editField > 0
            local fullName = padStr(editing and cfg.sName[i] or trim(cfg.sName[i]), SLOT_NAME_MAX)
            local isCustomPage = menuPage == 4
            local name = textSlice(fullName, 1, SLOT_NAME_VISIBLE)
            if isCustomPage and trim(name) == "" then name = "____" end
            local nameText = name
            if selected and editField == 1 then
                local start = math.max(1, math.min(editCharIdx - SLOT_NAME_VISIBLE + 1,
                    SLOT_NAME_MAX - SLOT_NAME_VISIBLE + 1))
                nameText = editDisplay(textSlice(fullName, start, start + SLOT_NAME_VISIBLE - 1),
                    SLOT_NAME_VISIBLE, editCharIdx - start + 1)
            end
            lcd.drawText(0, y, selected and ">" or " ", SMLSIZE)
            lcd.drawText(4, y, nameText, SMLSIZE +
                ((selected and selectedColumn == 1) and INVERS or 0))
            if isCustomPage then
                local unit = (selected and editField == 4) and
                    editDisplay(padStr(cfg.sUnit[i], 3), 3, editCharIdx) or trim(cfg.sUnit[i])
                if unit == "" then unit = "___" end
                lcd.drawText(52, y, unit, SMLSIZE +
                    ((selected and selectedColumn == 2) and INVERS or 0))
                lcd.drawText(86, y, tostring(cfg.sPrecision[i]),
                    SMLSIZE + ((selected and selectedColumn == 3) and INVERS or 0))
            else
                lcd.drawText(27, y, trim(cfg.sSrc[i]),
                    SMLSIZE + ((selected and selectedColumn == 2) and INVERS or 0))
                lcd.drawText(52, y, trim(cfg.sUnit[i]),
                    SMLSIZE + ((selected and selectedColumn == 3) and INVERS or 0))
                lcd.drawText(69, y, tostring(cfg.sPrecision[i]),
                    SMLSIZE + ((selected and selectedColumn == 4) and INVERS or 0))
                lcd.drawText(92, y, " =",
                    SMLSIZE + ((selected and selectedColumn == 5) and INVERS or 0))
                lcd.drawText(107, y, (cfg.sOn[i] == 1) and "[X]" or "[ ]",
                    SMLSIZE + ((selected and selectedColumn == 6) and INVERS or 0))
            end
        end
        if menuPage == 3 then
            local sourceRowY, graphRowY, altimeterRowY = 36, 43, 50
            local sourceSelected = selectedRow == 4
            lcd.drawText(0, sourceRowY, sourceSelected and ">" or " ", SMLSIZE)
            lcd.drawText(4, sourceRowY, "inside Horiz:",
                SMLSIZE + ((sourceSelected and selectedColumn == 1) and INVERS or 0))
            lcd.drawText(68, sourceRowY, cfg.insideSource,
                SMLSIZE + ((sourceSelected and selectedColumn == 1) and INVERS or 0))
            lcd.drawText(105, sourceRowY, (cfg.insideEnabled == 1) and " [X]" or " [ ]",
                SMLSIZE + ((sourceSelected and selectedColumn == 2) and INVERS or 0))
            local graphSelected = selectedRow == 5
            lcd.drawText(0, graphRowY, graphSelected and ">" or " ", SMLSIZE)
            lcd.drawText(1, graphRowY, " Graph", SMLSIZE)
            lcd.drawText(29, graphRowY, (cfg.graphEnabled == 1) and "[X]" or "[ ]",
                SMLSIZE + ((graphSelected and selectedColumn == 1) and INVERS or 0))
            lcd.drawText(48, graphRowY, "X-Time:", SMLSIZE)
            lcd.drawText(91, graphRowY, "[" .. cfg.graphSeconds .. "]",
                SMLSIZE + ((graphSelected and selectedColumn == 2) and INVERS or 0))
            local altimeterSelected = selectedRow == 6
            lcd.drawText(0, altimeterRowY, altimeterSelected and ">" or " ", SMLSIZE)
            lcd.drawText(4, altimeterRowY, "Altimeter-Scale:",
                SMLSIZE + ((altimeterSelected and selectedColumn == 1) and INVERS or 0))
            lcd.drawText(83, altimeterRowY, cfg.altimeterSource,
                SMLSIZE + ((altimeterSelected and selectedColumn == 1) and INVERS or 0))
            if selectedRow == 5 and selectedColumn == 1 then
                lcd.drawText(1, 57, " Graph?only1LSensor", SMLSIZE)
            end
        end
    else
        local rows = axisRows
        rows[1], rows[2], rows[3] = "Forward: " .. cfg.fwdAxis, "Side: " .. cfg.sideAxis,
            "Down: " .. cfg.downAxis
        rows[4] = "BOX: " .. ((cfg.viewMode == 1) and "FULL" or "SIMPLE")
        rows[5] = "Attitude: " .. ((cfg.attitudeMode == 1) and "ANGLES" or "VECTOR")
        for i = 1, #rows do
            local y = 10 + (i - 1) * 8
            local selected = i == selectedRow
            lcd.drawText(1, y, (selected and "> " or "  ") .. rows[i], selected and INVERS or 0)
        end
        if selectedRow ~= 6 then
            if calibrationMessage ~= "" then
                lcd.drawText(9, 56, calibrationMessage, SMLSIZE)
            elseif axisMessage ~= "" then
                lcd.drawText(1, 50, axisMessage, SMLSIZE)
            end
        end
    end
    if menuPage ~= 1 then
        local scrollSelected = selectedRow > menuContentRows()
        lcd.drawText(1, 58, scrollSelected and ">" or " ", scrollSelected and INVERS or 0)
        lcd.drawText(127, 58, "[scroll]", SMLSIZE + RIGHT +
            (scrollSelected and INVERS or 0))
    end
end

local function run(event, cfgTable)
    cfg = cfgTable
    if not C then
        local chunk = loadScript(cfgTable.dir .. "horz_cfg")
        if not chunk then return "exit" end
        C = chunk()
        trim, textSlice, textCharacters, joinCharacters, padStr, allowedCharList =
            C.trim, C.textSlice, C.textCharacters, C.joinCharacters, C.padStr, C.allowedCharList
    end
    if event == EVT_MENU_LONG then
        if axisEditing then save() end
        menuPage, selectedRow, editField = 1, 1, 0
        selectedColumn = 1
        axisEditing = false
        menuOpenTime = getTime()
    end
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
    if done then
        C, cfg = nil, nil
        return "exit"
    end
    drawMenu(event)
    if saved then
        saved = false
        return "save"
    end
    return nil
end

return { run = run }
