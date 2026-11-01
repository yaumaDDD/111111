WoundSystem = WoundSystem or {}
WoundSystem.Health = WoundSystem.Health or {}

local FALL_IMPACT_RECORD_WINDOW = 0.75
local FALL_FORCE_SPEED_OFFSET = 420
local FALL_FORCE_SPEED_DIVISOR = 60

local function WoundSystemHealthEnabled()
    local config = WoundSystem and WoundSystem.Health and WoundSystem.Health.Config
    if config and config.IsEnabled then
        return config.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

function WoundSystem.Health.FallSpeedToImpactForce(speed)
    return math.max(((tonumber(speed) or 0) - FALL_FORCE_SPEED_OFFSET) / FALL_FORCE_SPEED_DIVISOR, 0)
end

function WoundSystem.Health.GetRecentFallSpeed(ply, dmg)
    local now = CurTime()
    local speed = 0

    if (ply._woundSystemLastFallSpeedTime or 0) + FALL_IMPACT_RECORD_WINDOW >= now then
        speed = math.max(speed, tonumber(ply._woundSystemLastFallSpeed) or 0)
    end

    if (ply.woundsys_FallSpeedClearAt or 0) >= now then
        speed = math.max(speed, tonumber(ply.woundsys_MaxFallSpeed) or 0)
    end

    if (tonumber(dmg) or 0) > 0 then
        speed = math.max(speed, (tonumber(dmg) or 0) * 3.96 + 526.5)
    end

    return speed
end

hook.Add("OnPlayerHitGround", "WoundSystem_RecordFallImpactSpeed", function(ply, inWater, onFloater, speed)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:IsPlayer() then return end

    ply._woundSystemLastFallSpeed = inWater and 0 or math.max(tonumber(speed) or 0, tonumber(ply.woundsys_MaxFallSpeed) or 0)
    ply._woundSystemLastFallSpeedTime = CurTime()
    ply._woundSystemLastFallOnFloater = onFloater and true or false
end)
