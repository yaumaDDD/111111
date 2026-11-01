if WoundSystem and WoundSystem.HappinessClientLoaded then
    hook.Remove("InitPostEntity", "WoundSystem_HappinessClientInit")
    timer.Remove("WoundSystem_HappinessClientSync")
end

WoundSystem = WoundSystem or {}
WoundSystem.HappinessClientLoaded = true

local HAPPINESS_NW = "WoundSystem_Happiness"

WoundSystemClientState = WoundSystemClientState or {}
WoundSystemClientState.Happiness = WoundSystemClientState.Happiness or 0
WoundSystemHappiness = WoundSystemHappiness or 0

WoundSystemMoodIconConfig = WoundSystemMoodIconConfig or {
    x = 31,
    y = 60,
    scale = 2.5,
    baseSize = 11,
    texturePadding = 1,
    standalone = false,
    thresholds = {
        verysad = {-100, -45.1},
        sad = {-45, -10},
        neutral = {-9.9, 9.9},
        happy = {10, 45},
        veryhappy = {45.1, 100}
    }
}

local MoodIcons = {
    verysad = Material("casunknown-images/moodicons/verysad_padded.png"),
    sad = Material("casunknown-images/moodicons/sad_padded.png"),
    neutral = Material("casunknown-images/moodicons/neutral_padded.png"),
    happy = Material("casunknown-images/moodicons/happy_padded.png"),
    veryhappy = Material("casunknown-images/moodicons/veryhappy_padded.png")
}

local function SyncHappiness()
    if WoundSystem and WoundSystem.Client and WoundSystem.Client.IsEnabled and not WoundSystem.Client.IsEnabled() then
        WoundSystemClientState.Happiness = 0
        WoundSystemHappiness = 0
        return
    end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local value = ply:GetNWFloat(HAPPINESS_NW, 0)
    WoundSystemClientState.Happiness = value
    WoundSystemHappiness = value
end

hook.Add("InitPostEntity", "WoundSystem_HappinessClientInit", SyncHappiness)
timer.Create("WoundSystem_HappinessClientSync", 0.25, 0, SyncHappiness)

local function GetMoodIconName(happiness)
    local thresholds = WoundSystemMoodIconConfig.thresholds

    for _, name in ipairs({"verysad", "sad", "neutral", "happy", "veryhappy"}) do
        local range = thresholds[name]
        if range and happiness >= range[1] and happiness <= range[2] then
            return name
        end
    end

    return "neutral"
end

function WoundSystemDrawMoodIcon(x, y, scaleOverride)
    local cfg = WoundSystemMoodIconConfig
    local happiness = math.Round(WoundSystemClientState.Happiness or 0, 1)
    local mat = MoodIcons[GetMoodIconName(happiness)]
    if not mat or mat:IsError() then return end

    local drawScale = (scaleOverride or 1) * (cfg.scale or 2.5)
    local padding = cfg.texturePadding or 0
    local size = ((cfg.baseSize or 11) + (padding * 2)) * drawScale

    surface.SetMaterial(mat)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawTexturedRect(math.Round(x - (padding * drawScale)), math.Round(y - (padding * drawScale)), math.Round(size), math.Round(size))
end

hook.Add("HUDPaint", "WoundSystem_DrawMoodIcon", function()
    if WoundSystem and WoundSystem.Client and WoundSystem.Client.IsEnabled and not WoundSystem.Client.IsEnabled() then return end

    local cfg = WoundSystemMoodIconConfig
    if not cfg.standalone then return end

    WoundSystemDrawMoodIcon(cfg.x or 32, cfg.y or 64)
end)
