-- C:U BLOOD -> Z-CITY BRIDGE
-- Original C:U decorative stains/pools/trails/bodyflow removed per request and replaced with Z-City blood (hg_bloodimpact + decals).
-- Keeps WoundSystem.BloodEffects API so sv_health call sites remain valid.
WoundSystem = WoundSystem or {}
WoundSystem.BloodEffects = WoundSystem.BloodEffects or {}
WoundSystem.ServerBloodEffects = WoundSystem.ServerBloodEffects or {}
WoundSystem.ServerBloodEffects._Loaded = true

pcall(function() timer.Remove("WoundSystem_BloodEffectTrails") end)

local function WoundSystemHealthEnabled()
    local cfg = WoundSystem and WoundSystem.Health and WoundSystem.Health.Config
    if cfg and cfg.IsEnabled then return cfg.IsEnabled() end
    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

-- copied from original for periodic bleed logic
local TRAIL_INTERVAL = 0.12
local NEXT_TRAIL = {}
local GROUND_TRACE_DISTANCE = 4096
local GROUND_TRACE_UP = Vector(0, 0, 24)
local GROUND_TRACE_DOWN = Vector(0, 0, GROUND_TRACE_DISTANCE)
local DEFAULT_BLOOD_NORMAL = Vector(0, 0, 1)
local ZERO_VECTOR = Vector(0, 0, 0)
local FALLBACK_BLEED_SOURCE_BONES = {"ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Head1"}
local groundTrace = { mask = MASK_SOLID_BRUSHONLY }
local BLEED_SOURCE_BONES = {
    head = {"ValveBiped.Bip01_Head1"},
    thorax = {"ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine1"},
    abdomen = {"ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Pelvis"},
    arm_L = {"ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Forearm"},
    forearm_L = {"ValveBiped.Bip01_L_Forearm"},
    hand_L = {"ValveBiped.Bip01_L_Hand"},
    arm_R = {"ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Forearm"},
    forearm_R = {"ValveBiped.Bip01_R_Forearm"},
    hand_R = {"ValveBiped.Bip01_R_Hand"},
    thigh_L = {"ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_L_Calf"},
    crus_L = {"ValveBiped.Bip01_L_Calf"},
    foot_L = {"ValveBiped.Bip01_L_Foot"},
    thigh_R = {"ValveBiped.Bip01_R_Thigh", "ValveBiped.Bip01_R_Calf"},
    crus_R = {"ValveBiped.Bip01_R_Calf"},
    foot_R = {"ValveBiped.Bip01_R_Foot"}
}

-- Z-City helpers
local function ZCity_BloodImpact(pos, dir, severity, recipients)
    if not pos then return end
    if not WoundSystemHealthEnabled() then return end
    severity = math.Clamp(tonumber(severity) or 1, 0.1, 3)
    dir = dir or DEFAULT_BLOOD_NORMAL
    -- map severity to particle amount (Z-City does impact(pos, vel, mul) with amt loop)
    local amt = math.Clamp(math.floor(severity * 2.2 + 1), 1, 10)
    -- Z-City net expects pos, vel(normalized * something), mul(damage), amt
    -- sv_input.lua sends dir/2 and dmg; client multiplies vel by 500
    net.Start("hg_bloodimpact")
        net.WriteVector(pos)
        net.WriteVector(dir:GetNormalized() * 0.5)
        net.WriteFloat(severity * 2.0)
        net.WriteInt(amt, 8)
    if recipients then net.Send(recipients) else net.Broadcast() end
end

local function ZCity_Decal(pos, normal, severity)
    if not pos or not normal then return end
    -- primary Z-City decals: Normal.Blood21-25 / Arterial.Blood21-25
    -- pick arterial for heavy bleed
    local heavy = (severity or 1) > 1.4
    local decal = heavy and ("Arterial.Blood2" .. math.random(1,5)) or ("Normal.Blood2" .. math.random(1,5))
    -- do both: Z-City custom + fallback vanilla for visibility
    pcall(function() util.Decal(decal, pos + normal * 2, pos - normal * 2) end)
    pcall(function() util.Decal("Blood", pos + normal, pos - normal) end)
end

local function FindGround(pos, ignore)
    groundTrace.start = pos + GROUND_TRACE_UP
    groundTrace.endpos = pos - GROUND_TRACE_DOWN
    groundTrace.filter = ignore
    local tr = util.TraceLine(groundTrace)
    if tr.Hit and tr.HitWorld and not tr.HitSky then
        return tr.HitPos, tr.HitNormal, true
    end
    return nil, nil, false
end

local function GetBleedSourceEntity(ply)
    if WoundSystem.GetCurrentCharacter then
        local cur = WoundSystem.GetCurrentCharacter(ply)
        if IsValid(cur) then return cur end
    end
    return ply
end

local function CachedLookupBone(ent, cache, boneName)
    local cached = cache.bones[boneName]
    if cached ~= nil then return cached ~= false and cached or nil end
    local bone = ent:LookupBone(boneName)
    cache.bones[boneName] = bone or false
    return bone
end

local function GetBleedSourcePos(ent, limbId)
    if not IsValid(ent) then return nil end
    if ent.LookupBone and ent.GetBonePosition then
        local model = ent:GetModel() or ""
        local cache = ent.WoundSystemBleedBoneCache
        if not cache or cache.model ~= model then
            cache = {model = model, bones = {}}
            ent.WoundSystemBleedBoneCache = cache
        end
        local preferred = BLEED_SOURCE_BONES[limbId or ""]
        if preferred then
            for _, boneName in ipairs(preferred) do
                local bone = CachedLookupBone(ent, cache, boneName)
                if bone then
                    local pos = ent:GetBonePosition(bone)
                    if pos then return pos end
                end
            end
        end
        for _, boneName in ipairs(FALLBACK_BLEED_SOURCE_BONES) do
            local bone = CachedLookupBone(ent, cache, boneName)
            if bone then
                local pos = ent:GetBonePosition(bone)
                if pos then return pos end
            end
        end
    end
    return ent.WorldSpaceCenter and ent:WorldSpaceCenter() or ent:GetPos()
end

local function GetPlayerBleedInfo(ply)
    local health = WoundSystem.Health
    local getLimbs = health and health.GetLimbs
    if not getLimbs then return 0 end
    local limbs = getLimbs(ply)
    if not limbs then return 0 end
    local total, worstLimb, worstBleed = 0, nil, 0
    for limbId, state in pairs(limbs) do
        if state and not state.dismembered and not state.blockedBleeding then
            local bleed = math.max(state.bleed or 0, 0)
            total = total + bleed
            if bleed > worstBleed then worstBleed = bleed; worstLimb = limbId end
        end
    end
    return total, worstLimb, worstBleed
end

-- Public API: translate C:U Emit -> Z-City
function WoundSystem.BloodEffects.Emit(pos, normal, severity, kind, recipients, attachedEnt, limbId)
    if not WoundSystemHealthEnabled() then return end
    if not pos then return end
    normal = normal or DEFAULT_BLOOD_NORMAL
    severity = math.Clamp(tonumber(severity) or 1, 0.1, 3)
    kind = tostring(kind or "impact")

    -- map C:U kinds to Z-City intensity
    if kind == "impact" or kind == "dismember" then
        ZCity_BloodImpact(pos, normal, severity * 1.0, recipients)
        ZCity_Decal(pos, normal, severity)
    elseif kind == "vomitblood" or kind == "vomit" then
        -- vomit: slightly heavier, downward
        ZCity_BloodImpact(pos, normal, severity * 0.9, recipients)
        ZCity_Decal(pos, normal, severity)
        -- also try Z-City vomit squirt for juice (bloodsquirt2) if we have a valid ent/bone
        if IsValid(attachedEnt) and attachedEnt.LookupBone then
            local headBone = attachedEnt:LookupBone("ValveBiped.Bip01_Head1")
            if headBone then
                local mat = attachedEnt:GetBoneMatrix(headBone)
                if mat then
                    net.Start("bloodsquirt2")
                        net.WriteEntity(attachedEnt)
                        net.WriteString("ValveBiped.Bip01_Head1")
                        net.WriteMatrix(mat)
                        net.WriteVector(pos)
                        net.WriteVector(normal * 2 * math.Clamp(severity, 0.4, 1.5))
                    if recipients then net.Send(recipients) else net.Broadcast() end
                end
            end
        end
    elseif kind == "bodyflow" or kind == "bleeddrop" then
        ZCity_BloodImpact(pos, normal, severity * 0.7, recipients)
    elseif kind == "trail" or kind == "stain" or kind == "pool" then
        ZCity_BloodImpact(pos, normal, severity * 0.6, recipients)
        ZCity_Decal(pos, normal, severity * 0.5)
    else
        ZCity_BloodImpact(pos, normal, severity, recipients)
    end
end

function WoundSystem.BloodEffects.EmitGround(pos, severity, kind, ignore, recipients)
    if not WoundSystemHealthEnabled() then return end
    local groundPos, groundNormal, foundGround = FindGround(pos, ignore)
    if foundGround then
        ZCity_BloodImpact(groundPos, groundNormal, (severity or 1) * 1.0, recipients)
        ZCity_Decal(groundPos, groundNormal, severity)
        if kind == "pool" or kind == "trail" or kind == "dismember" or kind == "stain" then
            hook.Run("WoundSystem_OnBloodPool", groundPos, ignore)
        end
    end
end

-- Periodic bleeding -> Z-City droplets (replaces old WoundSystem_BloodEffectTrails)
timer.Create("WoundSystem_BloodEffectTrails", TRAIL_INTERVAL, 0, function()
    if not WoundSystemHealthEnabled() then table.Empty(NEXT_TRAIL); return end
    local now = CurTime()
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then NEXT_TRAIL[ply] = nil; continue end
        local bleed, limbId = GetPlayerBleedInfo(ply)
        if bleed <= 3 then continue end
        local delay = math.Clamp(1.0 - bleed / 100, 0.12, 1.4)
        if (NEXT_TRAIL[ply] or 0) > now then continue end
        NEXT_TRAIL[ply] = now + delay

        local sourceEnt = GetBleedSourceEntity(ply)
        local sourcePos = GetBleedSourcePos(sourceEnt, limbId) or ply:GetPos()
        local groundPos, groundNormal, foundGround = FindGround(sourcePos, sourceEnt)
        local severity = math.Clamp(bleed / 45, 0.45, 2.2)

        local dropDir = IsValid(sourceEnt) and sourceEnt:GetVelocity() or ZERO_VECTOR
        if dropDir:LengthSqr() < 25 then
            dropDir = IsValid(sourceEnt) and sourceEnt:GetForward() or VectorRand()
        end
        dropDir = dropDir:GetNormalized()

        local flowNormal = dropDir
        if IsValid(sourceEnt) then
            local center = sourceEnt.WorldSpaceCenter and sourceEnt:WorldSpaceCenter() or sourceEnt:GetPos()
            local out = sourcePos - center
            if out:LengthSqr() > 0.001 then flowNormal = out:GetNormalized() end
        end

        -- Z-City droplet + bodyflow
        ZCity_BloodImpact(sourcePos + Vector(0,0,-6), dropDir, severity * 0.55)
        -- slight second puff for bodyflow
        ZCity_BloodImpact(sourcePos, flowNormal, severity * 0.4)

        if foundGround and severity > 0.75 then
            ZCity_BloodImpact(groundPos, groundNormal, severity * 0.35)
            ZCity_Decal(groundPos, groundNormal, severity * 0.35)
        end
    end
end)
