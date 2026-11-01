if WoundSystem and WoundSystem.SelfTalkHUD and WoundSystem.SelfTalkHUD._Loaded then
    hook.Remove("HUDPaint", "WoundSystem_SelfTalkHUDPaint")
    hook.Remove("PlayerDeath", "WoundSystem_SelfTalkHUDClearOnDeath")
end

WoundSystem = WoundSystem or {}
WoundSystem.SelfTalkHUD = WoundSystem.SelfTalkHUD or {}
WoundSystem.SelfTalkHUD._Loaded = true

local HUD = WoundSystem.SelfTalkHUD
local TALK_SOUND = "speech.ogg"
local IMPAIRED_TALK_SOUND = "speechbad.ogg"

surface.CreateFont("WoundSystemSelfTalk", {
    font = "Arial",
    size = ScreenScale(12),
    weight = 800,
    antialias = true,
    outline = true
})

surface.CreateFont("WoundSystemSelfTalkSub", {
    font = "Arial",
    size = ScreenScale(9),
    weight = 700,
    antialias = true,
    outline = true
})

HUD.activePhrase = HUD.activePhrase or ""
HUD.typeStart = HUD.typeStart or 0
HUD.typeSpeed = HUD.typeSpeed or 18
HUD.lastProgress = HUD.lastProgress or -1
HUD.lastSound = HUD.lastSound or 0
HUD.clearTime = HUD.clearTime or 3
HUD.lastPhrase = HUD.lastPhrase or ""
HUD.talkTime = HUD.talkTime or 0
HUD.lastThink = HUD.lastThink or 0
HUD.onFinish = HUD.onFinish or nil
HUD.onInterrupt = HUD.onInterrupt or nil
HUD.finishedCurrent = HUD.finishedCurrent or false

local function WoundSystemClientEnabled()
    local client = WoundSystem and WoundSystem.Client
    if client and client.IsEnabled then
        return client.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

local function TextY()
    local baseY = ScrH() - 200
    if WoundSystemHealthHUDOpen then
        return baseY - 800
    end
    return baseY
end

local function IsHEVStatusLine(text)
    local upper = string.upper(tostring(text or ""))
    return string.find(upper, "%[HAZARDOUS ENVIRONMENT SUIT%]", 1, true) ~= nil
end

local function DrawPhrase(text, progress)
    local visibleText = string.sub(text, 1, progress or #text)
    local y = TextY()

    draw.SimpleTextOutlined(
        visibleText,
        "WoundSystemSelfTalk",
        ScrW() * 0.5,
        y,
        Color(251, 218, 114),
        TEXT_ALIGN_CENTER,
        TEXT_ALIGN_TOP,
        2,
        Color(0, 0, 0, 245)
    )
end

local function ApplyHEVTextDisplay(text, duration)
    duration = tonumber(duration) or 1.2
    if not text or text == "" then
        HUD.hevSubtitle = ""
        return
    end

    HUD.hevSubtitle = "[HAZARDOUS ENVIRONMENT SUIT]"
    HUD.activePhrase = string.upper(text)
    HUD.lastPhrase = HUD.activePhrase
    HUD.typeStart = CurTime()
    HUD.talkTime = 0
    HUD.lastThink = CurTime()
    HUD.lastProgress = -1
    HUD.lastSound = 0
    HUD.finishedCurrent = false
    HUD.typeSpeed = math.Clamp((#HUD.activePhrase) / math.max(duration, 0.3), 8, 35)
end

local function StripWrappingQuotes(text)
    text = string.Trim(tostring(text or ""))
    if #text >= 2 and string.sub(text, 1, 1) == "\"" and string.sub(text, -1) == "\"" then
        return string.sub(text, 2, -2)
    end

    return text
end

local function ConsciousnessScale()
    local state = WoundSystemClientState and WoundSystemClientState.Cardio
    if not state then return 1 end
    if state.unconscious then return 0 end

    return math.Clamp((tonumber(state.consciousness) or 100) * 0.01, 0, 1)
end

local function TalkSound()
    local state = WoundSystemClientState and WoundSystemClientState.Cardio
    if state and (state.impairedSpeech or state.disfigured) then
        return IMPAIRED_TALK_SOUND
    end

    return TALK_SOUND
end

local function CurrentProgress()
    local phrase = HUD.activePhrase or ""
    if phrase == "" then return 0 end

    return math.Clamp(math.floor((HUD.talkTime or 0) * (HUD.typeSpeed or 18)), 0, #phrase)
end

local function ClearCallbacks()
    HUD.onFinish = nil
    HUD.onInterrupt = nil
    HUD.finishedCurrent = false
end

function HUD.Interrupt()
    local phrase = HUD.activePhrase or ""
    if phrase ~= "" and not HUD.finishedCurrent and isfunction(HUD.onInterrupt) then
        HUD.onInterrupt(string.sub(phrase, 1, CurrentProgress()), phrase)
    end

    HUD.activePhrase = ""
    HUD.lastProgress = -1
    ClearCallbacks()
end

function HUD.Finish()
    local phrase = HUD.activePhrase or ""
    if phrase ~= "" and not HUD.finishedCurrent and isfunction(HUD.onFinish) then
        HUD.onFinish(phrase)
    end

    HUD.finishedCurrent = true
end

function HUD.Say(text, callbacks)
    text = StripWrappingQuotes(text)
    if text == "" then return end

    if (HUD.activePhrase or "") ~= "" and not HUD.finishedCurrent then
        HUD.Interrupt()
    end

    HUD.activePhrase = text
    HUD.lastPhrase = text
    HUD.typeStart = CurTime()
    HUD.talkTime = 0
    HUD.lastThink = CurTime()
    HUD.lastProgress = -1
    HUD.lastSound = 0
    HUD.onFinish = callbacks and callbacks.onFinish or nil
    HUD.onInterrupt = callbacks and callbacks.onInterrupt or nil
    HUD.finishedCurrent = false
end

function HUD.SetHEVStatus(label, status, duration)
    return
end

function HUD.Skip()
    HUD.activePhrase = ""
    HUD.lastProgress = -1
    ClearCallbacks()
end

function HUD.Clear()
    HUD.Interrupt()
    HUD.lastPhrase = ""
end

hook.Add("PlayerDeath", "WoundSystem_SelfTalkHUDClearOnDeath", function(ply)
    if ply == LocalPlayer() then
        HUD.Clear()
    end
end)

hook.Add("HUDPaint", "WoundSystem_SelfTalkHUDPaint", function()
    if not WoundSystemClientEnabled() then
        HUD.Clear()
        return
    end

    local ply = LocalPlayer()
    if IsValid(ply) and not ply:Alive() then
        HUD.Clear()
        return
    end

    local phrase = HUD.activePhrase or ""
    if phrase == "" then
        if WoundSystemHealthHUDOpen and (HUD.lastPhrase or "") ~= "" then
            DrawPhrase(HUD.lastPhrase, #HUD.lastPhrase)
        end

        return
    end

    local state = WoundSystemClientState and WoundSystemClientState.Cardio
    if state and state.unconscious then
        HUD.Interrupt()
        return
    end

    local now = CurTime()
    local dt = math.Clamp(now - (HUD.lastThink or now), 0, 0.2)
    HUD.lastThink = now
    HUD.talkTime = (HUD.talkTime or 0) + (dt * ConsciousnessScale())

    local len = #phrase
    local progress = math.Clamp(math.floor((HUD.talkTime or 0) * (HUD.typeSpeed or 18)), 0, len)
    if progress >= len then
        HUD.Finish()
    end

    if progress ~= HUD.lastProgress then
        local char = string.sub(phrase, math.max(progress, 1), math.max(progress, 1))
        if string.match(char, "%w") and CurTime() >= (HUD.lastSound or 0) then
            surface.PlaySound(TalkSound())
            HUD.lastSound = CurTime() + 0.045
        end

        HUD.lastProgress = progress
    end

    if (HUD.talkTime or 0) > (len / math.max(HUD.typeSpeed or 18, 1)) + (HUD.clearTime or 3) then
        HUD.lastPhrase = phrase
        HUD.Skip()
        return
    end

    DrawPhrase(phrase, progress)
end)
