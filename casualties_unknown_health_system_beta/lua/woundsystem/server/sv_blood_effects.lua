if WoundSystem and WoundSystem.ServerBloodEffects and WoundSystem.ServerBloodEffects._Loaded then
    timer.Remove("WoundSystem_BloodEffectTrails")
end

WoundSystem = WoundSystem or {}
WoundSystem.ServerBloodEffects = WoundSystem.ServerBloodEffects or {}
WoundSystem.ServerBloodEffects._Loaded = true
WoundSystem.BloodEffects = WoundSystem.BloodEffects or {}

local function WoundSystemHealthEnabled()
    local config = WoundSystem and WoundSystem.Health and WoundSystem.Health.Config
    if config and config.IsEnabled then
        return config.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

local TRAIL_INTERVAL = 0.1
local NEXT_TRAIL = {}
local GROUND_TRACE_DISTANCE = 4096
local GROUND_TRACE_UP = Vector(0, 0, 24)
local GROUND_TRACE_DOWN = Vector(0, 0, GROUND_TRACE_DISTANCE)
local BLOOD_SOURCE_OFFSET = Vector(0, 0, -6)
local DEFAULT_BLOOD_NORMAL = Vector(0, 0, 1)
local ZERO_VECTOR = Vector(0, 0, 0)
local FALLBACK_BLEED_SOURCE_BONES = {"ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Head1"}
local groundTrace = {
    mask = MASK_SOLID_BRUSHONLY
}
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

local function EmitBloodEffectUnchecked(pos, normal, severity, kind, recipients, attachedEnt, limbId)
    if not pos then return end

    normal = normal or DEFAULT_BLOOD_NORMAL
    severity = math.Clamp(tonumber(severity) or 1, 0.1, 3)
    kind = tostring(kind or "impact")
    attachedEnt = IsValid(attachedEnt) and attachedEnt or NULL
    limbId = tostring(limbId or "")

    net.Start("WoundSystem_BloodEffect")
        net.WriteVector(pos)
        net.WriteNormal(normal)
        net.WriteFloat(severity)
        net.WriteString(kind)
        net.WriteEntity(attachedEnt)
        net.WriteString(limbId)

    if recipients then
        net.Send(recipients)
    else
        net.Broadcast()
    end
end

local function EmitBloodEffect(pos, normal, severity, kind, recipients, attachedEnt, limbId)
    if not WoundSystemHealthEnabled() then return end
    EmitBloodEffectUnchecked(pos, normal, severity, kind, recipients, attachedEnt, limbId)
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
        local current = WoundSystem.GetCurrentCharacter(ply)
        if IsValid(current) then return current end
    end

    return ply
end

local function CachedLookupBone(ent, cache, boneName)
    local cached = cache.bones[boneName]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end

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

    local total = 0
    local worstLimb
    local worstBleed = 0

    for limbId, state in pairs(limbs) do
        if state and not state.dismembered and not state.blockedBleeding then
            local bleed = math.max(state.bleed or 0, 0)
            total = total + bleed
            if bleed > worstBleed then
                worstBleed = bleed
                worstLimb = limbId
            end
        end
    end

    return total, worstLimb, worstBleed
end

timer.Create("WoundSystem_BloodEffectTrails", TRAIL_INTERVAL, 0, function()
    if not WoundSystemHealthEnabled() then
        table.Empty(NEXT_TRAIL)
        return
    end

    local now = CurTime()

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then
            NEXT_TRAIL[ply] = nil
            continue
        end

        local bleed, limbId = GetPlayerBleedInfo(ply)
        if bleed <= 3 then continue end

        local delay = math.Clamp(1.0 - bleed / 100, 0.1, 1.2)
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
            if out:LengthSqr() > 0.001 then
                flowNormal = out:GetNormalized()
            end
        end

        EmitBloodEffectUnchecked(sourcePos + BLOOD_SOURCE_OFFSET, dropDir, severity * 0.75, "bleeddrop")
        EmitBloodEffectUnchecked(sourcePos, flowNormal, severity * 0.55, "bodyflow", nil, sourceEnt, limbId)

        if foundGround then
            if severity > 0.75 then
                EmitBloodEffectUnchecked(groundPos, groundNormal, severity * 0.35, "trail")
            end
        end
    end
end)

function WoundSystem.BloodEffects.Emit(pos, normal, severity, kind, recipients, attachedEnt, limbId)
    EmitBloodEffect(pos, normal, severity, kind, recipients, attachedEnt, limbId)
end

function WoundSystem.BloodEffects.EmitGround(pos, severity, kind, ignore, recipients)
    local groundPos, groundNormal, foundGround = FindGround(pos, ignore)
    if foundGround then
        EmitBloodEffect(groundPos, groundNormal, severity, kind, recipients)
        if kind == "pool" or kind == "trail" or kind == "dismember" or kind == "stain" then
            hook.Run("WoundSystem_OnBloodPool", groundPos, ignore)
        end
    end
end
