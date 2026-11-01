if WoundSystem and WoundSystem.VoiceProximity and WoundSystem.VoiceProximity._ServerLoaded then
    hook.Remove("PlayerCanHearPlayersVoice", "WoundSystem_VoiceProximity")
end

WoundSystem = WoundSystem or {}
WoundSystem.VoiceProximity = WoundSystem.VoiceProximity or {}
WoundSystem.VoiceProximity._ServerLoaded = true

local cvEnabled = GetConVar("woundsys_voice_proximity_enabled")
local cvFar = GetConVar("woundsys_voice_proximity_far")
local cvDeadTalk = GetConVar("woundsys_voice_proximity_dead_talk")
local cvUnconsciousTalk = GetConVar("woundsys_voice_proximity_unconscious_talk")
local cvTeamBypass = GetConVar("woundsys_voice_proximity_team_bypass")

local function WoundSystemHealthEnabled()
    local config = WoundSystem and WoundSystem.Health and WoundSystem.Health.Config
    if config and config.IsEnabled then
        return config.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

local function CVarBool(cvar, fallback)
    if not cvar then return fallback end
    return cvar:GetBool()
end

local function CVarFloat(cvar, fallback)
    if not cvar then return fallback end
    return cvar:GetFloat()
end

local function IsAssignedPlayerTeam(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false end

    local plyTeam = ply:Team()
    if plyTeam == TEAM_UNASSIGNED or plyTeam == TEAM_SPECTATOR or plyTeam == TEAM_CONNECTING then return false end

    return true
end

local function SameAssignedTeam(listener, talker)
    return IsAssignedPlayerTeam(listener) and IsAssignedPlayerTeam(talker) and listener:Team() == talker:Team()
end

local function IsTalkerUnconscious(talker)
    if not IsValid(talker) then return false end
    if talker:GetNWBool("WoundSystemUnconscious", false) then return true end

    return IsValid(talker:GetNWEntity("WoundSystemUnconsciousRagdoll"))
end

local function ShouldBlockTalker(talker)
    if not IsValid(talker) or not talker:IsPlayer() then return true end

    if not CVarBool(cvDeadTalk, false) and not talker:Alive() then return true end
    if not CVarBool(cvUnconsciousTalk, false) and IsTalkerUnconscious(talker) then return true end

    return false
end

hook.Add("PlayerCanHearPlayersVoice", "WoundSystem_VoiceProximity", function(listener, talker)
    if not WoundSystemHealthEnabled() then return end
    if not CVarBool(cvEnabled, true) then return end
    if not IsValid(listener) or not listener:IsPlayer() or not IsValid(talker) or not talker:IsPlayer() then return false, false end
    if listener == talker then return true, true end
    if ShouldBlockTalker(talker) then return false, false end

    if CVarBool(cvTeamBypass, false) and SameAssignedTeam(listener, talker) then
        return true, true
    end

    local far = math.max(CVarFloat(cvFar, 1800), 0)
    if far <= 0 then return false, false end

    if listener:GetPos():DistToSqr(talker:GetPos()) > far * far then
        return false, false
    end

    return true, true
end)
