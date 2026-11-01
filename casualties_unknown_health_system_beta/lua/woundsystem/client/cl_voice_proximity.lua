if WoundSystem and WoundSystem.VoiceProximity and WoundSystem.VoiceProximity.ResetAllScales then
    WoundSystem.VoiceProximity.ResetAllScales()
end

if WoundSystem and WoundSystem.VoiceProximity and WoundSystem.VoiceProximity._ClientLoaded then
    hook.Remove("PlayerStartVoice", "WoundSystem_VoiceProximityStart")
    hook.Remove("PlayerEndVoice", "WoundSystem_VoiceProximityEnd")
    hook.Remove("Think", "WoundSystem_VoiceProximityThink")
    hook.Remove("EntityRemoved", "WoundSystem_VoiceProximityEntityRemoved")
    hook.Remove("PlayerDisconnected", "WoundSystem_VoiceProximityDisconnect")
    hook.Remove("ShutDown", "WoundSystem_VoiceProximityShutdown")
end

WoundSystem = WoundSystem or {}
WoundSystem.VoiceProximity = WoundSystem.VoiceProximity or {}
WoundSystem.VoiceProximity._ClientLoaded = true

local VoiceProximity = WoundSystem.VoiceProximity
local ActiveTalkers = {}
local ScaledTalkers = {}
local WallCache = {}
local CVarCache = {}

local UPDATE_INTERVAL = 0.1
local nextUpdate = 0

local traceFilter = {}
local traceData = {
    filter = traceFilter,
    mask = MASK_SOLID_BRUSHONLY or MASK_SOLID
}

local function GetCachedCVar(name)
    local cvar = CVarCache[name]
    if cvar then return cvar end

    cvar = GetConVar(name)
    if cvar then CVarCache[name] = cvar end

    return cvar
end

local function CVarBool(name, fallback)
    local cvar = GetCachedCVar(name)
    if not cvar then return fallback end

    return cvar:GetBool()
end

local function CVarFloat(name, fallback)
    local cvar = GetCachedCVar(name)
    if not cvar then return fallback end

    return cvar:GetFloat()
end

local function WoundSystemClientEnabled()
    local client = WoundSystem and WoundSystem.Client
    if client and client.IsEnabled then
        return client.IsEnabled()
    end

    return CVarBool("woundsys_enabled", true)
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

local function ResetScale(talker)
    if IsValid(talker) and talker.SetVoiceVolumeScale then
        talker:SetVoiceVolumeScale(1)
    end

    ScaledTalkers[talker] = nil
    WallCache[talker] = nil
end

function VoiceProximity.ResetAllScales()
    for talker in pairs(ScaledTalkers) do
        ResetScale(talker)
    end
end

local function SetScale(talker, scale)
    if not IsValid(talker) or not talker.SetVoiceVolumeScale then return end

    scale = math.Clamp(tonumber(scale) or 1, 0, 1)

    if scale >= 0.995 then
        ResetScale(talker)
        return
    end

    local previous = ScaledTalkers[talker]
    if previous ~= nil and math.abs(previous - scale) <= 0.01 then return end

    talker:SetVoiceVolumeScale(scale)
    ScaledTalkers[talker] = scale
end

local function IsBlockedByWorld(listener, talker, now)
    local interval = math.max(CVarFloat("woundsys_voice_proximity_wall_check_interval", 0.35), 0)
    if interval <= 0 then return false end

    local cached = WallCache[talker]
    if cached and cached.nextCheck > now then
        return cached.blocked == true
    end

    traceFilter[1] = listener
    traceFilter[2] = talker
    traceData.start = listener:EyePos()
    traceData.endpos = talker:EyePos()

    local tr = util.TraceLine(traceData)
    cached = cached or {}
    cached.nextCheck = now + interval
    cached.blocked = tr.HitWorld == true
    WallCache[talker] = cached

    return cached.blocked
end

local function ComputeDistanceScale(listener, talker, now)
    if CVarBool("woundsys_voice_proximity_team_bypass", false) and SameAssignedTeam(listener, talker) then
        return 1
    end

    local near = math.max(CVarFloat("woundsys_voice_proximity_near", 350), 0)
    local far = math.max(CVarFloat("woundsys_voice_proximity_far", 1800), 1)
    local minVolume = math.Clamp(CVarFloat("woundsys_voice_proximity_min_volume", 0.08), 0, 1)
    local scale = 1

    if far <= near then
        scale = listener:GetPos():DistToSqr(talker:GetPos()) <= far * far and 1 or minVolume
    else
        local distSqr = listener:GetPos():DistToSqr(talker:GetPos())
        if distSqr > near * near then
            local distance = math.sqrt(distSqr)
            local t = math.Clamp((distance - near) / (far - near), 0, 1)
            local power = math.max(CVarFloat("woundsys_voice_proximity_power", 1.15), 0.25)
            scale = minVolume + (1 - minVolume) * (1 - math.pow(t, power))
        end
    end

    if IsBlockedByWorld(listener, talker, now) then
        scale = math.max(minVolume, scale * math.Clamp(CVarFloat("woundsys_voice_proximity_wall_muffle", 0.35), 0, 1))
    end

    return scale
end

local function ProcessTalkers()
    local now = CurTime()
    if now < nextUpdate then return end

    nextUpdate = now + UPDATE_INTERVAL

    if not WoundSystemClientEnabled() then
        VoiceProximity.ResetAllScales()
        return
    end

    if not CVarBool("woundsys_voice_proximity_enabled", true) then
        VoiceProximity.ResetAllScales()
        return
    end

    local listener = LocalPlayer()
    if not IsValid(listener) then return end

    for talker in pairs(ActiveTalkers) do
        if not IsValid(talker) or not talker:IsPlayer() or talker == listener then
            ActiveTalkers[talker] = nil
            ResetScale(talker)
        else
            SetScale(talker, ComputeDistanceScale(listener, talker, now))
        end
    end
end

hook.Add("PlayerStartVoice", "WoundSystem_VoiceProximityStart", function(talker)
    if not IsValid(talker) or not talker:IsPlayer() or talker == LocalPlayer() then return end

    ActiveTalkers[talker] = true
end)

hook.Add("PlayerEndVoice", "WoundSystem_VoiceProximityEnd", function(talker)
    ActiveTalkers[talker] = nil
    ResetScale(talker)
end)

hook.Add("EntityRemoved", "WoundSystem_VoiceProximityEntityRemoved", function(ent)
    ActiveTalkers[ent] = nil
    ResetScale(ent)
end)

hook.Add("PlayerDisconnected", "WoundSystem_VoiceProximityDisconnect", function(ply)
    ActiveTalkers[ply] = nil
    ResetScale(ply)
end)

hook.Add("Think", "WoundSystem_VoiceProximityThink", ProcessTalkers)
hook.Add("ShutDown", "WoundSystem_VoiceProximityShutdown", VoiceProximity.ResetAllScales)
