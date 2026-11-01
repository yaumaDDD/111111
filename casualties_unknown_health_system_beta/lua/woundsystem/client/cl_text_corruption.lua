WoundSystem = WoundSystem or {}
WoundSystem.TextCorruption = WoundSystem.TextCorruption or {}

local TextCorruption = WoundSystem.TextCorruption

TextCorruption.Enabled = TextCorruption.Enabled or CreateClientConVar("woundsys_brain_ui_text_corruption", "1", true, false, "Corrupt WoundSystem UI text when brain health is low.", 0, 1)
TextCorruption.Cache = TextCorruption.Cache or {}
TextCorruption.WasCorrupting = TextCorruption.WasCorrupting or false

local DISTORTION_CHARS = "!@#$%&"

local function Number(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function CurrentBrainHealth()
    local state = WoundSystemClientState
    local cardio = state and state.Cardio
    return Number(cardio and cardio.brainHealth, 100)
end

local function Deterministic01(seed)
    seed = tonumber(seed) or 0
    local x = math.sin(seed * 12.9898) * 43758.5453
    return x - math.floor(x)
end

local function DeterministicChar(seed)
    local index = math.floor(Deterministic01(seed) * #DISTORTION_CHARS) + 1
    return string.sub(DISTORTION_CHARS, index, index)
end

local function IsOutsideAngleBrackets(text, index)
    local inside = false
    for i = 1, index do
        local ch = string.sub(text, i, i)
        if ch == "<" then
            inside = true
        elseif ch == ">" then
            if i == index then return false end
            inside = false
        end
    end

    return not inside
end

function TextCorruption.BrainSeverity()
    local brain = CurrentBrainHealth()
    return math.Clamp(0.95 - (brain * 0.01), 0, 0.95)
end

function TextCorruption.ShouldCorrupt()
    local shouldCorrupt = TextCorruption.Enabled:GetBool() and TextCorruption.BrainSeverity() > 0

    if not shouldCorrupt and TextCorruption.WasCorrupting then
        table.Empty(TextCorruption.Cache)
    end

    TextCorruption.WasCorrupting = shouldCorrupt
    return shouldCorrupt
end

function TextCorruption.Corrupt(text)
    text = tostring(text or "")
    if text == "" or not TextCorruption.ShouldCorrupt() then return text end

    local severity = TextCorruption.BrainSeverity()
    local cacheKey = string.format("%.3f|%s", severity, text)
    local cached = TextCorruption.Cache[cacheKey]
    if cached then return cached end

    local out = {}

    for i = 1, #text do
        local char = string.sub(text, i, i)
        if Deterministic01(i) < severity and IsOutsideAngleBrackets(text, i) then
            out[#out + 1] = DeterministicChar(i + 128)
        else
            out[#out + 1] = char
        end
    end

    local corrupted = table.concat(out)
    TextCorruption.Cache[cacheKey] = corrupted
    return corrupted
end

function TextCorruption.ForUI(text)
    return TextCorruption.Corrupt(text)
end

function TextCorruption.ForChat(text)
    return TextCorruption.Corrupt(text)
end
