-- horz_cfg.lua: Config laden/speichern und Sensor-Katalog fuer horz.lua / horz_menu.lua
-- Wird von horz.lua beim Start (und nach dem Menue) kurz geladen und danach verworfen;
-- das Menue laedt es selbst nach, um zu speichern. Liegt im selben Ordner wie horz.lua.

-- V2: Das Leselimit 1024 Byte laesst Reserve fuer zusaetzliche Einstellungen.
local CONFIG_READ_LIMIT = 2048
local SLOT_NAME_MAX = 4
-- Alte Configs duerfen 12 Zeichen enthalten; beim Laden wird auf 4 gekuerzt.
local SLOT_NAME_LEGACY_MAX = 12
local MM_LIMIT = 1000000
local SLOT_COUNT, STANDARD_SLOT_COUNT = 15, 9
local CUSTOM_SLOT_FIRST = STANDARD_SLOT_COUNT + 1
local defaults = {
    names = { "RX", "Alt", "VSp", "Spd", "Dist", "Head", "Batt", "celD", "Amp" },
    sources = { "RSSI", "GAlt", "VSpd", "GSpd", "Dist", "Hdg", "Cels", "celD", "Curr" },
    units = { "dB", "m", "m/s", "kmh", "m", "°", "V", "V", "A" }
}
local catalog = {
    { "", "%.1f", 1, "" }, { "RSSI", "%.0f", 1, "dB" }, { "Alt", "%.0f", 1, "m" },
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
local DEGREE_UTF8 = "°"
local allowedChars =
" aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ0123456789-+_.*" ..
DEGREE_UTF8 .. "%/() " -- Leerzeichen am Anfang/Ende (Null-Abstand)

local function textCharacters(value)
    local characters, index = {}, 1
    while index <= #value do
        local character = string.sub(value, index, index + 1)
        if character == DEGREE_UTF8 then
            characters[#characters + 1] = DEGREE_UTF8
            index = index + 2
        else
            characters[#characters + 1] = string.sub(value, index, index)
            index = index + 1
        end
    end
    return characters
end

local function joinCharacters(characters)
    local result = ""
    for index = 1, #characters do
        result = result .. characters[index]
    end
    return result
end

local function textSlice(value, first, last)
    local characters = textCharacters(value)
    local result = {}
    for index = math.max(1, first), math.min(last or #characters, #characters) do
        result[#result + 1] = characters[index]
    end
    return joinCharacters(result)
end

local allowedCharList = textCharacters(allowedChars)

local function trim(str)
    if not str then return "" end
    return (string.gsub(tostring(str), "^%s*(.-)%s*$", "%1"))
end

local function customSlotForSource(cfg, source)
    local key = string.lower(trim(source))
    if key == "" then return nil end
    for i = CUSTOM_SLOT_FIRST, SLOT_COUNT do
        if string.lower(trim(cfg.sName[i])) == key then return i end
    end
end

local function catalogEntry(cfg, source)
    local key = string.lower(trim(source))
    local entry = catalogByName[key]
    if entry then return entry[1], entry[2], entry[3], entry[4] end
    local slot = customSlotForSource(cfg, key)
    if slot then
        return trim(cfg.sName[slot]), "%." .. cfg.sPrecision[slot] .. "f", 1, trim(cfg.sUnit[slot])
    end
end

local function customCatalogEntryAt(cfg, index)
    local customIndex = index - #catalog
    if customIndex < 1 then return nil end
    local found = 0
    for i = CUSTOM_SLOT_FIRST, SLOT_COUNT do
        local name = trim(cfg.sName[i])
        local key = string.lower(name)
        if key ~= "" and not catalogByName[key] then
            local duplicate = false
            for previous = CUSTOM_SLOT_FIRST, i - 1 do
                if string.lower(trim(cfg.sName[previous])) == key then
                    duplicate = true
                    break
                end
            end
            if not duplicate then
                found = found + 1
                if found == customIndex then
                    return name, "%." .. cfg.sPrecision[i] .. "f", 1, trim(cfg.sUnit[i])
                end
            end
        end
    end
end

local function catalogCount(cfg)
    local count = #catalog
    while customCatalogEntryAt(cfg, count + 1) do count = count + 1 end
    return count
end

local function catalogEntryAt(cfg, index)
    if index <= #catalog then
        local entry = catalog[index]
        return entry[1], entry[2], entry[3], entry[4]
    end
    return customCatalogEntryAt(cfg, index)
end

local function padStr(str, len)
    local characters = textCharacters(tostring(str or ""))
    while #characters < len do characters[#characters + 1] = " " end
    local result = {}
    for index = 1, len do result[index] = characters[index] end
    return joinCharacters(result)
end

local function modelPath()
    local info = model.getInfo()
    local name = string.gsub((info and info.name) or "model", "[ %c%p]", "_")
    return "/LOGS/hz_" .. name .. ".cfg"
end

local function setDefaults(cfg)
    cfg.invPitch, cfg.invRoll, cfg.invHdg = 0, 0, 0
    cfg.groundMode, cfg.attitudeMode, cfg.viewMode = 2, 1, 1
    cfg.pitchSource, cfg.rollSource = "Ptch", "Roll"
    cfg.insideSource, cfg.insideEnabled = "Alt", 1
    cfg.altimeterSource = "Alt"
    cfg.graphSeconds = 30
    cfg.graphEnabled = 1
    cfg.fwdAxis, cfg.sideAxis, cfg.downAxis = "X+", "Z-", "Y+"
    for i = 1, SLOT_COUNT do
        if i <= STANDARD_SLOT_COUNT then
            cfg.sName[i], cfg.sSrc[i], cfg.sUnit[i] =
                defaults.names[i], defaults.sources[i], defaults.units[i]
            cfg.sOn[i] = 1
        else
            cfg.sName[i], cfg.sSrc[i], cfg.sUnit[i] = "", "", ""
            cfg.sOn[i] = 0
        end
        local entry = catalogByName[string.lower(cfg.sSrc[i])]
        cfg.sPrecision[i] = (i > STANDARD_SLOT_COUNT) and 0 or
            (entry and tonumber(string.match(entry[2], "%.(%d)f")) or 0)
        cfg.sMin[i], cfg.sMax[i] = 0, 0
    end
end

local function validAxis(value)
    return value == "X+" or value == "X-" or value == "Y+" or value == "Y-" or
        value == "Z+" or value == "Z-"
end

local function validText(value, maxLen)
    local i, charCount = 1, 0
    while i <= #value do
        local char = string.sub(value, i, i + 1)
        if char == DEGREE_UTF8 then
            i = i + 2
        else
            local byte = string.byte(value, i)
            local ascii = string.sub(value, i, i)
            if byte >= 128 or not string.find(allowedChars, ascii, 1, true) then
                return false
            end
            i = i + 1
        end
        charCount = charCount + 1
        if charCount > maxLen then return false end
    end
    return true
end

local function isFinite(value)
    return value and value == value and value ~= math.huge and value ~= -math.huge
end

local function loadConfig(cfg)
    setDefaults(cfg)
    cfg.configLoadWarning = false
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
                        cfg.configLoadWarning = true
                        break
                    end
                else
                    local key, value = string.match(line, "^([^=]+)=(.*)$")
                    if key == "MODE" and (value == "ANGLES" or value == "VECTOR") then
                        cfg.attitudeMode = (value == "VECTOR") and 2 or 1
                    elseif key == "VIEW" and (value == "CLASSIC" or value == "3D") then
                        cfg.viewMode = (value == "3D") and 1 or 0
                    elseif key == "INVERT" then
                        local p, r, h = string.match(value, "^(%d),(%d),(%d)$")
                        if p and tonumber(p) <= 1 and tonumber(r) <= 1 and tonumber(h) <= 1 then
                            cfg.invPitch, cfg.invRoll, cfg.invHdg = tonumber(p), tonumber(r), tonumber(h)
                        end
                    elseif key == "GROUND" then
                        local ground = tonumber(value)
                        if ground and ground % 1 == 0 and ground >= 0 and ground <= 2 then
                            cfg.groundMode = ground
                        end
                    elseif key == "SOURCES" then
                        local p, r = string.match(value, "^(.-),(.-)$")
                        if p ~= nil and r ~= nil and validText(p, 4) and validText(r, 4) then
                            cfg.pitchSource, cfg.rollSource = p, r
                        end
                    elseif key == "INSIDE" then
                        local source, enabled = string.match(value, "^(.-),([01])$")
                        if source and validText(source, 4) then
                            cfg.insideSource, cfg.insideEnabled = source, tonumber(enabled)
                        end
                    elseif key == "ALTIMETER-SCALE" and validText(value, 4) then
                        cfg.altimeterSource = value
                    elseif key == "SLOTON" then
                        if string.match(value, "^[01]+$") and
                            (#value == STANDARD_SLOT_COUNT or #value == SLOT_COUNT) then
                            for i = 1, #value do cfg.sOn[i] = tonumber(string.sub(value, i, i)) end
                        end
                    elseif key == "GRAPHTIME" then
                        local secs = tonumber(value)
                        if secs and secs % 1 == 0 and secs >= 10 and secs <= 999 then
                            cfg.graphSeconds = secs
                        end
                    elseif key == "GRAPH" and (value == "0" or value == "1") then
                        cfg.graphEnabled = tonumber(value)
                    elseif key == "SLOTPRECI" then
                        local iText, precision = string.match(value, "^(%d+)|(%d)$")
                        local i, number = tonumber(iText), tonumber(precision)
                        if i and i % 1 == 0 and i >= 1 and i <= SLOT_COUNT and number and number <= 4 then
                            cfg.sPrecision[i] = number
                        end
                    elseif key == "SLOTRANGE" then
                        local iText, minText, maxText =
                            string.match(value, "^(%d+)|([^|]*)|([^|]*)$")
                        local i, minValue, maxValue = tonumber(iText), tonumber(minText), tonumber(maxText)
                        if i and i % 1 == 0 and i >= 1 and i <= SLOT_COUNT and
                            isFinite(minValue) and isFinite(maxValue) and
                            math.abs(minValue) <= MM_LIMIT and math.abs(maxValue) <= MM_LIMIT then
                            cfg.sMin[i], cfg.sMax[i] = minValue, maxValue
                        end
                    elseif key == "AXES" then
                        local fwd, side, down = string.match(value, "^([^,]+),([^,]+),([^,]+)$")
                        if fwd and side and down and validAxis(fwd) and validAxis(side) and validAxis(down) and
                            string.sub(fwd, 1, 1) ~= string.sub(side, 1, 1) and
                            string.sub(fwd, 1, 1) ~= string.sub(down, 1, 1) and
                            string.sub(side, 1, 1) ~= string.sub(down, 1, 1) then
                            cfg.fwdAxis, cfg.sideAxis, cfg.downAxis = fwd, side, down
                        end
                    elseif key == "SLOT" then
                        local iText, name, source, unit =
                            string.match(value, "^(%d+)|([^|]*)|([^|]*)|([^|]*)$")
                        local i = tonumber(iText)
                        if iText and name and source and unit and i and i % 1 == 0 and
                            i >= 1 and i <= SLOT_COUNT and validText(name, SLOT_NAME_LEGACY_MAX) and
                            validText(source, 4) and validText(unit, 3) then
                            cfg.sName[i], cfg.sSrc[i], cfg.sUnit[i] =
                                textSlice(name, 1, SLOT_NAME_MAX), source, unit
                            if i >= CUSTOM_SLOT_FIRST then
                                cfg.sSrc[i] = trim(cfg.sName[i])
                            end
                        end
                    end
                end
            end
        end
    end
end

local function saveConfig(cfg)
    -- Leerzeichen am Rand werden beim Beenden der Eingabe entfernt
    cfg.pitchSource, cfg.rollSource, cfg.altimeterSource =
        trim(cfg.pitchSource), trim(cfg.rollSource), trim(cfg.altimeterSource)
    for i = 1, SLOT_COUNT do
        cfg.sName[i], cfg.sSrc[i], cfg.sUnit[i] =
            textSlice(trim(cfg.sName[i]), 1, SLOT_NAME_MAX), trim(cfg.sSrc[i]), trim(cfg.sUnit[i])
        if i >= CUSTOM_SLOT_FIRST then cfg.sSrc[i] = trim(cfg.sName[i]) end
    end
    local f = io.open(modelPath(), "w")
    if not f then
        cfg.configSaveFailed = true
        return false
    end
    io.write(f, "HORZCFG=2\n")
    io.write(f, "MODE=" .. ((cfg.attitudeMode == 1) and "ANGLES" or "VECTOR") .. "\n")
    io.write(f, "VIEW=" .. ((cfg.viewMode == 1) and "3D" or "CLASSIC") .. "\n")
    io.write(f, "INVERT=" .. cfg.invPitch .. "," .. cfg.invRoll .. "," .. cfg.invHdg .. "\n")
    io.write(f, "GROUND=" .. cfg.groundMode .. "\n")
    io.write(f, "SOURCES=" .. cfg.pitchSource .. "," .. cfg.rollSource .. "\n")
    io.write(f, "INSIDE=" .. cfg.insideSource .. "," .. cfg.insideEnabled .. "\n")
    io.write(f, "ALTIMETER-SCALE=" .. trim(cfg.altimeterSource) .. "\n")
    local on = ""
    for i = 1, SLOT_COUNT do on = on .. cfg.sOn[i] end
    io.write(f, "SLOTON=" .. on .. "\n")
    io.write(f, "GRAPHTIME=" .. cfg.graphSeconds .. "\n")
    io.write(f, "GRAPH=" .. cfg.graphEnabled .. "\n")
    io.write(f, "AXES=" .. cfg.fwdAxis .. "," .. cfg.sideAxis .. "," .. cfg.downAxis .. "\n")
    for i = 1, SLOT_COUNT do
        io.write(f, "SLOT=" .. i .. "|" .. trim(cfg.sName[i]) .. "|" ..
            trim(cfg.sSrc[i]) .. "|" .. trim(cfg.sUnit[i]) .. "\n")
        io.write(f, "SLOTPRECI=" .. i .. "|" .. cfg.sPrecision[i] .. "\n")
        io.write(f, "SLOTRANGE=" .. i .. "|" .. cfg.sMin[i] .. "|" .. cfg.sMax[i] .. "\n")
    end
    io.close(f)
    cfg.configSaveFailed = false
    cfg.configLoadWarning = false
    return true
end


return {
    load = loadConfig,
    save = saveConfig,
    trim = trim,
    textSlice = textSlice,
    textCharacters = textCharacters,
    joinCharacters = joinCharacters,
    padStr = padStr,
    allowedCharList = allowedCharList,
    catalogEntry = catalogEntry,
    catalogEntryAt = catalogEntryAt,
    catalogCount = catalogCount,
    customSlotForSource = customSlotForSource
}
