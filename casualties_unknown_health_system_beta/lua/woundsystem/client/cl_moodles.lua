if WoundSystem and WoundSystem.Moodles and WoundSystem.Moodles._Loaded then
    hook.Remove("Think", "WoundSystem_MoodlesThink")
    hook.Remove("HUDPaint", "WoundSystem_MoodlesPaint")
    hook.Remove("PostDrawHUD", "WoundSystem_MoodlesPaint")
end

WoundSystem = WoundSystem or {}
WoundSystem.Moodles = WoundSystem.Moodles or {}

local Moodles = WoundSystem.Moodles
Moodles._Loaded = true
Moodles.Definitions = {}
Moodles.DefById = {}
Moodles.Active = Moodles.Active or {}
Moodles.Current = Moodles.Current or {}
Moodles.Layout = Moodles.Layout or {}
Moodles.VisibleScratch = Moodles.VisibleScratch or {}
Moodles.NextBuild = 0

-- Customize placement with the woundsys_moodles_* cvars.
-- Customize content by calling WoundSystem.Moodles.Register("id", {icon = "...", condition = function(ctx) return {intensity = 1, title = "...", desc = "..."} end}).

surface.CreateFont("WoundSystemMoodleCount", {font = "Trebuchet24", size = 20, weight = 900, antialias = true})

local cvEnabled = CreateClientConVar("woundsys_moodles_enabled", "1", true, false, "Draw WoundSystem symptom moodles.", 0, 1)
local cvScale = CreateClientConVar("woundsys_moodles_scale", "1", true, false, "Moodle icon scale.", 0.4, 3)
local cvIconSize = CreateClientConVar("woundsys_moodles_icon_size", "52", true, false, "Base moodle icon size.", 24, 128)
local cvGap = CreateClientConVar("woundsys_moodles_gap", "10", true, false, "Pixels between moodle icons.", 0, 64)
local cvColumns = CreateClientConVar("woundsys_moodles_columns", "10", true, false, "Moodle icons per row.", 1, 32)
local cvOffsetX = CreateClientConVar("woundsys_moodles_offset_x", "32", true, false, "Moodle anchor horizontal offset.", -3000, 3000)
local cvOffsetY = CreateClientConVar("woundsys_moodles_offset_y", "112", true, false, "Moodle anchor vertical offset.", -3000, 3000)
local cvAnchor = CreateClientConVar("woundsys_moodles_anchor", "bottomleft", true, false, "Moodle anchor: topleft, topright, bottomleft, bottomright, centerleft, centerright.")
local cvAlwaysSide = CreateClientConVar("woundsys_moodles_always_show_side", "0", true, false, "Always show side/secondary moodles.", 0, 1)
local cvSideOnCursor = CreateClientConVar("woundsys_moodles_side_on_cursor", "1", true, false, "Show side moodles while the mouse cursor is visible.", 0, 1)
local cvMaxMain = CreateClientConVar("woundsys_moodles_max_main", "10", true, false, "Maximum main moodles before secondary ones collapse.", 1, 40)
local cvUpdateRate = CreateClientConVar("woundsys_moodles_update_rate", "0.5", true, false, "Seconds between moodle condition rebuilds.", 0.1, 5)
local cvTooltip = CreateClientConVar("woundsys_moodles_tooltips", "1", true, false, "Show tooltips when hovering moodles with the cursor.", 0, 1)
local cvChipped = CreateClientConVar("woundsys_moodles_medical_chip", "1", true, false, "Show chip-gated diagnostic moodles.", 0, 1)
local cvDisabled = CreateClientConVar("woundsys_moodles_disabled", "", true, false, "Comma-separated moodle definition ids to hide.")

local MOODLE_PATH = "casunknown-images/moodles/"
local MatCache = {}
local BloodMoodleIcons = {
    amputation = true,
    bleeding = true,
    heavybleeding = true,
    hemothorax = true,
    hypertension = true,
    hypotension = true,
    internalbleed = true,
    maxbleeding = true,
    rippedeye = true,
    rippedjaw = true,
    smallbleeding = true,
    stroke = true
}
local BloodMoodleVariantExists = {}
local BackgroundByIntensity = {
    [0] = "mood1",
    [1] = "mood2",
    [2] = "mood3",
    [3] = "mood4",
    [4] = "mood5",
    [5] = "mood6",
    [6] = "mood7",
    [7] = "mood8",
    [8] = "moodlast"
}

local function HasBloodMoodleVariant(name)
    if BloodMoodleVariantExists[name] ~= nil then return BloodMoodleVariantExists[name] end

    BloodMoodleVariantExists[name] = file.Exists("materials/" .. MOODLE_PATH .. name .. ".png", "GAME")
    return BloodMoodleVariantExists[name]
end

local function BloodMoodleName(name)
    local cvBloodColor = GetConVar("woundsys_blood_color")
    if not cvBloodColor then return name end
    if string.lower(string.Trim(cvBloodColor:GetString() or "alien_yellow")) ~= "red" then return name end

    local padded = string.EndsWith(name, "_padded")
    local baseName = padded and string.sub(name, 1, -8) or name
    if not BloodMoodleIcons[string.lower(baseName)] then return name end

    local redName = padded and (baseName .. "_padded_red") or (baseName .. "_red")
    return HasBloodMoodleVariant(redName) and redName or name
end

local function Mat(name)
    if not name or name == "" then return nil end
    if not string.find(name, "/") then
        name = BloodMoodleName(name)
    end

    local path = string.find(name, "/") and name or (MOODLE_PATH .. name .. ".png")

    if not MatCache[path] then
        if WoundSystem.Client and WoundSystem.Client.PaddedMaterial then
            MatCache[path] = WoundSystem.Client.PaddedMaterial(path)
        else
            MatCache[path] = Material(path)
        end
    end

    return MatCache[path]
end

local function Number(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function Round(value)
    return math.Round and math.Round(value) or math.floor((value or 0) + 0.5)
end

local function LocalPlayerDead()
    local ply = LocalPlayer()
    return IsValid(ply) and not ply:Alive()
end

local function ClearActiveMoodles()
    table.Empty(Moodles.Active)
    table.Empty(Moodles.Current)
    table.Empty(Moodles.Layout)
    table.Empty(Moodles.VisibleScratch)
end

local function TrimLower(value)
    return string.lower(string.Trim(tostring(value or "")))
end

local function WithAlpha(color, alpha)
    return Color(color.r, color.g, color.b, math.Clamp(alpha or color.a or 255, 0, 255))
end

local function DisabledSet()
    local disabled = {}
    for _, part in ipairs(string.Explode(",", cvDisabled:GetString() or "")) do
        local id = TrimLower(part)
        if id ~= "" then disabled[id] = true end
    end
    return disabled
end

local function TextValue(value, ctx, moodle)
    if isfunction(value) then
        local ok, result = pcall(value, ctx, moodle)
        if ok then return tostring(result or "") end
        return ""
    end

    return tostring(value or "")
end

local function CorruptUIText(text)
    if WoundSystem.TextCorruption and WoundSystem.TextCorruption.ForUI then
        return WoundSystem.TextCorruption.ForUI(text)
    end

    return tostring(text or "")
end

local function Mood(intensity, title, desc, critical, extra)
    extra = extra or {}
    extra.intensity = intensity
    extra.title = title
    extra.desc = desc
    extra.critical = critical
    return extra
end

local function FormatSeconds(seconds)
    seconds = math.max(Number(seconds, 0), 0)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%02d:%02d", m, s)
end

function Moodles.Register(id, def)
    id = TrimLower(id)
    if id == "" or not istable(def) then return end

    def = table.Copy(def)
    def.id = id

    local existing = Moodles.DefById[id]
    if existing then
        for i, current in ipairs(Moodles.Definitions) do
            if current == existing then
                Moodles.Definitions[i] = def
                break
            end
        end
    else
        table.insert(Moodles.Definitions, def)
    end

    Moodles.DefById[id] = def
end

function Moodles.SetDisabled(id, disabled)
    id = TrimLower(id)
    if id == "" then return end

    local current = DisabledSet()
    current[id] = disabled == true or nil

    local parts = {}
    for key, value in pairs(current) do
        if value then table.insert(parts, key) end
    end
    table.sort(parts)
    RunConsoleCommand("woundsys_moodles_disabled", table.concat(parts, ","))
end

function Moodles.RebuildNow()
    Moodles.NextBuild = 0
end

local function Cardio()
    return (WoundSystemClientState and WoundSystemClientState.Cardio) or {}
end

local function Limbs()
    return (WoundSystemClientState and WoundSystemClientState.PlayerLimbs) or {}
end

local function GetContext()
    local ply = LocalPlayer()
    local cvForceUnchipped = GetConVar("woundsys_force_unchipped")
    local forceUnchipped = cvForceUnchipped and cvForceUnchipped:GetBool() or false
    return {
        ply = ply,
        c = Cardio(),
        limbs = Limbs(),
        happiness = (WoundSystemClientState and WoundSystemClientState.Happiness) or (IsValid(ply) and ply:GetNWFloat("WoundSystem_Happiness", 0)) or 0,
        chipped = not forceUnchipped and cvChipped:GetBool()
    }
end

local function Limb(ctx, id)
    return ctx.limbs and ctx.limbs[id] or nil
end

local function Head(ctx)
    return Limb(ctx, "head") or {}
end

local function Thorax(ctx)
    return Limb(ctx, "thorax") or {}
end

local function AnyLimb(ctx, fn)
    for id, state in pairs(ctx.limbs or {}) do
        if fn(state, id) then return true, state, id end
    end
    return false
end

local function MaxLimb(ctx, field)
    local maxValue = 0
    for _, state in pairs(ctx.limbs or {}) do
        maxValue = math.max(maxValue, Number(state[field], 0))
    end
    return maxValue
end

local function MaxBoneTimer(ctx)
    local maxValue = 0
    for _, state in pairs(ctx.limbs or {}) do
        if state.broken then
            maxValue = math.max(maxValue, Number(state.boneHealTimer, 0))
        end
    end
    return maxValue
end

local function MaxDislocationTimer(ctx)
    local maxValue = 0
    for _, state in pairs(ctx.limbs or {}) do
        if state.dislocated then
            maxValue = math.max(maxValue, Number(state.dislocationTimer, 0))
        end
    end
    return maxValue
end

local function InCardiacArrest(ctx)
    return Number(ctx.c.heartRate, 70) < 20
end

local function RegisterDefaults()
    Moodles.Register("focused", {
        icon = "focused",
        condition = function(ctx)
            if Number(ctx.c.focusedLevel, 0) > 0 then
                return Mood(8, "Focused", "Everything narrows into sharp focus.", true)
            end
        end
    })

    Moodles.Register("horrified", {
        icon = "horrified",
        condition = function(ctx)
            local value = Number(ctx.c.horrifiedLevel, 0)
            if value > 50 then
                return Mood(3, "Horrified", "Panic is overwhelming your ability to act.", true)
            elseif value > 0 then
                return Mood(1, "Impending doom", "Something feels terribly wrong.", false, {icon = "impendingdoom"})
            end
        end
    })

    Moodles.Register("tachycardia", {
        icon = "tachycardia",
        condition = function(ctx)
            local hr = Number(ctx.c.heartRate, 70)
            if InCardiacArrest(ctx) or hr <= 110 then return end
            return Mood((hr > 200) and 2 or ((hr > 160) and 1 or 0), "Tachycardia", string.format("Heart rate is elevated: %d BPM.", Round(hr)))
        end
    })

    Moodles.Register("bradycardia", {
        icon = "bradycardia",
        condition = function(ctx)
            local hr = Number(ctx.c.heartRate, 70)
            if InCardiacArrest(ctx) or hr >= 60 then return end
            return Mood((hr < 40) and 1 or 0, "Bradycardia", string.format("Heart rate is low: %d BPM.", Round(hr)))
        end
    })

    Moodles.Register("palpitations", {
        icon = "palpitations",
        condition = function(ctx)
            local hr = Number(ctx.c.heartRate, 70)
            local fib = Number(ctx.c.fibrillationProgress, 0)
            if fib > 50 or hr > 240 then
                return Mood(3, "Palpitations", "Your heartbeat feels irregular and forceful.")
            end
        end
    })

    Moodles.Register("laststand", {
        icon = "lastleg",
        condition = function(ctx)
            if Number(ctx.c.lastStandTime, 0) > 0 then
                return Mood(8, "Last stand", "A final surge is keeping you moving.")
            end
        end
    })

    Moodles.Register("braindamage", {
        icon = "braindamage",
        chippedOnly = true,
        condition = function(ctx)
            local brain = Number(ctx.c.brainHealth, 100)
            if brain < 30 then return Mood(3, "Severe brain damage", "Brain health is critically low.", true) end
            if brain < 60 then return Mood(2, "Brain damage", "Brain health is seriously reduced.") end
            if brain < 80 then return Mood(1, "Brain trauma", "Brain health is reduced.") end
            if brain < 95 then return Mood(0, "Mild brain trauma", "Brain health is below normal.") end
        end
    })

    Moodles.Register("stroke", {
        icon = "stroke",
        chippedOnly = true,
        condition = function(ctx)
            if Number(ctx.c.strokeAmount, 0) > 70 then
                return Mood(3, "Stroke", "Neurological damage is rapidly worsening.", true)
            end
        end
    })

    Moodles.Register("cardiacarrest", {
        icon = "cardiacarrest",
        condition = function(ctx)
            if InCardiacArrest(ctx) then
                return Mood(3, "Cardiac arrest", "The heart is no longer pumping effectively.", true)
            end
        end
    })

    Moodles.Register("arrythmia", {
        icon = "arrythmia",
        chippedOnly = true,
        condition = function(ctx)
            if InCardiacArrest(ctx) then return end
            local fib = Number(ctx.c.fibrillationProgress, 0)
            if fib > 75 then return Mood(3, "Ventricular fibrillation", "Heart rhythm is critically unstable.", true) end
            if fib > 50 then return Mood(2, "Arrhythmia", "Heart rhythm is unstable.", true) end
            if fib > 15 then return Mood(1, "Irregular heartbeat", "Heart rhythm is becoming unstable.") end
        end
    })

    Moodles.Register("hypotension", {
        icon = "hypotension",
        chippedOnly = true,
        condition = function(ctx)
            if InCardiacArrest(ctx) then return end
            local bp = Number(ctx.c.bloodPressure, 120)
            if bp < 60 then return Mood(3, "Critical hypotension", string.format("Blood pressure is critically low: %d.", Round(bp)), true) end
            if bp < 83 then return Mood(2, "Severe hypotension", string.format("Blood pressure is very low: %d.", Round(bp)), bp < 70) end
            if bp < 96 then return Mood(1, "Hypotension", string.format("Blood pressure is low: %d.", Round(bp))) end
            if bp < 110 then return Mood(0, "Low blood pressure", string.format("Blood pressure is slightly low: %d.", Round(bp))) end
        end
    })

    Moodles.Register("hypertension", {
        icon = "hypertension",
        chippedOnly = true,
        condition = function(ctx)
            if InCardiacArrest(ctx) then return end
            local bp = Number(ctx.c.bloodPressure, 120)
            if bp > 180 then return Mood(3, "Critical hypertension", string.format("Blood pressure is critically high: %d.", Round(bp)), true) end
            if bp > 162 then return Mood(2, "Severe hypertension", string.format("Blood pressure is very high: %d.", Round(bp))) end
            if bp > 145 then return Mood(1, "Hypertension", string.format("Blood pressure is high: %d.", Round(bp))) end
            if bp > 130 then return Mood(0, "Elevated blood pressure", string.format("Blood pressure is elevated: %d.", Round(bp))) end
        end
    })

    Moodles.Register("breathing", {
        icon = "cantbreathe",
        condition = function(ctx)
            local rr = Number(ctx.c.respiratoryRate, 100)
            if rr <= 10 then
                return Mood(3, "Cannot breathe", "Respiration has nearly stopped.", true)
            elseif rr < 50 then
                return Mood(1, "Hypoventilation", "Breathing is dangerously slow.", false, {icon = "hypoventilation"})
            elseif rr < 90 then
                return Mood(0, "Slow breathing", "Breathing is slower than normal.", false, {icon = "hypoventilation"})
            end
        end
    })

    Moodles.Register("thoraxdestroyed", {
        icon = "thoraxdestroyed",
        condition = function(ctx)
            if Number(Thorax(ctx).muscle, 100) < 4 then
                return Mood(3, "Thorax destroyed", "The torso can barely support respiration.", true)
            end
        end
    })

    Moodles.Register("hemothorax", {
        icon = "hemothorax",
        chippedOnly = true,
        condition = function(ctx)
            local value = Number(ctx.c.hemothorax, 0)
            if value > 40 then
                return Mood(1, "Hemothorax", string.format("Blood is accumulating around the lung: %d%%.", Round(value)), value > 70)
            end
        end
    })

    Moodles.Register("pulmonaryembolism", {
        icon = "pulmonaryembolism",
        chippedOnly = true,
        condition = function(ctx)
            if ctx.c.hasPulmonaryEmbolism then
                return Mood(3, "Pulmonary embolism", "A clot is blocking pulmonary circulation.", true)
            end
        end
    })

    Moodles.Register("oxygen", {
        icon = "oxygen",
        chippedOnly = true,
        condition = function(ctx)
            local oxy = Number(ctx.c.bloodOxygen, 98)
            if oxy < 45 then return Mood(3, "Critical hypoxia", string.format("Blood oxygen is critically low: %d%%.", Round(oxy))) end
            if oxy < 60 then return Mood(2, "Severe hypoxia", string.format("Blood oxygen is very low: %d%%.", Round(oxy))) end
            if oxy < 75 then return Mood(1, "Hypoxia", string.format("Blood oxygen is low: %d%%.", Round(oxy))) end
            if oxy < 90 then return Mood(0, "Low oxygen", string.format("Blood oxygen is below normal: %d%%.", Round(oxy))) end
        end
    })

    Moodles.Register("irradiated", {
        icon = "irradiated",
        chippedOnly = true,
        condition = function(ctx)
            local rad = Number(ctx.c.radiationSickness, 0)
            if rad > 80 then return Mood(3, "Radiation sickness", "Radiation exposure is critical.", true) end
            if rad > 50 then return Mood(2, "Radiation sickness", "Radiation exposure is severe.", true) end
            if rad > 30 then return Mood(1, "Irradiated", "Radiation exposure is causing sickness.") end
            if rad > 10 then return Mood(0, "Mild irradiation", "Radiation exposure is above safe levels.") end
        end
    })

    Moodles.Register("pain", {
        icon = "pain",
        condition = function(ctx)
            local pain = Number(ctx.c.avgPain, 0)
            if pain > 80 then return Mood(3, "Agony", string.format("Pain is overwhelming: %d%%.", Round(pain)), true) end
            if pain > 55 then return Mood(2, "Severe pain", string.format("Pain is severe: %d%%.", Round(pain))) end
            if pain > 30 then return Mood(1, "Pain", string.format("Pain is significant: %d%%.", Round(pain))) end
            if pain > 10 then return Mood(0, "Discomfort", string.format("Pain is noticeable: %d%%.", Round(pain))) end
        end
    })

    Moodles.Register("shock", {
        icon = "shock",
        condition = function(ctx)
            if Number(ctx.c.painShock, 0) > 0.3 or Number(ctx.c.cardioShock, 0) > 60 then
                return Mood(3, "Shock", "Shock is interfering with consciousness.")
            end
        end
    })

    Moodles.Register("overdose", {
        icon = "overdose",
        condition = function(ctx)
            local value = Number(ctx.c.actualOpiateReception or ctx.c.opiateReception, 0)
            if value > 80 then return Mood(3, "Opiate overdose", "Opiate reception is critically high.", true) end
            if value > 50 then return Mood(2, "Opiate overdose", "Opiates are strongly suppressing your system.", true) end
            if value > 20 then return Mood(1, "Opiated", "Opiates are strongly affecting your system.") end
            if value > 5 then return Mood(0, "Drugged", "Opiates are affecting your system.") end
        end
    })

    Moodles.Register("antidepressants", {
        icon = "happy",
        side = true,
        condition = function(ctx)
            local value = Number(ctx.c.antidepressantHappiness, 0)
            if value > 30 then return Mood(7, "Antidepressant effect", "Mood support is strongly active.") end
            if value > 15 then return Mood(6, "Antidepressant effect", "Mood support is active.") end
            if value > 5 then return Mood(5, "Mood support", "Antidepressants are affecting your mood.") end
        end
    })

    Moodles.Register("withdrawal", {
        icon = "withdrawal",
        chippedOnly = true,
        condition = function(ctx)
            local value = Number(ctx.c.actualOpiateReception or ctx.c.opiateReception, 0)
            if value < -34 then return Mood(3, "Severe withdrawal", "Withdrawal is critical.", true) end
            if value < -25 then return Mood(2, "Withdrawal", "Withdrawal symptoms are severe.") end
            if value < -15 then return Mood(1, "Withdrawal", "Withdrawal symptoms are present.") end
            if value < -5 then return Mood(0, "Mild withdrawal", "Withdrawal symptoms are beginning.") end
        end
    })

    Moodles.Register("stimulants", {
        icon = "stimulants",
        chippedOnly = true,
        condition = function(ctx)
            if ctx.c.onHardStimulants then
                return Mood(6, "Stimulated", "Hard stimulants are active.")
            end
        end
    })

    Moodles.Register("consciousness", {
        icon = "confused",
        condition = function(ctx)
            if Number(Head(ctx).muscle, 100) < 14.4 then
                return Mood(3, "Concussion", "Head trauma is severe.", true, {icon = "concussion"})
            end

            local consciousness = Number(ctx.c.consciousness, 100)
            if consciousness <= 20 then
                if ctx.c.sleeping then
                    return Mood(4, "Asleep", "You are sleeping.", false, {icon = "asleep"})
                end
                return Mood(3, "Unconscious", "Consciousness is critically low.", false, {icon = "unconscious"})
            end
            if consciousness < 30 then return Mood(3, "Incapacitated", "Consciousness is barely holding.") end
            if consciousness < 55 then return Mood(2, "Confused", "Thinking is heavily impaired.") end
            if consciousness < 72 then return Mood(1, "Dazed", "Thinking is impaired.") end
            if consciousness < 90 then return Mood(0, "Lightheaded", "Focus is slightly impaired.") end
        end
    })

    Moodles.Register("drugoverdose", {
        icon = "drugoverdose",
        chippedOnly = true,
        condition = function(ctx)
            local value = Number(ctx.c.overdoseIndex, 0)
            if value > 3 then
                return Mood(3, "Drug overdose", "A dangerous overdose reaction is active.", true)
            end
            if value > 0.5 then
                return Mood(2, "Drug overdose", "A dangerous overdose reaction is building.", true)
            end
        end
    })

    Moodles.Register("internalbleed", {
        icon = "internalBleed",
        chippedOnly = true,
        condition = function(ctx)
            local value = Number(ctx.c.internalBleeding, 0)
            if value > 5 then
                return Mood(math.Clamp(math.floor((value - 1) / 25), 0, 3), "Internal bleeding", string.format("Internal bleeding: %d%%.", Round(value)), value > 50)
            end
        end
    })

    Moodles.Register("bleeding", {
        icon = "smallbleeding",
        condition = function(ctx)
            local value = Number(ctx.c.totalBleedSpeed, 0)
            if value > 0.3 then return Mood(3, "Catastrophic bleeding", "Bleeding is life threatening.", true, {icon = "maxbleeding"}) end
            if value > 0.15 then return Mood(2, "Heavy bleeding", "Bleeding is severe.", true, {icon = "heavybleeding"}) end
            if value > 0.06 then return Mood(1, "Bleeding", "Bleeding is moderate.", false, {icon = "bleeding"}) end
            if value > 0 then return Mood(0, "Minor bleeding", "Bleeding is present.") end
        end
    })

    Moodles.Register("exertion", {
        icon = "exertion",
        condition = function(ctx)
            local stamina = Number(ctx.c.stamina, 100)
            if stamina <= 15 then return Mood(3, "Exhausted", string.format("Stamina is critically low: %d%%.", Round(stamina)), true) end
            if stamina < 35 then return Mood(2, "Exerted", string.format("Stamina is very low: %d%%.", Round(stamina))) end
            if stamina < 50 then return Mood(1, "Tired muscles", string.format("Stamina is low: %d%%.", Round(stamina))) end
            if stamina < 70 then return Mood(0, "Light exertion", string.format("Stamina is reduced: %d%%.", Round(stamina))) end
        end
    })

    Moodles.Register("brokenbone", {
        icon = "brokenbone",
        chippedOnly = true,
        condition = function(ctx)
            local value = MaxBoneTimer(ctx)
            if value > 0 then
                return Mood(math.Clamp(Round(value * 0.03), 0, 3), "Broken bone", "A fracture is healing.")
            end
        end
    })

    Moodles.Register("dislocation", {
        icon = "dislocation",
        chippedOnly = true,
        condition = function(ctx)
            local value = MaxDislocationTimer(ctx)
            if value > 0 then
                return Mood(math.Clamp(Round(value * 0.03), 0, 3), "Dislocation", "A dislocation is healing.")
            end
        end
    })

    Moodles.Register("brokenneck", {
        icon = "brokenneck",
        chippedOnly = true,
        condition = function(ctx)
            local head = Head(ctx)
            if head.broken then
                return Mood(math.Clamp(Round(Number(head.boneHealTimer, 0) * 0.03), 0, 3), "Broken neck", "The neck is fractured.")
            end
        end
    })

    Moodles.Register("brokenribs", {
        icon = "brokenribs",
        chippedOnly = true,
        condition = function(ctx)
            local thorax = Thorax(ctx)
            if thorax.broken then
                return Mood(math.Clamp(Round(Number(thorax.boneHealTimer, 0) * 0.03), 0, 3), "Broken ribs", "The ribs are fractured.")
            end
        end
    })

    Moodles.Register("jawspine", {
        icon = "dislocatedjaw",
        chippedOnly = true,
        condition = function(ctx)
            local thorax = Thorax(ctx)
            if thorax.dislocated then
                return Mood(math.Clamp(Round(Number(thorax.dislocationTimer, 0) * 0.03), 0, 3), "Dislocated spine", "The spine is dislocated.", false, {icon = "dislocatedspine"})
            end
        end
    })

    Moodles.Register("infected", {
        icon = "infected",
        condition = function(ctx)
            local value = MaxLimb(ctx, "infection")
            if value > 80 then return Mood(3, "Severe infection", "A limb infection is severe.") end
            if value > 60 then return Mood(2, "Infection", "A limb infection is worsening.") end
            if value > 40 then return Mood(1, "Infection", "A limb infection is present.") end
            if value > 25 then return Mood(0, "Early infection", "A limb infection is beginning.") end
        end
    })

    Moodles.Register("sepsis", {
        icon = "sepsis",
        chippedOnly = true,
        condition = function(ctx)
            local value = Number(ctx.c.septicShock, 0)
            if value > 80 then return Mood(3, "Sepsis", "Septic shock is critical.", true) end
            if value > 50 then return Mood(2, "Sepsis", "Septic shock is severe.") end
            if value > 10 then return Mood(1, "Sepsis", "Septic shock is developing.") end
        end
    })

    Moodles.Register("venom", {
        icon = "venom",
        condition = function(ctx)
            local value = Number(ctx.c.venomCurrent, 0)
            if value > 90 then return Mood(3, "Venom", "Venom level is critical.") end
            if value > 55 then return Mood(2, "Venom", "Venom level is high.") end
            if value > 25 then return Mood(1, "Venom", "Venom is spreading.") end
            if value > 2 then return Mood(0, "Venom", "Venom is present.") end
        end
    })

    Moodles.Register("tired", {
        icon = "tired",
        condition = function(ctx)
            return nil
        end
    })

    Moodles.Register("hunger", {
        icon = "hunger",
        condition = function(ctx)
            local hunger = Number(ctx.c.hunger, 100)
            local moodMult = math.Clamp(1 + Number(ctx.happiness, 0) * 0.009, 0, 1)
            if hunger <= 15 * moodMult then return Mood(3, "Starving", "Hunger is critical.", hunger <= 0) end
            if hunger < 35 * moodMult then return Mood(2, "Very hungry", "Hunger is severe.") end
            if hunger < 50 * moodMult then return Mood(1, "Hungry", "Hunger is noticeable.") end
            if hunger < 75 * moodMult then return Mood(0, "Peckish", "Hunger is slightly low.") end
            if hunger > 120 then return Mood(5, "Stuffed", "You are uncomfortably full.") end
            if hunger > 100 then return Mood(4, "Full", "You are well fed.") end
        end
    })

    Moodles.Register("thirst", {
        icon = "thirst",
        condition = function(ctx)
            local thirst = Number(ctx.c.thirst, 100)
            if thirst <= 20 then return Mood(3, "Dehydrated", "Thirst is critical.", thirst <= 0) end
            if thirst < 35 then return Mood(2, "Very thirsty", "Thirst is severe.") end
            if thirst < 55 then return Mood(1, "Thirsty", "Thirst is noticeable.") end
            if thirst < 75 then return Mood(0, "Slightly thirsty", "Thirst is slightly low.") end
        end
    })

    Moodles.Register("overhydrated", {
        icon = "overhydrated",
        condition = function(ctx)
            local thirst = Number(ctx.c.thirst, 100)
            if thirst > 175 then return Mood(3, "Overhydrated", "Fluid intake is dangerously high.", true) end
            if thirst > 125 then return Mood(1, "Overhydrated", "Fluid intake is high.") end
            if thirst > 100 then return Mood(0, "Well hydrated", "Fluid intake is above normal.") end
        end
    })

    Moodles.Register("sick", {
        icon = "sick",
        condition = function(ctx)
            local sick = Number(ctx.c.sicknessAmount, 0)
            if sick > 75 then return Mood(3, "Very sick", "Sickness is severe.", sick > 95) end
            if sick > 50 then return Mood(2, "Sick", "Sickness is worsening.") end
            if sick > 30 then return Mood(1, "Queasy", "Sickness is present.") end
            if sick > 10 then return Mood(0, "Nauseous", "Sickness is mild.") end
        end
    })

    Moodles.Register("nausea", {
        icon = "sick",
        condition = function(ctx)
            local motion = Number(WoundSystemSpinNauseaIntensity or 0, 0)
            if motion > 0.65 then return Mood(3, "Disoriented", "Severe head spinning is causing intense nausea and disorientation.", true) end
            if motion > 0.40 then return Mood(2, "Dizzy", "Rapid head rotation is causing dizziness and motion nausea.") end
            if motion > 0.20 then return Mood(1, "Slight Nausea", "Frequent camera motion is making you feel slightly nauseous.") end
        end
    })

    Moodles.Register("temperature", {
        icon = "hot",
        condition = function(ctx)
            local temp = Number(ctx.c.temperature, 37)
            if temp > 41.5 then return Mood(3, "Hyperthermia", string.format("Body temperature is critical: %.1f C.", temp), true) end
            if temp > 40.25 then return Mood(2, "Very hot", string.format("Body temperature is high: %.1f C.", temp)) end
            if temp > 39 then return Mood(1, "Hot", string.format("Body temperature is elevated: %.1f C.", temp)) end
            if temp > 38 then return Mood(0, "Warm", string.format("Body temperature is slightly elevated: %.1f C.", temp)) end
            if temp < 28 then return Mood(3, "Hypothermia", string.format("Body temperature is critical: %.1f C.", temp), true, {icon = "cold"}) end
            if temp < 32.5 then return Mood(2, "Very cold", string.format("Body temperature is low: %.1f C.", temp), false, {icon = "cold"}) end
            if temp < 34 then return Mood(1, "Cold", string.format("Body temperature is reduced: %.1f C.", temp), false, {icon = "cold"}) end
            if temp < 35.5 then return Mood(0, "Chilly", string.format("Body temperature is slightly low: %.1f C.", temp), false, {icon = "cold"}) end
        end
    })

    Moodles.Register("mood", {
        icon = "sad",
        condition = function(ctx)
            local happiness = Number(ctx.happiness, 0)
            if happiness <= -75 then return Mood(3, "Miserable", "Mood is dangerously low.", false, {icon = "miserable"}) end
            if happiness < -50 then return Mood(2, "Depressed", "Mood is very low.", false, {icon = "depression"}) end
            if happiness < -30 then return Mood(1, "Gloomy", "Mood is low.", false, {icon = "gloomy"}) end
            if happiness < -10 then return Mood(0, "Sad", "Mood is below normal.") end
            if happiness >= 75 then return Mood(7, "Ecstatic", "Mood is excellent.", false, {icon = "happy"}) end
            if happiness > 50 then return Mood(6, "Happy", "Mood is very good.", false, {icon = "happy"}) end
            if happiness > 30 then return Mood(5, "Content", "Mood is good.", false, {icon = "happy"}) end
            if happiness > 10 then return Mood(4, "Comfortable", "Mood is above normal.", false, {icon = "happy"}) end
        end
    })

    Moodles.Register("clawdamage", {
        icon = "clawdamage",
        condition = function(ctx)
            local claw = Number(ctx.c.clawHealth, 100)
            if claw < 25 then return Mood(1, "Damaged claws", "Claw condition is poor.") end
            if claw < 60 then return Mood(0, "Worn claws", "Claw condition is reduced.") end
        end
    })

    Moodles.Register("hearingloss", {
        icon = "hearingloss",
        condition = function(ctx)
            local hearing = Number(ctx.c.hearingLoss, 0)
            if hearing > 70 then return Mood(2, "Deafened", "Hearing loss is severe.") end
            if hearing > 40 then return Mood(1, "Hearing loss", "Hearing is impaired.") end
            if hearing > 15 then return Mood(0, "Ringing ears", "Hearing is slightly impaired.") end
        end
    })

    Moodles.Register("dirty", {
        icon = "dirty",
        condition = function(ctx)
            local dirty = Number(ctx.c.dirtyness, 0)
            if dirty > 80 then return Mood(1, "Filthy", string.format("Dirtyness: %d%%.", Round(dirty))) end
            if dirty > 50 then return Mood(0, "Dirty", string.format("Dirtyness: %d%%.", Round(dirty))) end
        end
    })

    Moodles.Register("encumbered", {
        icon = "encumbered",
        condition = function(ctx)
            local enc = Number(ctx.c.overEncumberance, 0)
            if enc > 0.85 then return Mood(3, "Overencumbered", string.format("Carry burden: %d%%.", Round(enc * 100)), true) end
            if enc > 0.55 then return Mood(2, "Encumbered", string.format("Carry burden: %d%%.", Round(enc * 100))) end
            if enc > 0.3 then return Mood(1, "Heavy load", string.format("Carry burden: %d%%.", Round(enc * 100))) end
            if enc > 0 then return Mood(0, "Loaded", string.format("Carry burden: %d%%.", Round(enc * 100))) end
        end
    })

    Moodles.Register("wet", {
        icon = "wet",
        condition = function(ctx)
            local wet = Number(ctx.c.wetness, 0)
            if wet > 70 then return Mood(3, "Soaked", "Wetness is severe.") end
            if wet > 45 then return Mood(2, "Wet", "Wetness is high.") end
            if wet > 20 then return Mood(1, "Damp", "Wetness is noticeable.") end
            if wet > 5 then return Mood(0, "Slightly damp", "Wetness is mild.") end
        end
    })

    Moodles.Register("immunity", {
        icon = "lowimmunity",
        side = true,
        chippedOnly = true,
        condition = function(ctx)
            local immunity = Number(ctx.c.immunity, 100)
            if immunity > 150 then return Mood(5, "High immunity", "Immune response is strong.", false, {icon = "highimmunity"}) end
            if immunity < 55 then return Mood(1, "Low immunity", "Immune response is weak.") end
        end
    })

    Moodles.Register("keratinbooster", {
        icon = "keratinbooster",
        side = true,
        chippedOnly = true,
        condition = function(ctx)
            local time = Number(ctx.c.clawRegrowTime, 0)
            if time > 0 then
                return Mood(5, "Keratin booster", "Claw regrowth time: " .. FormatSeconds(time) .. ".")
            end
        end
    })

    Moodles.Register("weight", {
        icon = "underweight",
        side = true,
        condition = function(ctx)
            local weight = Number(ctx.c.weightOffset, 0)
            if weight <= -50 then return Mood(3, "Severely underweight", "Body weight is dangerously low.") end
            if weight < -40 then return Mood(2, "Underweight", "Body weight is very low.") end
            if weight < -30 then return Mood(1, "Underweight", "Body weight is low.") end
            if weight < -15 then return Mood(0, "Thin", "Body weight is below normal.") end
            if weight >= 50 then return Mood(3, "Severely overweight", "Body weight is dangerously high.", false, {icon = "overweight"}) end
            if weight > 40 then return Mood(2, "Overweight", "Body weight is very high.", false, {icon = "overweight"}) end
            if weight > 30 then return Mood(1, "Overweight", "Body weight is high.", false, {icon = "overweight"}) end
            if weight > 15 then return Mood(0, "Heavy", "Body weight is above normal.", false, {icon = "overweight"}) end
        end
    })

    Moodles.Register("trauma", {
        icon = "trauma",
        side = true,
        condition = function(ctx)
            local trauma = Number(ctx.c.traumaAmount, 0)
            if trauma > 80 then return Mood(3, "Traumatized", "Trauma is severe.") end
            if trauma > 45 then return Mood(2, "Trauma", "Trauma is significant.") end
            if trauma > 25 then return Mood(1, "Shaken", "Trauma is present.") end
        end
    })

    Moodles.Register("energized", {
        icon = "energized",
        side = true,
        chippedOnly = true,
        condition = function(ctx)
            local time = Number(ctx.c.caffeinated, 0)
            if time > 0 then
                return Mood(5, "Energized", "Stimulant time remaining: " .. FormatSeconds(time) .. ".")
            end
        end
    })

    Moodles.Register("badsleep", {
        icon = "badsleep",
        side = true,
        chippedOnly = true,
        condition = function(ctx)
            if Number(ctx.c.badSleepAmount, 0) > 0 then
                return Mood(0, "Bad sleep", "Poor rest is affecting recovery.")
            end
        end
    })

    Moodles.Register("impairedspeech", {
        icon = "impairedspeech",
        side = true,
        condition = function(ctx)
            if ctx.c.impairedSpeech then
                return Mood(0, "Impaired speech", "Speech is impaired.")
            end
        end
    })

    Moodles.Register("rnrs", {
        icon = "rnrs",
        side = true,
        chippedOnly = true,
        condition = function(ctx)
            local time = Number(ctx.c.brainGrowSickness, 0)
            if time > 0 then
                return Mood(0, "Neural recovery sickness", "Time remaining: " .. FormatSeconds(time) .. ".")
            end
        end
    })

    Moodles.Register("disfigurement", {
        icon = "rippedjaw",
        side = true,
        condition = function(ctx)
            local head = Head(ctx)
            local eyes = Number(head.eyes, 2)
            if ctx.c.disfigured then
                return Mood(3, "Disfigured", "The face is badly damaged.")
            end
            if ctx.c.bothEyesGone or eyes <= 0 then
                return Mood(3, "Eyes gone", "Both eyes are missing.", false, {icon = "rippedeye"})
            end
            if ctx.c.eyeGone or eyes == 1 then
                return Mood(2, "Eye gone", "One eye is missing.", false, {icon = "rippedeye"})
            end
        end
    })

    Moodles.Register("amputation", {
        icon = "amputation",
        side = true,
        condition = function(ctx)
            local hasAmputation = AnyLimb(ctx, function(state) return state.dismembered == true end)
            if hasAmputation then
                return Mood(3, "Amputation", "One or more limbs are missing.")
            end
        end
    })

    Moodles.Register("fightorflight", {
        icon = "fightorflight",
        side = true,
        chippedOnly = true,
        condition = function(ctx)
            local adr = Number(ctx.c.adrenaline or ctx.c.curAdrenaline, 0)
            if adr > 20 then
                return Mood((adr > 65) and 1 or 0, "Fight or flight", "Adrenaline is elevated.")
            end
        end
    })

    Moodles.Register("hollow", {
        icon = "hollow",
        side = true,
        condition = function(ctx)
            if ctx.c.mindWipe then
                return Mood(0, "Hollow", "Your emotional response is suppressed.")
            end
        end
    })
end

local function NormalizeMoodle(def, ctx, result)
    if result == true then result = {} end
    if not istable(result) then return nil end

    local moodle = {
        id = result.id or def.id,
        icon = result.icon or def.icon or def.id,
        intensity = math.Clamp(math.floor(Number(result.intensity, Number(def.intensity, 0))), 0, 8),
        title = result.title or def.title or def.id,
        desc = result.desc or def.desc or "",
        critical = result.critical == true or (result.critical == nil and def.critical == true),
        side = result.side == true or (result.side == nil and def.side == true),
        chippedOnly = result.chippedOnly == true or (result.chippedOnly == nil and def.chippedOnly == true)
    }

    if WoundSystem.CAS3Locale and WoundSystem.CAS3Locale.ApplyMoodleText then
        WoundSystem.CAS3Locale.ApplyMoodleText(moodle)
    end

    if moodle.chippedOnly and not ctx.chipped then return nil end
    moodle.title = TextValue(moodle.title, ctx, moodle)
    moodle.desc = TextValue(moodle.desc, ctx, moodle)
    moodle.key = moodle.id .. ":" .. moodle.icon .. ":" .. tostring(moodle.intensity)
    return moodle
end

local function AddResult(out, def, ctx, result)
    if result == nil or result == false then return end

    if istable(result) and result[1] and not result.icon and not result.intensity then
        for _, child in ipairs(result) do
            local moodle = NormalizeMoodle(def, ctx, child)
            if moodle then table.insert(out, moodle) end
        end
        return
    end

    local moodle = NormalizeMoodle(def, ctx, result)
    if moodle then table.insert(out, moodle) end
end

local function BuildMoodles()
    if LocalPlayerDead() then return {} end

    local ctx = GetContext()
    if not IsValid(ctx.ply) or not ctx.ply:Alive() then return {} end

    local disabled = DisabledSet()
    local out = {}

    for _, def in ipairs(Moodles.Definitions) do
        if not disabled[def.id] and def.enabled ~= false and isfunction(def.condition) then
            local ok, result = pcall(def.condition, ctx, def)
            if ok then
                AddResult(out, def, ctx, result)
            end
        end
    end

    return out
end

local function RebuildActive()
    local now = CurTime()
    local built = BuildMoodles()
    local seen = {}

    for _, moodle in ipairs(built) do
        seen[moodle.key] = true
        if not Moodles.Active[moodle.key] then
            Moodles.Active[moodle.key] = {appeared = now}
        end
    end

    for key in pairs(Moodles.Active) do
        if not seen[key] then
            Moodles.Active[key] = nil
        end
    end

    Moodles.Current = built
end

local function ShowSideMoodles()
    if cvAlwaysSide:GetBool() then return true end
    if cvSideOnCursor:GetBool() and vgui.CursorVisible() then return true end
    return false
end

local function VisibleMoodles()
    local showSide = ShowSideMoodles()
    local maxMain = math.max(cvMaxMain:GetInt(), 1)
    local visible = Moodles.VisibleScratch
    table.Empty(visible)
    local hiddenSide = 0
    local mainCount = 0

    for _, moodle in ipairs(Moodles.Current or {}) do
        if moodle.side then
            if showSide then
                visible[#visible + 1] = moodle
            else
                hiddenSide = hiddenSide + 1
            end
        elseif mainCount < maxMain then
            mainCount = mainCount + 1
            visible[#visible + 1] = moodle
        else
            hiddenSide = hiddenSide + 1
        end
    end

    return visible, hiddenSide
end

local function LayoutPosition(index, size, gap, columns)
    columns = math.max(columns, 1)
    local col = (index - 1) % columns
    local row = math.floor((index - 1) / columns)
    local anchor = TrimLower(cvAnchor:GetString())
    local right = string.find(anchor, "right", 1, true) ~= nil
    local bottom = string.find(anchor, "bottom", 1, true) ~= nil
    local center = string.find(anchor, "center", 1, true) ~= nil

    local step = size + gap
    local x
    local y

    if right then
        x = ScrW() - cvOffsetX:GetFloat() - size - (col * step)
    else
        x = cvOffsetX:GetFloat() + (col * step)
    end

    if center then
        y = ScrH() * 0.5 + cvOffsetY:GetFloat() + (row * step)
    elseif bottom then
        y = ScrH() - cvOffsetY:GetFloat() - size - (row * step)
    else
        y = cvOffsetY:GetFloat() + (row * step)
    end

    return x, y
end

local function DrawMaterial(name, x, y, w, h, color)
    local mat = Mat(name)
    if not mat or mat:IsError() then return end

    if WoundSystem.Client and WoundSystem.Client.SetGuiMaterial and WoundSystem.Client.DrawRectInt then
        WoundSystem.Client.SetGuiMaterial(mat)
        surface.SetDrawColor(color.r, color.g, color.b, color.a)
        WoundSystem.Client.DrawRectInt(x, y, w, h)
        return
    end

    surface.SetMaterial(mat)
    surface.SetDrawColor(color.r, color.g, color.b, color.a)
    surface.DrawTexturedRect(math.Round(x), math.Round(y), math.Round(w), math.Round(h))
end

local function DrawMoodleGlow(drawX, drawY, drawSize, alpha)
    local glowW = drawSize
    local glowH = drawSize * 6
    local glowX = drawX
    local glowY = drawY - (glowH - drawSize) * 0.5

    DrawMaterial("moodleglow", glowX, glowY, glowW, glowH, Color(255, 255, 255, alpha))
end

local function DrawMoodle(moodle, index, size, gap, columns)
    local x, y = LayoutPosition(index, size, gap, columns)
    local active = Moodles.Active[moodle.key] or {appeared = CurTime()}
    local age = CurTime() - (active.appeared or CurTime())
    local pop = math.Clamp(1 - age / 0.5, 0, 1)
    local alpha = 255 * (1 - pop)
    local drawSize = size * (1 + pop * 1.5)
    local drawX = x - (drawSize - size) * 0.5
    local drawY = y - (drawSize - size) * 0.5 - (pop * 36)

    if moodle.critical then
        drawY = drawY + math.sin(CurTime() * 6) * 4
    end

    local color = Color(255, 255, 255, alpha)
    DrawMaterial(BackgroundByIntensity[moodle.intensity] or "mood1", drawX, drawY, drawSize, drawSize, color)
    DrawMaterial(moodle.icon, drawX, drawY, drawSize, drawSize, color)

    if moodle.critical then
        local flashAlpha = alpha * math.abs(math.sin(CurTime() * 2.5))
        DrawMoodleGlow(drawX, drawY, drawSize, flashAlpha)
    end

    local layout = Moodles.Layout[moodle.key]
    if not layout then
        layout = {}
        Moodles.Layout[moodle.key] = layout
    end
    layout.x = drawX
    layout.y = drawY
    layout.w = drawSize
    layout.h = drawSize
    layout.moodle = moodle
end

local function DrawBonus(count, index, size, gap, columns)
    if count <= 0 then return end
    local x, y = LayoutPosition(index, size, gap, columns)
    draw.RoundedBox(8, x, y, size, size, Color(15, 15, 18, 205))
    draw.SimpleText("+" .. tostring(count), "WoundSystemMoodleCount", x + size * 0.5, y + size * 0.5, Color(235, 235, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function DrawTooltip()
    if not cvTooltip:GetBool() or not vgui.CursorVisible() then return end

    local mx, my = gui.MousePos()
    if mx <= 0 and my <= 0 then return end

    local hovered
    for _, item in pairs(Moodles.Layout) do
        if mx >= item.x and mx <= item.x + item.w and my >= item.y and my <= item.y + item.h then
            hovered = item.moodle
            break
        end
    end
    if not hovered then return end

    if WoundSystemDrawCasTooltip then
        WoundSystemDrawCasTooltip(hovered.title or hovered.id, hovered.desc or "No description available.", mx, my, "moodle_" .. tostring(hovered.id), {
            noPop = true
        })
        return
    end

    local style = WoundSystemTooltipStyle or {
        backgroundColor = Color(10, 10, 11, 245),
        titleColor = Color(255, 255, 255),
        descriptionColor = Color(120, 120, 120),
        cursorOffsetX = 30,
        cursorOffsetY = 30,
        tabPaddingX = 0,
        tabPaddingY = 2,
        bodyPaddingX = 1,
        bodyPaddingY = 2,
        lineSpacing = 16,
        headerBodyGap = 0,
        fontTitle = "RetroTooltipTitle",
        fontDesc = "RetroTooltipDesc"
    }

    local titleText = CorruptUIText(hovered.title or hovered.id)
    local descLines = string.Explode("\n", CorruptUIText(hovered.desc or "No description available."))

    surface.SetFont(style.fontTitle)
    local tW, tH = surface.GetTextSize(titleText)

    surface.SetFont(style.fontDesc)
    local maxDescW = 0
    for _, line in ipairs(descLines) do
        local lw = surface.GetTextSize(line)
        if lw > maxDescW then maxDescW = lw end
    end

    local tabW = tW + (style.tabPaddingX * 2)
    local tabH = tH + (style.tabPaddingY * 2)
    local bodyW = math.max(tabW + (style.bodyPaddingX * 2), maxDescW + (style.bodyPaddingX * 2))
    local bodyH = (#descLines * style.lineSpacing) + (style.bodyPaddingY * 2) + 10

    local tipX, tipY = mx + style.cursorOffsetX, my + style.cursorOffsetY
    if tipX + bodyW > ScrW() then tipX = mx - bodyW - style.cursorOffsetX end
    if tipY + tabH + bodyH > ScrH() then tipY = my - tabH - bodyH - style.cursorOffsetY end

    surface.SetDrawColor(style.backgroundColor.r, style.backgroundColor.g, style.backgroundColor.b, style.backgroundColor.a)
    surface.DrawRect(tipX, tipY, tabW, tabH)
    surface.DrawRect(tipX, tipY + tabH + style.headerBodyGap, bodyW, bodyH)

    draw.SimpleText(titleText, style.fontTitle, tipX + style.tabPaddingX, tipY + style.tabPaddingY, style.titleColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    local startY = tipY + tabH + style.headerBodyGap + style.bodyPaddingY
    for i, line in ipairs(descLines) do
        draw.SimpleText(line, style.fontDesc, tipX + style.bodyPaddingX, startY + ((i - 1) * style.lineSpacing), style.descriptionColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
end

RegisterDefaults()

hook.Add("Think", "WoundSystem_MoodlesThink", function()
    if WoundSystem and WoundSystem.Client and WoundSystem.Client.IsEnabled and not WoundSystem.Client.IsEnabled() then
        ClearActiveMoodles()
        return
    end

    if not cvEnabled:GetBool() then return end
    if LocalPlayerDead() then
        ClearActiveMoodles()
        return
    end

    local now = CurTime()
    if now < (Moodles.NextBuild or 0) then return end
    Moodles.NextBuild = now + math.max(cvUpdateRate:GetFloat(), 0.1)
    RebuildActive()
end)

hook.Add("PostDrawHUD", "WoundSystem_MoodlesPaint", function()
    if WoundSystem and WoundSystem.Client and WoundSystem.Client.IsEnabled and not WoundSystem.Client.IsEnabled() then
        table.Empty(Moodles.Layout)
        return
    end

    if not cvEnabled:GetBool() then return end
    if LocalPlayerDead() then
        table.Empty(Moodles.Layout)
        return
    end
    local visible, hiddenSide = VisibleMoodles()
    table.Empty(Moodles.Layout)

    local size = math.max(cvIconSize:GetFloat(), 24) * math.max(cvScale:GetFloat(), 0.1)
    local gap = math.max(cvGap:GetFloat(), 0) * math.max(cvScale:GetFloat(), 0.1)
    local columns = math.max(cvColumns:GetInt(), 1)

    for i, moodle in ipairs(visible) do
        DrawMoodle(moodle, i, size, gap, columns)
    end

    if hiddenSide > 0 then
        DrawBonus(hiddenSide, #visible + 1, size, gap, columns)
    end

    DrawTooltip()
end)
