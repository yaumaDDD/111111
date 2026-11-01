function WoundSystemHealthEnabled()
    local config = WoundSystem and WoundSystem.Health and WoundSystem.Health.Config
    if config and config.IsEnabled then
        return config.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

-- Z-City integration: returns hg.WoundBridge when WoundSystem is the health back-end of Z-City.
-- In that mode Z-City owns the physical ragdoll (hg.Fake / hg.FakeUp) and WoundSystem only
-- decides *when* the body goes down / gets up.
function WoundSystemBridgeActive()
    local WB = hg and hg.WoundBridge
    if WB and WB.IsEnabled and WB.IsEnabled() then return WB end
    return nil
end

local function WoundSystem_RemoveVanillaDeathRagdollFor(ply)
    if not IsValid(ply) then return end

    local preserved = ply:GetNWEntity("WoundSystemUnconsciousRagdoll")
    if not IsValid(preserved) then return end

    local function removeDuplicate(ragdoll)
        if not IsValid(ragdoll) or ragdoll == preserved then return end
        if ragdoll:GetNWBool("WoundSystemUnconsciousRagdoll", false) or ragdoll:GetNWBool("WoundSystemDeadUnconsciousBody", false) then return end

        local class = ragdoll:GetClass()
        local sameModel = string.lower(ragdoll:GetModel() or "") == string.lower(preserved:GetModel() or ply:GetModel() or "")
        local isVanilla = class == "hl2mp_ragdoll"
        local nearPreserved = ragdoll:WorldSpaceCenter():DistToSqr(preserved:WorldSpaceCenter()) <= (420 * 420)
        local nearPlayer = ragdoll:WorldSpaceCenter():DistToSqr(ply:WorldSpaceCenter()) <= (420 * 420)

        if (isVanilla or sameModel) and (nearPreserved or nearPlayer) then
            SafeRemoveEntityDelayed(ragdoll, 0)
        end
    end

    if ply.GetRagdollEntity then
        removeDuplicate(ply:GetRagdollEntity())
    end

    for _, ragdoll in ipairs(ents.FindByClass("hl2mp_ragdoll")) do
        removeDuplicate(ragdoll)
    end

    for _, ragdoll in ipairs(ents.FindByClass("prop_ragdoll")) do
        removeDuplicate(ragdoll)
    end
end

hook.Add("CreateEntityRagdoll", "WoundSystem_SuppressVanillaDeathRagdoll", function(owner, ragdoll)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(owner) or not owner:IsPlayer() or not IsValid(owner:GetNWEntity("WoundSystemUnconsciousRagdoll")) then return end

    if IsValid(ragdoll) then
        SafeRemoveEntityDelayed(ragdoll, 0)
    end

    timer.Simple(0, function()
        WoundSystem_RemoveVanillaDeathRagdollFor(owner)
    end)
end)

hook.Add("PlayerDeath", "WoundSystem_SuppressVanillaDeathRagdoll", function(victim)
    if not WoundSystemHealthEnabled() then return end

    for i = 0, 12 do
        timer.Simple(i * 0.1, function()
            WoundSystem_RemoveVanillaDeathRagdollFor(victim)
        end)
    end
end)

if WoundSystem and WoundSystem.Health and WoundSystem.Health._Loaded then return end

WoundSystem = WoundSystem or {}
WoundSystem.Health = WoundSystem.Health or {}
WoundSystem.Health._Loaded = true

if WoundSystem.PoolNetStrings then
    WoundSystem.PoolNetStrings()
end

local Const = {}
local Fn = {}
local PlayerLimbs
local BodyState
local GetBody
local GetInventory

function Fn.IntBleedingClamped(internalBleeding)
    return math.Clamp(internalBleeding or 0, 0, 25)
end

Const.StrokeAffectedLimbs = {
    arm_L = true,
    forearm_L = true,
    hand_L = true
}

WoundSystem.Health.LimbForce.LegLimbs = {
    R = {"thigh_R", "crus_R", "foot_R"},
    L = {"thigh_L", "crus_L", "foot_L"}
}

WoundSystem.Health.LimbForce.ArmLimbs = {
    R = {"arm_R", "forearm_R", "hand_R"},
    L = {"arm_L", "forearm_L", "hand_L"}
}

WoundSystem.Health.LimbForce.CoreLimbs = {"thorax", "abdomen"}

function Fn.ClearLimbBandage(state)
    if not state then return end
    state.isBandaged = false
    state.blockedBleeding = false
    state.bandageSlowAmount = 0
end

function Fn.AddHearingLoss(body, amount)
    if not body or amount <= 0 then return end
    if WoundSystem.Health and WoundSystem.Health.Config and WoundSystem.Health.Config.CVars and WoundSystem.Health.Config.CVars.GunshotHearingEnabled and not WoundSystem.Health.Config.CVars.GunshotHearingEnabled:GetBool() then
        return
    end
    body.hearingLoss = math.Clamp((body.hearingLoss or 0) + amount, 0, 100)
end

function Fn.LimbIsInfected(state)
    return (state.infection or 0) > 0 or (state.infectionSpeed or 0) > 0
end

function WoundSystem.Health.LimbForce.IsStructurallyDisabled(state)
    return state and (state.broken or state.dislocated or state.splinted or state.dismembered)
end

function WoundSystem.Health.LimbForce.ComputeTotalForce(state, body, limbName)
    if not state or state.dismembered then return 0 end
    if not WoundSystem.Health.LimbForce.EnabledCVar:GetBool() then
        return math.Clamp((state.muscle or 100) / 100, 0, 1)
    end

    local structuralIntegrity = WoundSystem.Health.LimbForce.IsStructurallyDisabled(state) and 0 or 1
    local pain = math.max(state.pain or 0, (body.avgPain or 0) * 0.9)
    local adrenaline = (body.curAdrenaline or body.adrenaline or 0) * 0.5
    local painFactor = math.Clamp(1 - ((pain - adrenaline) * 0.007), 0, 1)
    local oxygenFactor = math.Clamp((body.bloodOxygen or 100) / 100, 0, 1)
    local strokeFactor = 1

    if Const.StrokeAffectedLimbs[limbName] and (body.strokeAmount or 0) > 0 then
        strokeFactor = math.Clamp(1 - ((body.strokeAmount or 0) / 50), 0, 1)
    end

    local shockFactor = 1
    if (state.shockStrengthLoss or 0) > 0 then
        shockFactor = math.Clamp(1 - (state.shockStrengthLoss or 0), 0, 1)
    end

    return math.Clamp(((state.muscle or 0) / 100) * structuralIntegrity * painFactor * oxygenFactor * strokeFactor * shockFactor, 0, 1)
end

function WoundSystem.Health.LimbForce.RecomputeAll(limbs, body)
    if not limbs or not body then return end

    for limbName, state in pairs(limbs) do
        state.muscleStrength = WoundSystem.Health.LimbForce.ComputeTotalForce(state, body, limbName)
    end
end

function Fn.ViscosityOxygenCap(viscosity)
    local v = math.max(0, math.min(math.abs(viscosity or 0), 40))
    return 100 - v * 0.4
end

function WoundSystem.Health.Circulation.ThirstBloodPressure(thirst)
    thirst = tonumber(thirst) or 100

    if thirst < 0 then
        return math.Clamp(0.7 + ((thirst + 50) / 50) * 0.22, 0.65, 0.92)
    end

    if thirst < 40 then
        return Lerp(math.Clamp(thirst / 40, 0, 1), 0.92, 1)
    end

    if thirst > 175 then
        return math.Clamp(1 + ((thirst - 175) / 75) * 0.12, 1, 1.12)
    end

    return 1
end

function WoundSystem.Health.Circulation.ReferencePressure(body, actualOpiateReception, tempDiff)
    if not body then return 120 end

    local refPressure = 120
    refPressure = refPressure - (100 - (body.bloodVolume or 100)) / 4
    refPressure = refPressure + (100 - (body.stamina or 100)) * 0.2
    refPressure = refPressure + ((body.curAdrenaline or 0) * 0.2)
    refPressure = refPressure - ((body.septicShock or 0) * 0.4)
    refPressure = refPressure + ((tempDiff or 0) * 2)
    refPressure = refPressure + ((body.weightOffset or 0) * 0.333)

    if (body.thirst or 100) < 0 then
        refPressure = refPressure + (body.thirst or 100)
    end

    if (body.hunger or 100) < 40 then
        refPressure = refPressure + ((body.hunger or 100) - 40) * 0.25
    end

    if (body.bloodPressureChangeFromMedicine or 0) > 0 then
        refPressure = refPressure * 0.75
    elseif (body.bloodPressureChangeFromMedicine or 0) < 0 then
        refPressure = refPressure * 1.25
    end

    return refPressure - ((actualOpiateReception or 0) * 0.4)
end

local function HandleRadiationSicknessTick(ply, body, limbs, dt)
    local rad = body.radiationSickness or 0
    if rad <= 0 then
        body.radiationSickness = 0
        return
    end

    if (body.sicknessAmount or 0) < rad * 0.4 then
        local gain = math.min(0.45 * dt, math.max(0, rad - (body.sicknessAmount or 0)))
        body.sicknessAmount = (body.sicknessAmount or 0) + gain
    end

    body.brainHealth = math.Clamp((body.brainHealth or 100) - (dt * rad * 0.0003), 0, 100)

    if rad > 10 then
        body.bloodVolume = math.max(-100, (body.bloodVolume or 100) - (dt * rad * 0.00025))
        body.thirst = math.Clamp((body.thirst or 100) - (dt * rad * 0.0002), -50, 250)
    end

    if rad > 30 then
        for _, state in pairs(limbs) do
            local skinCap = 100 - rad * 0.5
            if (state.skin or 100) > skinCap then
                state.skin = math.max(0, (state.skin or 100) - (0.2 * dt))
            end
        end
    end

    for _, state in pairs(limbs) do
        local muscleCap = 100 - rad * 0.5
        if (state.muscle or 100) > muscleCap then
            state.muscle = math.max(0, (state.muscle or 100) - (0.2 * dt))
        end
        local painFloor = rad * 0.3
        if (state.pain or 0) < painFloor then
            state.pain = math.min(100, (state.pain or 0) + (2 * dt))
        end
    end

    body.radiationSickness = math.max(0, rad - (0.033 * dt))
end

Const.HitgroupToLimb = {
    [HITGROUP_HEAD]      = "head",
    [HITGROUP_CHEST]     = "thorax",
    [HITGROUP_STOMACH]   = "abdomen",
    [HITGROUP_LEFTARM]   = "forearm_L",
    [HITGROUP_RIGHTARM]  = "forearm_R",
    [HITGROUP_LEFTLEG]   = "crus_L",
    [HITGROUP_RIGHTLEG]  = "crus_R",
    [HITGROUP_GEAR]      = "abdomen", 
    [HITGROUP_GENERIC]   = "thorax"   
}

Const.RandomDamageLimbs = {
    "thorax", "abdomen", "head",
    "arm_R", "forearm_R", "hand_R",
    "arm_L", "forearm_L", "hand_L",
    "thigh_R", "crus_R", "foot_R",
    "thigh_L", "crus_L", "foot_L"
}

Const.RandomDamageWeights = {
    thorax = 16,
    abdomen = 12,
    head = 5,
    arm_R = 8,
    forearm_R = 7,
    hand_R = 4,
    arm_L = 8,
    forearm_L = 7,
    hand_L = 4,
    thigh_R = 8,
    crus_R = 7,
    foot_R = 4,
    thigh_L = 8,
    crus_L = 7,
    foot_L = 4
}

function Fn.PickRandomDamageLimb(ply)
    local limbs = PlayerLimbs[ply]
    if not limbs then return "thorax" end

    local totalWeight = 0
    for _, limbName in ipairs(Const.RandomDamageLimbs) do
        local state = limbs[limbName]
        if state and not state.dismembered then
            totalWeight = totalWeight + (Const.RandomDamageWeights[limbName] or 1)
        end
    end

    if totalWeight <= 0 then return "thorax" end

    local roll = math.Rand(0, totalWeight)
    for _, limbName in ipairs(Const.RandomDamageLimbs) do
        local state = limbs[limbName]
        if state and not state.dismembered then
            roll = roll - (Const.RandomDamageWeights[limbName] or 1)
            if roll <= 0 then return limbName end
        end
    end

    return "thorax"
end

Const.ConnectedLimbs = {
    ["head"]      = {"thorax"},
    ["thorax"]    = {"head", "abdomen", "arm_R", "arm_L"},
    ["abdomen"]   = {"thorax", "thigh_R", "thigh_L"},
    ["arm_R"]     = {"thorax", "forearm_R"},
    ["forearm_R"] = {"arm_R", "hand_R"},
    ["hand_R"]    = {"forearm_R"},
    ["arm_L"]     = {"thorax", "forearm_L"},
    ["forearm_L"] = {"arm_L", "hand_L"},
    ["hand_L"]    = {"forearm_L"},
    ["thigh_R"]   = {"abdomen", "crus_R"},
    ["crus_R"]    = {"thigh_R", "foot_R"},
    ["foot_R"]    = {"crus_R"},
    ["thigh_L"]   = {"abdomen", "crus_L"},
    ["crus_L"]    = {"thigh_L", "foot_L"},
    ["foot_L"]    = {"crus_L"}
}

Const.LowerLimbs = {
    ["thigh_R"]   = {"thigh_R", "crus_R", "foot_R"},
    ["crus_R"]    = {"crus_R", "foot_R"},
    ["foot_R"]    = {"foot_R"},
    ["thigh_L"]   = {"thigh_L", "crus_L", "foot_L"},
    ["crus_L"]    = {"crus_L", "foot_L"},
    ["foot_L"]    = {"foot_L"},
    ["arm_R"]     = {"arm_R", "forearm_R", "hand_R"},
    ["forearm_R"] = {"forearm_R", "hand_R"},
    ["hand_R"]    = {"hand_R"},
    ["arm_L"]     = {"arm_L", "forearm_L", "hand_L"},
    ["forearm_L"] = {"forearm_L", "hand_L"},
    ["hand_L"]    = {"hand_L"},
}

function Fn.GetLowerLimbs(limbName)
    return Const.LowerLimbs[limbName] or {limbName}
end

Const.ParentLimb = {
    ["hand_R"]    = "forearm_R",
    ["forearm_R"] = "arm_R",
    ["arm_R"]     = "thorax",
    ["hand_L"]    = "forearm_L",
    ["forearm_L"] = "arm_L",
    ["arm_L"]     = "thorax",
    ["foot_R"]    = "crus_R",
    ["crus_R"]    = "thigh_R",
    ["thigh_R"]   = "abdomen",
    ["foot_L"]    = "crus_L",
    ["crus_L"]    = "thigh_L",
    ["thigh_L"]   = "abdomen",
    ["head"]      = "thorax",
    ["abdomen"]   = "thorax"
}

function Fn.ResolveLivingLimb(ply, limb)
    if not PlayerLimbs or not PlayerLimbs[ply] then return limb end
    local current = limb
    local visited = {}
    while current and PlayerLimbs[ply][current] and PlayerLimbs[ply][current].dismembered do
        if visited[current] then break end
        visited[current] = true
        current = Const.ParentLimb[current]
    end
    return (current and PlayerLimbs[ply][current] and not PlayerLimbs[ply][current].dismembered) and current or "thorax"
end

Const.LimbToBones = {
    ["head"]      = {"ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Neck1", "Bip01 Head", "Bip01 Neck"},
    ["arm_L"]     = {"ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_Hand", "Bip01 L Arm", "Bip01 L Arm1", "Bip01 L Arm2", "Bip01 L Hand"},
    ["forearm_L"] = {"ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_Hand", "Bip01 L Arm1", "Bip01 L Arm2", "Bip01 L Hand"},
    ["hand_L"]    = {"ValveBiped.Bip01_L_Hand", "Bip01 L Hand"},
    ["arm_R"]     = {"ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Hand", "Bip01 R Arm", "Bip01 R Arm1", "Bip01 R Arm2", "Bip01 R Hand"},
    ["forearm_R"] = {"ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Hand", "Bip01 R Arm1", "Bip01 R Arm2", "Bip01 R Hand"},
    ["hand_R"]    = {"ValveBiped.Bip01_R_Hand", "Bip01 R Hand"},
    ["thigh_L"]   = {"ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_L_Foot", "Bip01 L Leg", "Bip01 L Leg1", "Bip01 L Foot"},
    ["crus_L"]    = {"ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_L_Foot", "Bip01 L Leg1", "Bip01 L Foot"},
    ["foot_L"]    = {"ValveBiped.Bip01_L_Foot", "Bip01 L Foot"},
    ["thigh_R"]   = {"ValveBiped.Bip01_R_Thigh", "ValveBiped.Bip01_R_Calf", "ValveBiped.Bip01_R_Foot", "Bip01 R Leg", "Bip01 R Leg1", "Bip01 R Foot"},
    ["crus_R"]    = {"ValveBiped.Bip01_R_Calf", "ValveBiped.Bip01_R_Foot", "Bip01 R Leg1", "Bip01 R Foot"},
    ["foot_R"]    = {"ValveBiped.Bip01_R_Foot", "Bip01 R Foot"},
}

Const.LimbBoneNamePatterns = {
    ["head"] = {"head", "neck", "eye", "eyeball", "face", "jaw", "hair", "hat", "helmet"},
    ["arm_L"] = {"l_upperarm", "left_upperarm", "l upperarm", "left upperarm", "l_arm", "left_arm", "leftarm"},
    ["arm_R"] = {"r_upperarm", "right_upperarm", "r upperarm", "right upperarm", "r_arm", "right_arm", "rightarm"},
    ["forearm_L"] = {"l_forearm", "left_forearm", "l forearm", "left forearm", "l_lowerarm", "left_lowerarm"},
    ["forearm_R"] = {"r_forearm", "right_forearm", "r forearm", "right forearm", "r_lowerarm", "right_lowerarm"},
    ["hand_L"] = {"l_hand", "left_hand", "lefthand", "l finger", "l_finger", "left finger", "left_finger"},
    ["hand_R"] = {"r_hand", "right_hand", "righthand", "r finger", "r_finger", "right finger", "right_finger"},
    ["thigh_L"] = {"l_thigh", "left_thigh", "l thigh", "left thigh", "l_upperleg", "left_upperleg", "l_leg", "left_leg"},
    ["thigh_R"] = {"r_thigh", "right_thigh", "r thigh", "right thigh", "r_upperleg", "right_upperleg", "r_leg", "right_leg"},
    ["crus_L"] = {"l_calf", "left_calf", "l calf", "left calf", "l_lowerleg", "left_lowerleg", "l_shin", "left_shin"},
    ["crus_R"] = {"r_calf", "right_calf", "r calf", "right calf", "r_lowerleg", "right_lowerleg", "r_shin", "right_shin"},
    ["foot_L"] = {"l_foot", "left_foot", "leftfoot", "l toe", "l_toe", "left toe", "left_toe"},
    ["foot_R"] = {"r_foot", "right_foot", "rightfoot", "r toe", "r_toe", "right toe", "right_toe"},
}

function Fn.ForEachDismembermentBone(ent, limbName, callback)
    if not IsValid(ent) or not isfunction(callback) then return end

    local visited = {}
    local bones = Const.LimbToBones[limbName]
    if bones then
        for _, boneName in ipairs(bones) do
            local boneIndex = ent:LookupBone(boneName)
            if boneIndex and boneIndex >= 0 and not visited[boneIndex] then
                visited[boneIndex] = true
                callback(boneIndex, boneName)
            end
        end
    end

    local patterns = Const.LimbBoneNamePatterns[limbName]
    if not patterns or not ent.GetBoneCount or not ent.GetBoneName then return end

    for boneIndex = 0, ent:GetBoneCount() - 1 do
        if not visited[boneIndex] then
            local boneName = ent:GetBoneName(boneIndex)
            local lowerName = string.lower(tostring(boneName or ""))
            for _, pattern in ipairs(patterns) do
                if string.find(lowerName, pattern, 1, true) then
                    visited[boneIndex] = true
                    callback(boneIndex, boneName)
                    break
                end
            end
        end
    end
end

function Fn.SetLimbBodygroupState(ent, limbName, hide)
    -- Bodygroup meanings are model-specific. The server must not force them to
    -- 0/1 or players can spawn with missing heads, feet, hair, or clothing.
end


PlayerLimbs = {}
BodyState = {}
WoundSystem.Health.PlayerLimbs = PlayerLimbs
WoundSystem.Health.BodyState = BodyState
local Sessions = {
    Shrapnel = {},
    NextShrapnelId = 1,
    Dislocation = {},
    NextDislocationId = 1,
    Bandage = {},
    NextBandageId = 1,
    Syringe = {},
    NextSyringeId = 1,
    Aed = {},
    NextAedId = 1
}
local SendLimbUpdate

local PlayerInventory = {}
local LastSentLimbState = {}

local SendCardioUpdate

function Fn.ResetFurBloodRegionNW(ply)
    for _, region in ipairs(WoundSystem.Health.Constants.FurBloodRegions) do
        ply:SetNWFloat("WoundSystemFurBlood_" .. region, 0)
    end
end

function Fn.EmptyFurBloodRegions()
    local regions = {}
    for _, region in ipairs(WoundSystem.Health.Constants.FurBloodRegions) do
        regions[region] = 0
    end
    return regions
end

function Fn.AddFurBloodToLimb(ply, limbName, amount)
    local limbs = PlayerLimbs and PlayerLimbs[ply]
    local state = limbs and limbs[limbName]
    if not state or state.dismembered then return end

    amount = math.max(tonumber(amount) or 0, 0)
    if amount <= 0 then return end

    local oldAmount = state.furBloodAmount or 0
    state.furBloodAmount = math.Clamp(oldAmount + amount, 0, WoundSystem.Health.Constants.FurBloodMax)

    local added = state.furBloodAmount - oldAmount
    if added <= 0 or not IsValid(ply) then return end

    local region = WoundSystem.Health.Constants.FurBloodRegionByLimb[limbName]
    ply:SetNWFloat("WoundSystemFurBlood", math.Clamp(ply:GetNWFloat("WoundSystemFurBlood", 0) + added, 0, WoundSystem.Health.Constants.FurBloodMax * #WoundSystem.Health.Constants.FurBloodRegions))

    if region then
        ply:SetNWFloat("WoundSystemFurBlood_" .. region, math.Clamp(ply:GetNWFloat("WoundSystemFurBlood_" .. region, 0) + added, 0, WoundSystem.Health.Constants.FurBloodMax * 4))
    end
end

local function GetBloodVomitSourceEntity(ply, body)
    if body and IsValid(body.unconsciousRagdoll) then
        return body.unconsciousRagdoll
    end

    if IsValid(ply) then
        local ragdoll = ply:GetNWEntity("WoundSystemUnconsciousRagdoll")
        if IsValid(ragdoll) then
            return ragdoll
        end
    end

    return ply
end

local function GetMouthBloodVomitOrigin(ply, body)
    if not IsValid(ply) then return nil, nil end

    local sourceEnt = GetBloodVomitSourceEntity(ply, body)
    if not IsValid(sourceEnt) then return nil, nil end

    local eyeAng = sourceEnt == ply and ply:EyeAngles() or sourceEnt:GetAngles()
    local forward = Angle(0, eyeAng.y, 0):Forward()
    local pos = sourceEnt == ply and ply:EyePos() or sourceEnt:WorldSpaceCenter()

    if sourceEnt.LookupBone and sourceEnt.GetBonePosition then
        local headBone = sourceEnt:LookupBone("ValveBiped.Bip01_Head1")
        if headBone then
            local headPos, headAng = sourceEnt:GetBonePosition(headBone)
            if headPos then
                if headAng then
                    forward = headAng:Forward()
                end
                pos = headPos + forward * 7 - (headAng and headAng:Up() or sourceEnt:GetUp()) * 2
            end
        end
    end

    return pos, forward, sourceEnt
end

local function FinishBloodVomit(ply)
    if not IsValid(ply) or not ply:Alive() then return end

    local body = BodyState and BodyState[ply]
    if not body then return end

    body.bloodVomiting = false
    body.bloodVolume = math.max(-100, (body.bloodVolume or 100) - 1)
    Fn.AddFurBloodToLimb(ply, "head", 2.5)

    local pos, forward, sourceEnt = GetMouthBloodVomitOrigin(ply, body)
    if not pos then return end

    if WoundSystem.BloodEffects and WoundSystem.BloodEffects.Emit then
        WoundSystem.BloodEffects.Emit(pos, forward, 1.8, "vomitblood", nil, sourceEnt)
    end

    local soundEnt = IsValid(sourceEnt) and sourceEnt or ply
    soundEnt:EmitSound(math.random(1, 2) == 1 and "vomit1.ogg" or "vomit2a.ogg", 70, 100, 0.85)
    if WoundSystem.TalkerSayLine then
        timer.Simple(1.5, function()
            if IsValid(ply) then
                WoundSystem.TalkerSayLine(ply, "vomitblood", nil, true)
            end
        end)
    end
    SendCardioUpdate(ply)
end

local function BeginBloodVomit(ply, body)
    if not IsValid(ply) or not body or body.bloodVomiting then return end

    body.bloodVomiting = true
    body.bloodVomitTime = 0

    net.Start("WoundSystem_BloodVomit")
    net.Send(ply)

    timer.Simple(WoundSystem.Health.Constants.BloodVomitWarningTime, function()
        FinishBloodVomit(ply)
    end)
end

Const.BandageProfiles = {
    ["GAUZE"] = {
        mode = "gauze",
        durabilityPerWrap = 100 / 12,
        effectDivisor = 12,
        requireBleed = true,
        effects = {
            bandageSlowAmount = 45,
            skinHealAmount = 30,
            pain = -60,
            boneHealTimer = -20,
            dislocationTimer = -20
        },
        bandagedAtBleed = 1,
        bandagedAtSlow = 10
    },
    ["BRUISE KIT"] = {
        mode = "bruise",
        durabilityPerWrap = 10,
        effectDivisor = 10,
        effects = {
            skinHealAmount = 100,
            muscle = 1,
            pain = -80,
            dislocationTimer = -80
        }
    }
}

function Fn.CopyTable(value)
    if type(value) ~= "table" then return nil end
    return table.Copy and table.Copy(value) or value
end

function Fn.FirstDefined(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if value ~= nil then return value end
    end

    return nil
end

function Fn.GetBandageProfile(itemId)
    itemId = WoundSystem.NormalizeItemId and WoundSystem.NormalizeItemId(itemId) or string.upper(tostring(itemId or ""))

    local fallback = Const.BandageProfiles[itemId]
    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    local use = item and item.use

    if not use or use.minigame ~= "bandage" then
        return fallback
    end

    local bandage = type(use.bandage) == "table" and use.bandage or {}

    local durabilityPerWrap = tonumber(bandage.durabilityPerWrap or use.durabilityPerWrap or (fallback and fallback.durabilityPerWrap)) or WoundSystem.Health.Constants.BandageDurabilityPerWrap
    local effectDivisor = tonumber(bandage.effectDivisor or use.bandageEffectDivisor or use.effectDivisor or (fallback and fallback.effectDivisor))
    if not effectDivisor and durabilityPerWrap > 0 then
        effectDivisor = 100 / durabilityPerWrap
    end

    return {
        mode = bandage.mode or use.bandageMode or (fallback and fallback.mode) or "gauze",
        durabilityPerWrap = durabilityPerWrap,
        effectDivisor = math.max(tonumber(effectDivisor) or 1, 1),
        requireBleed = Fn.FirstDefined(use.requireBleed, bandage.requireBleed, fallback and fallback.requireBleed, false),
        effects = Fn.CopyTable(bandage.effects) or Fn.CopyTable(use.bandageEffects) or Fn.CopyTable(fallback and fallback.effects) or {},
        bodyEffects = Fn.CopyTable(bandage.bodyEffects) or Fn.CopyTable(use.bandageBodyEffects) or Fn.CopyTable(fallback and fallback.bodyEffects) or {},
        setStatuses = Fn.CopyTable(bandage.setStatuses) or Fn.CopyTable(use.bandageSetStatuses) or Fn.CopyTable(fallback and fallback.setStatuses) or nil,
        clearStatuses = Fn.CopyTable(bandage.clearStatuses) or Fn.CopyTable(use.bandageClearStatuses) or Fn.CopyTable(fallback and fallback.clearStatuses) or nil,
        bandagedAtBleed = Fn.FirstDefined(bandage.bandagedAtBleed, use.bandagedAtBleed, fallback and fallback.bandagedAtBleed),
        bandagedAtSlow = Fn.FirstDefined(bandage.bandagedAtSlow, use.bandagedAtSlow, fallback and fallback.bandagedAtSlow),
        applyWrap = bandage.applyWrap or use.applyWrap
    }
end

Const.LimbEffectClamps = {
    skin = {0, 100},
    muscle = {0, 100},
    pain = {0, 100},
    bleed = {0, 100},
    infection = {0, 100},
    infectionAmount = {0, 100},
    infectionSpeed = {0, 100},
    disinfectTime = {0, 999999},
    bandageSlowAmount = {0, 100},
    skinHealAmount = {0, 100},
    muscleStrength = {0, 1},
    boneHealTimer = {0, 100},
    dislocationTimer = {0, 100},
    furBloodAmount = {0, WoundSystem.Health.Constants.FurBloodMax}
}

Const.BodyEffectClamps = {
    bloodVolume = {-100, 100},
    internalBleeding = {0, 100},
    hemothorax = {0, 100},
    bloodOxygen = {0, 100},
    bloodPressure = {0, 250},
    heartRate = {0, 320},
    respiratoryRate = {0, 200},
    cardioShock = {0, 100},
    shock = {0, 100},
    adrenaline = {0, 100},
    brainHealth = {0, 100},
    consciousness = {0, 100},
    sicknessAmount = {0, 100},
    immunity = {0, 200},
    stamina = {0, 100},
    bloodViscosity = {-100, 150},
    radiationSickness = {0, 100},
    wetness = {0, 100},
    strokeAmount = {0, 100},
    opiateHappiness = {-80, 1000},
    antidepressantHappiness = {-100, 100},
    antidepressantAmount = {0, 1000},
    antidepressantCurrentAmount = {0, 1000},
    sleepingPillAmount = {0, 999999},
    opiateAmount = {0, 1000},
    opiateReception = {-1000, 1000},
    actualOpiateReception = {-1000, 1000},
    opiateTolerance = {0, 1000},
    antagonistAmount = {0, 1000},
    hunger = {-50, 125},
    thirst = {-50, 250},
    energy = {0, 100},
    weightOffset = {-80, 100},
    septicShock = {0, 100},
    dirtyness = {0, 100},
    traumaAmount = {0, 100},
    clawHealth = {0, 100},
    clawRegrowTime = {0, 999999},
    caffeinated = {0, 999999},
    badSleepAmount = {0, 999999},
    venomCurrent = {0, 100},
    overdoseIndex = {0, 10},
    painShock = {0, 1},
    lastStandTime = {-999999, 999999},
    focusedLevel = {0, 100},
    horrifiedLevel = {0, 100},
    overEncumberance = {0, 1},
    brainGrowSickness = {0, 999999},
    temporarySlowdown = {0, 0.95},
    vomitTime = {0, 999999},
    vomitPower = {0, 100},
    badLookAmount = {0, 100},
    stimulantMultiplier = {0, 2},
    bloodPressureChangeFromMedicine = {-999999, 999999},
    antibioticImmunityTime = {0, 999999}
}

Const.DrugEffectAliases = {
    opiate = "opiateAmount",
    opiateDose = "opiateAmount",
    opiateAmount = "opiateAmount",
    opioid = "opiateAmount",
    opioidDose = "opiateAmount",
    antagonist = "antagonistAmount",
    antagonistDose = "antagonistAmount",
    antagonistAmount = "antagonistAmount",
    antidepressant = "antidepressantHappiness",
    antidepressantMood = "antidepressantHappiness",
    antidepressantHappiness = "antidepressantHappiness",
    opiateMood = "opiateHappiness",
    opiateHappiness = "opiateHappiness",
    tolerance = "opiateTolerance",
    opiateTolerance = "opiateTolerance",
    overdose = "overdoseIndex",
    overdoseRisk = "overdoseIndex",
    overdoseIndex = "overdoseIndex"
}

function Fn.AddClampedNumber(target, key, amount, fraction, clamps)
    if type(target) ~= "table" or type(amount) ~= "number" then return end

    local current = tonumber(target[key]) or 0
    local nextValue = current + amount * (tonumber(fraction) or 1)
    local clamp = clamps and clamps[key]

    if clamp then
        nextValue = math.Clamp(nextValue, clamp[1], clamp[2])
    end

    target[key] = nextValue
end

function Fn.ApplyNumericEffects(target, effects, wrapFraction, clamps)
    if type(target) ~= "table" or type(effects) ~= "table" then return end

    for key, amount in pairs(effects) do
        if type(amount) == "number" then
            Fn.AddClampedNumber(target, key, amount, wrapFraction, clamps)
        elseif type(amount) == "boolean" then
            target[key] = amount
        end
    end
end

function Fn.ApplyDrugEffects(body, effects, fraction)
    if type(body) ~= "table" or type(effects) ~= "table" then return end

    for key, amount in pairs(effects) do
        local targetKey = Const.DrugEffectAliases[key] or key

        if type(amount) == "number" then
            Fn.AddClampedNumber(body, targetKey, amount, fraction, Const.BodyEffectClamps)
        elseif type(amount) == "boolean" then
            body[targetKey] = amount
        end
    end
end

function Fn.AddBodyShock(body, amount)
    if type(body) ~= "table" then return end

    body.shock = math.Clamp((body.shock or 0) + (tonumber(amount) or 0), 0, 100)
    body.cardioShock = math.max(body.cardioShock or 0, body.shock or 0)
end

local function ApplyTimedBodyEffectStep(ply, body, limbs, effect)
    if not body or not effect then return end

    local kind = effect.kind or effect.id
    if kind == "procoagulant" then
        body.internalBleeding = math.Clamp((body.internalBleeding or 0) * 0.95, 0, 100)
        body.bloodViscosity = math.Clamp((body.bloodViscosity or 0) + 1.75, -100, 150)
        body.strokeAmount = math.Clamp((body.strokeAmount or 0) - 10, 0, 100)

        for limbId, limb in pairs(limbs or {}) do
            if type(limb) == "table" then
                limb.bleed = math.Clamp((limb.bleed or 0) * 0.96, 0, 100)
                if SendLimbUpdate then
                    SendLimbUpdate(ply, limbId, true)
                end
            end
        end
    elseif kind == "reliefcream" then
        local limb = limbs and limbs[effect.limbId]
        if limb then
            limb.pain = math.Clamp(Lerp(0.15, limb.pain or 0, (limb.pain or 0) * 0.1), 0, 100)
            if SendLimbUpdate then
                SendLimbUpdate(ply, effect.limbId, true)
            end
        end
    end
end

local function QueueTimedBodyEffect(ply, body, id, duration, data)
    if not IsValid(ply) or type(body) ~= "table" then return false end

    id = tostring(id or "")
    duration = math.max(tonumber(duration) or 0, 0)
    if id == "" or duration <= 0 then return false end

    body.timedBodyEffects = body.timedBodyEffects or {}

    local effect = body.timedBodyEffects[id]
    if effect then
        effect.remaining = (effect.remaining or 0) + duration
        effect.maxHad = math.max(effect.maxHad or 0, effect.remaining or 0)
        effect.kind = data and data.kind or effect.kind
        effect.limbId = data and data.limbId or effect.limbId
    else
        effect = {
            id = id,
            kind = data and data.kind or id,
            limbId = data and data.limbId or nil,
            remaining = duration,
            maxHad = duration,
            accumulator = 0
        }
        body.timedBodyEffects[id] = effect

        if not data or data.immediate ~= false then
            ApplyTimedBodyEffectStep(ply, body, PlayerLimbs and PlayerLimbs[ply], effect)
        end
    end

    return true
end

local function TickTimedBodyEffects(ply, body, limbs, dt)
    if type(body) ~= "table" or type(body.timedBodyEffects) ~= "table" then return end

    local any = false
    for id, effect in pairs(body.timedBodyEffects) do
        effect.remaining = (tonumber(effect.remaining) or 0) - dt
        effect.accumulator = (tonumber(effect.accumulator) or 0) + dt

        while effect.remaining > 0 and effect.accumulator >= 1 do
            ApplyTimedBodyEffectStep(ply, body, limbs, effect)
            effect.accumulator = effect.accumulator - 1
            any = true
        end

        if effect.remaining <= 0 then
            body.timedBodyEffects[id] = nil
        end
    end

    if any and SendCardioUpdate then
        SendCardioUpdate(ply)
    end
end

WoundSystem.Health = WoundSystem.Health or {}
WoundSystem.Health.AddBodyShock = Fn.AddBodyShock
WoundSystem.Health.QueueTimedBodyEffect = QueueTimedBodyEffect

local function ApplyStatusList(ctx, statuses, value)
    if type(statuses) ~= "table" or not ctx then return end

    for key, statusValue in pairs(statuses) do
        if type(key) == "number" then
            ctx.setStatus(statusValue, value)
        else
            ctx.setStatus(key, statusValue)
        end
    end
end

local function ApplyBandageProfile(ctx, profile)
    if not ctx or not ctx.limb or not profile then return false end

    local wrapFraction = tonumber(ctx.wrapFraction) or 0
    if wrapFraction <= 0 then return false end

    local effectFraction = wrapFraction / math.max(tonumber(profile.effectDivisor) or 1, 1)

    Fn.ApplyNumericEffects(ctx.limb, profile.effects, effectFraction, Const.LimbEffectClamps)
    Fn.ApplyNumericEffects(ctx.body, profile.bodyEffects, effectFraction, Const.BodyEffectClamps)
    ApplyStatusList(ctx, profile.setStatuses, true)
    ApplyStatusList(ctx, profile.clearStatuses, false)

    if ctx.limb.broken and profile.effects and profile.effects.boneHealTimer and (ctx.limb.boneHealTimer or 0) <= 0 then
        ctx.limb.broken = false
        ctx.limb.boneHealTimer = 0
    end

    if ctx.limb.dislocated and profile.effects and profile.effects.dislocationTimer and (ctx.limb.dislocationTimer or 0) <= 0 then
        ctx.limb.dislocated = false
        ctx.limb.dislocationTimer = 0
    end

    if profile.bandagedAtSlow or profile.bandagedAtBleed then
        local slowOk = profile.bandagedAtSlow and (ctx.limb.bandageSlowAmount or 0) >= profile.bandagedAtSlow
        local bleedOk = profile.bandagedAtBleed and (ctx.limb.bleed or 0) <= profile.bandagedAtBleed
        if slowOk or bleedOk then
            ctx.limb.isBandaged = true
        end
    end

    return true
end

local function GetSyringeProfile(itemId)
    itemId = WoundSystem.NormalizeItemId and WoundSystem.NormalizeItemId(itemId) or string.upper(tostring(itemId or ""))

    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    local use = item and item.use
    if not use or use.minigame ~= "syringe" then return nil end

    local syringe = type(use.syringe) == "table" and use.syringe or {}

    return {
        color = Fn.CopyTable(syringe.color) or Fn.CopyTable(use.syringeColor) or {0, 132, 173, 255},
        durabilityPerSecond = tonumber(syringe.durabilityPerSecond or use.syringeDurabilityPerSecond) or WoundSystem.Health.Constants.SyringeDurabilityPerSecond,
        effects = Fn.CopyTable(syringe.effects) or Fn.CopyTable(use.syringeEffects) or {},
        bodyEffects = Fn.CopyTable(syringe.bodyEffects) or Fn.CopyTable(use.syringeBodyEffects) or {},
        drugEffects = Fn.CopyTable(syringe.drugEffects) or Fn.CopyTable(use.syringeDrugEffects) or {},
        woundStatus = Fn.FirstDefined(syringe.woundStatus, use.syringeWoundStatus, "SYRINGE_WOUND"),
        applyUse = syringe.applyUse or use.applyUse
    }
end

local function ApplySyringeProfile(ctx, profile)
    if not ctx or not ctx.limb or not profile then return false end

    local fraction = tonumber(ctx.syringeFraction) or 0
    if fraction <= 0 then return false end

    Fn.ApplyNumericEffects(ctx.limb, profile.effects, fraction, Const.LimbEffectClamps)
    Fn.ApplyNumericEffects(ctx.body, profile.bodyEffects, fraction, Const.BodyEffectClamps)
    Fn.ApplyDrugEffects(ctx.body, profile.drugEffects, fraction)

    if type(profile.applyUse) == "function" then
        if profile.applyUse(ctx) == false then return false end
    end

    return true
end

-- Global table or tracker for god mode players (or you can store it right in BodyState)
concommand.Add("cu_god", function(ply, cmd, args)
    -- Ensure only admins/superadmins can use this command
    if IsValid(ply) and not ply:IsAdmin() then 
        ply:PrintMessage(HUD_PRINTTALK, "[Casualties: Unknown] Access Denied.")
        return 
    end

    -- Get the player's medical data structure
    local body = BodyState[ply]
    if not body then return end

    -- Toggle the god mode state
    body.isGodMode = not body.isGodMode
    ply.WoundSystemGodMode = body.isGodMode

    if body.isGodMode then
        if body.unconscious or IsValid(body.unconsciousRagdoll) then
            RestorePlayerFromUnconsciousRagdoll(ply, body, false)
        end

        -- Freeze/Reset critical parameters immediately on activation
        body.pain = 0
        body.bloodVolume = 200 -- Matches the upper clamp limit in your CardioLiteTick
        body.temperature = 37.0
        body.internalBleeding = 0
        body.bloodVomitTime = 0
        body.bloodVomiting = false
        body.unconscious = false
        body.wasUnconscious = false
        body.lastFurBloodTotal = 0
        body.lastFurBloodRegions = Fn.EmptyFurBloodRegions()
        ply:SetNWFloat("WoundSystemFurBlood", 0)
        Fn.ResetFurBloodRegionNW(ply)
        WoundSystem.Health.SetFacialExpressionNW(ply, "normal", 0, 2)
        WoundSystem.Health.ResetForcedFacialExpressionNW(ply)
        
        -- Reset limb states completely
        local limbs = PlayerLimbs[ply]
        if limbs then
            for limbName, state in pairs(limbs) do
                state.skin = 100
                state.muscle = 100
                state.muscleStrength = 1
                state.pain = 0
                state.bleed = 0
                state.infection = 0
                state.infectionSpeed = 0
                state.shrapnel = 0
                state.disinfectTime = 0
                state.broken = false -- Fixed from state.fracture
                state.dislocated = false
                state.dislocationTimer = 0
                state.boneHealTimer = 0
                state.isBandaged = false
                state.blockedBleeding = false
                state.bandageSlowAmount = 0
                state.skinHealAmount = 0
				state.hasInjection = false
                state.furBloodAmount = 0
                state.customStatuses = {}
				if limbName == "head" then
                    state.eyes = 2
                end

                -- Force immediate client UI refresh for this limb
                SendLimbUpdate(ply, limbName, true)
            end
        end

        ply:PrintMessage(HUD_PRINTTALK, "[Casualties: Unknown] God Mode ENABLED. Parameters frozen.")
    else
        ply:PrintMessage(HUD_PRINTTALK, "[Casualties: Unknown] God Mode DISABLED. Physiology resuming.")
    end
end)

function Fn.IsCriticalLimb(limbName)
    return limbName == "head" or limbName == "thorax" or limbName == "abdomen"
end

function Fn.GetMajorVesselBleed(limbName, dmg)
    if limbName == "thigh_R" or limbName == "thigh_L" or limbName == "arm_R" or limbName == "arm_L" then
        if math.random() < 0.15 then
            return dmg * 0.9
        end
    elseif limbName == "crus_R" or limbName == "crus_L" or limbName == "forearm_R" or limbName == "forearm_L" then
        if math.random() < 0.08 then
            return dmg * 0.65
        end
    end

    return 0
end

Const.RagdollDamageBones = {
    { limb = "head", patterns = {"head", "neck", "jaw", "face"} },
    { limb = "hand_L", patterns = {"l_hand", "l hand", "left hand", "bip01_l_finger", "leftfinger"} },
    { limb = "hand_R", patterns = {"r_hand", "r hand", "right hand", "bip01_r_finger", "rightfinger"} },
    { limb = "forearm_L", patterns = {"l_forearm", "l forearm", "left forearm", "l_lowerarm", "left lowerarm"} },
    { limb = "forearm_R", patterns = {"r_forearm", "r forearm", "right forearm", "r_lowerarm", "right lowerarm"} },
    { limb = "arm_L", patterns = {"l_upperarm", "l upperarm", "left upperarm", "l_clavicle", "left clavicle"} },
    { limb = "arm_R", patterns = {"r_upperarm", "r upperarm", "right upperarm", "r_clavicle", "right clavicle"} },
    { limb = "foot_L", patterns = {"l_foot", "l foot", "left foot", "l_toe", "left toe"} },
    { limb = "foot_R", patterns = {"r_foot", "r foot", "right foot", "r_toe", "right toe"} },
    { limb = "crus_L", patterns = {"l_calf", "l calf", "l_shin", "l shin", "left shin", "left calf", "l_lowerleg", "left lowerleg"} },
    { limb = "crus_R", patterns = {"r_calf", "r calf", "r_shin", "r shin", "right shin", "right calf", "r_lowerleg", "right lowerleg"} },
    { limb = "thigh_L", patterns = {"l_thigh", "l thigh", "left thigh", "l_upperleg", "left upperleg"} },
    { limb = "thigh_R", patterns = {"r_thigh", "r thigh", "right thigh", "r_upperleg", "right upperleg"} },
    { limb = "thorax", patterns = {"spine2", "spine3", "spine4", "chest", "rib", "sternum"} },
    { limb = "abdomen", patterns = {"pelvis", "spine", "hips", "hip", "spine1"} }
}

local function RagdollBoneNameToLimb(boneName)
    boneName = string.lower(tostring(boneName or ""))
    if boneName == "" then return nil end

    for _, candidate in ipairs(Const.RagdollDamageBones) do
        for _, pattern in ipairs(candidate.patterns) do
            if string.find(boneName, pattern, 1, true) then
                return candidate.limb
            end
        end
    end

    return nil
end

local function GuessRagdollDamageLimb(ragdoll, dmginfo)
    local pos = dmginfo:GetDamagePosition()
    if pos == vector_origin and dmginfo.GetReportedPosition then
        local reportedPos = dmginfo:GetReportedPosition()
        if reportedPos and reportedPos ~= vector_origin then
            pos = reportedPos
        end
    end

    if pos == vector_origin then
        pos = ragdoll:WorldSpaceCenter()
    end

    if dmginfo.GetDamageForce and ragdoll.TranslatePhysBoneToBone then
        local force = dmginfo:GetDamageForce()
        if force and force:LengthSqr() > 0 then
            local dir = force:GetNormalized()
            local tr = util.TraceLine({
                start = pos - dir * 12,
                endpos = pos + dir * 48,
                filter = function(ent) return ent == ragdoll end,
                mask = MASK_SHOT
            })

            if tr.Hit and tr.Entity == ragdoll and tr.PhysicsBone and tr.PhysicsBone >= 0 then
                local boneId = ragdoll:TranslatePhysBoneToBone(tr.PhysicsBone)
                if boneId and boneId >= 0 then
                    local limb = RagdollBoneNameToLimb(ragdoll:GetBoneName(boneId))
                    if limb then return limb end
                end
            end
        end
    end

    local bestLimb = "thorax"
    local bestDist = math.huge

    for i = 0, ragdoll:GetBoneCount() - 1 do
        local boneName = string.lower(ragdoll:GetBoneName(i) or "")
        local bonePos = ragdoll:GetBonePosition(i)
        if bonePos then
            local limb = RagdollBoneNameToLimb(boneName)
            if limb then
                local dist = bonePos:DistToSqr(pos)
                if dist < bestDist then
                    bestDist = dist
                    bestLimb = limb
                end
            end
        end
    end

    return bestLimb
end

local function RemapClamped(value, inMin, inMax, outMin, outMax)
    if inMin == inMax then return outMin end
    local frac = math.Clamp((value - inMin) / (inMax - inMin), 0, 1)
    return Lerp(frac, outMin, outMax)
end

local function ApplyDislocation(ply, limbName, state)
    state.dislocated = true
    state.dislocationTimer = 100
    hook.Run("WoundSystem_OnDislocate", ply, limbName, state)
end

local function ApplyFracture(ply, limbName, state)
    state.broken = true
    state.boneHealTimer = 100
    hook.Run("WoundSystem_OnFracture", ply, limbName, state)
end



local function GetShrapnelInputDelay()
    local hz = math.max(WoundSystem.Health.Config.CvFloat(WoundSystem.Health.Config.CVars.ShrapnelInputHz, 20), 1)
    return 1 / hz
end

local function GetLimbState(ply, limbId)
    if not PlayerLimbs[ply] then return nil end
    return PlayerLimbs[ply][limbId]
end

local function BuildMedicalItemContext(ply, item, slotIdx, slot, limbId)
    local limb = GetLimbState(ply, limbId)
    local body = GetBody and GetBody(ply) or nil

    local ctx = {
        ply = ply,
        item = item,
        itemId = item and item.id,
        slotIdx = slotIdx,
        slot = slot,
        limbId = limbId,
        limb = limb,
        body = body,
        limbs = PlayerLimbs[ply],
        inventory = GetInventory and GetInventory(ply) or nil
    }

    ctx.syncLimb = function(force)
        if SendLimbUpdate then
            SendLimbUpdate(ply, limbId, force ~= false)
        end
    end

    ctx.syncInventory = function()
        if SyncInventoryToClient then
            SyncInventoryToClient(ply)
        end
    end

    ctx.setStatus = function(statusId, value)
        if not WoundSystem.Statuses then return false end
        return WoundSystem.Statuses.Set(limb, statusId, value)
    end

    ctx.clearStatus = function(statusId)
        if not WoundSystem.Statuses then return false end
        return WoundSystem.Statuses.Clear(limb, statusId)
    end

    ctx.hasStatus = function(statusId)
        return WoundSystem.Statuses and WoundSystem.Statuses.Has(limb, statusId) or false
    end

    return ctx
end

local MedicalItemHandlers = {}

function WoundSystem.RegisterServerMedicalItem(itemId, handler)
    if type(handler) ~= "function" then return end

    itemId = WoundSystem.NormalizeItemId and WoundSystem.NormalizeItemId(itemId) or string.upper(tostring(itemId or ""))
    if itemId == "" then return end

    MedicalItemHandlers[itemId] = handler
end

local function UseRegisteredMedicalItem(ply, itemId, limbId, slotIdx, slot)
    if not IsValid(ply) or not ply:Alive() then return false end

    itemId = WoundSystem.NormalizeItemId and WoundSystem.NormalizeItemId(itemId) or string.upper(tostring(itemId or ""))
    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId) or nil
    local use = item and item.use or nil
    local ctx = BuildMedicalItemContext(ply, item, slotIdx, slot, limbId)

    if use and WoundSystem.Items and WoundSystem.Items.LimbAllowed and not WoundSystem.Items.LimbAllowed(use, limbId) then
        return false
    end

    if use and type(use.canUse) == "function" and use.canUse(ctx) == false then
        return false
    end

    local handler = MedicalItemHandlers[itemId]
    if handler then
        return handler(ply, limbId, itemId, ctx) ~= false
    end

    if use and type(use.apply) == "function" then
        return use.apply(ctx) ~= false
    end

    return false
end

WoundSystem.UseMedicalItem = UseRegisteredMedicalItem

local function CountRemainingPieces(session)
    local count = 0
    for _, piece in ipairs(session.pieces) do
        if piece.active and piece.embedded ~= false then
            count = count + 1
        end
    end
    return count
end

local function WriteShrapnelPieces(session)
    for i = 1, WoundSystem.Health.Constants.ShrapnelPieceCount do
        local piece = session.pieces[i]
        net.WriteFloat(piece.x)
        net.WriteFloat(piece.y)
        net.WriteBool(piece.active)
    end
end

local function WriteShrapnelEmbeddedStates(session)
    for i = 1, WoundSystem.Health.Constants.ShrapnelPieceCount do
        local piece = session.pieces[i]
        net.WriteBool(piece and piece.embedded ~= false)
    end
end

local MINIGAME_ACK_BANDAGE = 1
local MINIGAME_ACK_SYRINGE = 2
local MINIGAME_ACK_AED = 3

local function ReadOptionalInputSeq()
    if not net.BytesLeft then return 0 end

    local bytesLeft, bitsLeft = net.BytesLeft()
    if (bitsLeft or 0) >= 24 or (bytesLeft or 0) >= 3 then
        return net.ReadUInt(24)
    end

    return 0
end

local function SendMinigameAck(ply, gameId, session)
    if not IsValid(ply) or not session then return end

    net.Start("WoundSystem_MinigameAck")
        net.WriteUInt(gameId or 0, 3)
        net.WriteUInt(session.id or 0, 24)
        net.WriteUInt(session.lastAckSeq or 0, 24)
    net.Send(ply)
end

local function MinigameTimeoutLimit(ply, baseTimeout)
    local ping = IsValid(ply) and ply.Ping and ply:Ping() or 0
    return (tonumber(baseTimeout) or 0) + math.Clamp((tonumber(ping) or 0) / 1000 * 4, 0, 1.5)
end

local function SendShrapnelOpen(ply, session)
    local remaining = CountRemainingPieces(session)
    net.Start("WoundSystem_ShrapnelOpen")
        net.WriteUInt(session.id, 24)
        net.WriteString(session.limbId)
        net.WriteBool(session.hasTweezers == true)
        WriteShrapnelPieces(session)
        net.WriteUInt(remaining, 4)
        WriteShrapnelEmbeddedStates(session)
        net.WriteUInt(session.lastAckSeq or 0, 24)
    net.Send(ply)
end

local function SendShrapnelState(ply, session)
    local remaining = CountRemainingPieces(session)
    net.Start("WoundSystem_ShrapnelState")
        net.WriteUInt(session.id, 24)
        WriteShrapnelPieces(session)
        net.WriteUInt(remaining, 4)
        WriteShrapnelEmbeddedStates(session)
        net.WriteUInt(session.lastAckSeq or 0, 24)
    net.Send(ply)
end

local function BroadcastMinigameOneShot(ply, soundName, volume)
    if not IsValid(ply) or not soundName or soundName == "" then return end

    volume = tonumber(volume) or 0.5
    ply:SendLua(string.format("surface.PlaySound(%q)", soundName))

    net.Start("WoundSystem_MinigameSound_Client")
        net.WriteEntity(ply)
        net.WriteString(soundName)
        net.WriteFloat(volume)
        net.WriteBool(false)
        net.WriteBool(false)
    net.SendOmit(ply)
end

local function CloseShrapnelSession(ply, reason)
    local session = Sessions.Shrapnel[ply]
    if not session then return end

    if session.playingSquelch then
        ply:SendLua([[
            if WoundSystem.SquelchSound then
                WoundSystem.SquelchSound:Stop()
            end
        ]])
        net.Start("WoundSystem_MinigameSound_Client")
        net.WriteEntity(ply)
        net.WriteString("squelchloop.ogg")
        net.WriteFloat(0.4)
        net.WriteBool(true)
        net.WriteBool(true)
        net.SendOmit(ply)
    end

    Sessions.Shrapnel[ply] = nil
    net.Start("WoundSystem_ShrapnelClose")
        net.WriteUInt(session.id, 24)
        net.WriteString(reason or "closed")
    net.Send(ply)
end

local function DislocationTimerFromBone(session)
    local dx = (session.boneX or 0) - WoundSystem.Health.Constants.DislocationFinishX
    local dy = (session.boneY or 0) - WoundSystem.Health.Constants.DislocationFinishY
    return math.Clamp(math.sqrt(dx * dx + dy * dy) * 0.2, 0, 100)
end

local function SendDislocationOpen(ply, session)
    net.Start("WoundSystem_DislocationOpen")
        net.WriteUInt(session.id, 24)
        net.WriteString(session.limbId or "")
        net.WriteBool(session.hasWrench == true)
        net.WriteFloat(session.boneX or WoundSystem.Health.Constants.DislocationFinishX)
        net.WriteFloat(session.boneY or WoundSystem.Health.Constants.DislocationFinishY)
        net.WriteFloat(session.boneVelX or 0)
        net.WriteFloat(session.boneVelY or 0)
        net.WriteFloat(session.dislocationTimer or 0)
        net.WriteBool(session.painBlocked == true)
        net.WriteUInt(session.lastAckSeq or 0, 24)
    net.Send(ply)
end

local function SendDislocationState(ply, session)
    net.Start("WoundSystem_DislocationState")
        net.WriteUInt(session.id, 24)
        net.WriteFloat(session.boneX or WoundSystem.Health.Constants.DislocationFinishX)
        net.WriteFloat(session.boneY or WoundSystem.Health.Constants.DislocationFinishY)
        net.WriteFloat(session.boneVelX or 0)
        net.WriteFloat(session.boneVelY or 0)
        net.WriteFloat(session.dislocationTimer or 0)
        net.WriteBool(session.painBlocked == true)
        net.WriteBool(session.hitThisInput == true)
        net.WriteUInt(session.lastAckSeq or 0, 24)
    net.Send(ply)
    session.hitThisInput = false
end

local function CloseDislocationSession(ply, reason)
    local session = Sessions.Dislocation[ply]
    if not session then return end

    Sessions.Dislocation[ply] = nil
    net.Start("WoundSystem_DislocationClose")
        net.WriteUInt(session.id, 24)
        net.WriteString(reason or "closed")
    net.Send(ply)
end

-- Z-City SWEP minigames (hg.WoundBridge) use a temporary tool slot (index 6) and a deferred session:
-- the minigame only measures the player's work, the effect is applied by session.onClose once it was completed.
local function FinishExternalSession(ply, session, reason)
    if not session or not session.external then return end

    local inv = PlayerInventory[ply]
    if inv then inv[6] = nil end
    if IsValid(ply) then
        SyncInventoryToClient(ply)
        ply.WoundSystemExtMinigameAttackLock = true -- the mouse button that was used in the minigame must not fire the SWEP again
    end

    if type(session.onClose) == "function" then
        local ok, err = pcall(session.onClose, ply, session, reason)
        if not ok then ErrorNoHalt("[WoundSystem] external minigame onClose failed: " .. tostring(err) .. "\n") end
    end
end

local function CloseBandageSession(ply, reason)
    local session = Sessions.Bandage[ply]
    if not session then return end

    Sessions.Bandage[ply] = nil
    net.Start("WoundSystem_BandageClose")
        net.WriteUInt(session.id, 24)
        net.WriteString(reason or "closed")
    net.Send(ply)

    FinishExternalSession(ply, session, reason)
end

local function SendBandageOpen(ply, session)
    net.Start("WoundSystem_BandageOpen")
        net.WriteUInt(session.id, 24)
        net.WriteString(session.limbId)
        net.WriteString(session.mode or "gauze")
        net.WriteUInt(session.slotIdx or 0, 3)
    net.Send(ply)
end

local function SendSyringeOpen(ply, session)
    local inv = PlayerInventory[ply]
    local slot = inv and inv[session.slotIdx]
    local maxDur = WoundSystem.Items and WoundSystem.Items.GetMax and WoundSystem.Items.GetMax(session.itemId) or 100
    local condition = slot and math.Clamp((slot.durability or 0) / math.max(maxDur, 1), 0, 1) or 0

    net.Start("WoundSystem_SyringeOpen")
        net.WriteUInt(session.id, 24)
        net.WriteString(session.limbId)
        net.WriteUInt(session.slotIdx or 0, 3)
        net.WriteString(session.itemId or "")
        net.WriteFloat(condition)
    net.Send(ply)
end

local function SendSyringeState(ply, session)
    local inv = PlayerInventory[ply]
    local slot = inv and inv[session.slotIdx]
    local maxDur = WoundSystem.Items and WoundSystem.Items.GetMax and WoundSystem.Items.GetMax(session.itemId) or 100
    local condition = slot and math.Clamp((slot.durability or 0) / math.max(maxDur, 1), 0, 1) or 0

    net.Start("WoundSystem_SyringeState")
        net.WriteUInt(session.id, 24)
        net.WriteFloat(condition)
        net.WriteUInt(session.lastAckSeq or 0, 24)
    net.Send(ply)
end

local function CloseSyringeSession(ply, reason)
    local session = Sessions.Syringe[ply]
    if not session then return end

    Sessions.Syringe[ply] = nil
    net.Start("WoundSystem_SyringeClose")
        net.WriteUInt(session.id, 24)
        net.WriteString(reason or "closed")
    net.Send(ply)

    FinishExternalSession(ply, session, reason)
end

local function SendAedOpen(ply, session)
    local inv = PlayerInventory[ply]
    local slot = inv and inv[session.slotIdx]
    local maxDur = WoundSystem.Items and WoundSystem.Items.GetMax and WoundSystem.Items.GetMax(session.itemId) or 100
    local condition = slot and math.Clamp((slot.durability or 0) / math.max(maxDur, 1), 0, 1) or 0

    net.Start("WoundSystem_AEDOpen")
        net.WriteUInt(session.id, 24)
        net.WriteString(session.limbId)
        net.WriteUInt(session.slotIdx or 0, 3)
        net.WriteString(session.itemId or "")
        net.WriteFloat(condition)
    net.Send(ply)
end

local function SendAedState(ply, session)
    local inv = PlayerInventory[ply]
    local slot = inv and inv[session.slotIdx]
    local maxDur = WoundSystem.Items and WoundSystem.Items.GetMax and WoundSystem.Items.GetMax(session.itemId) or 100
    local condition = slot and math.Clamp((slot.durability or 0) / math.max(maxDur, 1), 0, 1) or 0

    net.Start("WoundSystem_AEDState")
        net.WriteUInt(session.id, 24)
        net.WriteUInt(session.state or 0, 3)
        net.WriteFloat(condition)
        net.WriteUInt(session.lastAckSeq or 0, 24)
    net.Send(ply)
end

local function CloseAedSession(ply, reason)
    local session = Sessions.Aed[ply]
    if not session then return end

    Sessions.Aed[ply] = nil
    net.Start("WoundSystem_AEDClose")
        net.WriteUInt(session.id, 24)
        net.WriteString(reason or "closed")
    net.Send(ply)
end

local function BreakShrapnelGrasp(ply, session, state)
    session.heldIndex = nil
    session.grabArmed = false
    session.holdSource = nil

    state.skin = math.Clamp(state.skin - math.Rand(4, 6), 0, 100)
    state.bleed = math.Clamp(state.bleed + math.Rand(0.4, 1.0), 0, 100)
    state.pain = math.Clamp(state.pain + math.Rand(9, 16), 0, 100)
    Fn.ClearLimbBandage(state)

    SendLimbUpdate(ply, session.limbId, true)
end

function WoundSystem.Health.UnconsciousCardioNetValueChanged(body, previous)
    if not previous then return true end
    if previous.unconscious ~= (body.unconscious == true) then return true end
    if math.abs((previous.bloodOxygen or 100) - (body.bloodOxygen or 100)) >= 1.5 then return true end
    if math.abs((previous.bloodPressure or 120) - (body.bloodPressure or 120)) >= 3 then return true end
    if math.abs((previous.heartRate or 70) - (body.heartRate or 70)) >= 4 then return true end
    if math.abs((previous.respiratoryRate or 100) - (body.respiratoryRate or 100)) >= 4 then return true end
    if math.abs((previous.consciousness or 100) - (body.consciousness or 100)) >= 1.5 then return true end
    if math.abs((previous.brainHealth or 100) - (body.brainHealth or 100)) >= 1 then return true end
    if math.abs((previous.bloodVolume or 100) - (body.bloodVolume or 100)) >= 1 then return true end
    if math.abs((previous.totalBleedSpeed or 0) - (body.totalBleedSpeed or 0)) >= 0.08 then return true end
    if math.abs((previous.fibrillationProgress or 0) - (body.fibrillationProgress or 0)) >= 1 then return true end
    if previous.hasPulmonaryEmbolism ~= (body.hasPulmonaryEmbolism == true) then return true end

    return false
end

function WoundSystem.Health.RememberUnconsciousCardioNetSnapshot(body)
    body.lastUnconsciousCardioNetSnapshot = {
        unconscious = body.unconscious == true,
        bloodOxygen = body.bloodOxygen or 100,
        bloodPressure = body.bloodPressure or 120,
        heartRate = body.heartRate or 70,
        respiratoryRate = body.respiratoryRate or 100,
        consciousness = body.consciousness or 100,
        brainHealth = body.brainHealth or 100,
        bloodVolume = body.bloodVolume or 100,
        totalBleedSpeed = body.totalBleedSpeed or 0,
        fibrillationProgress = body.fibrillationProgress or 0,
        hasPulmonaryEmbolism = body.hasPulmonaryEmbolism == true
    }
end

function WoundSystem.Health.ShouldSkipUnconsciousCardioNet(ply, body, force)
    if force or not body or not body.unconscious then return false end

    local now = CurTime()
    local minInterval = WoundSystem.Health.IsStableUnconsciousSlowTickEligible
        and WoundSystem.Health.IsStableUnconsciousSlowTickEligible(ply, body)
        and 0.75
        or 0.5

    if now < (body.nextUnconsciousCardioNetAt or 0) then
        return true
    end

    if not WoundSystem.Health.UnconsciousCardioNetValueChanged(body, body.lastUnconsciousCardioNetSnapshot) then
        body.nextUnconsciousCardioNetAt = now + minInterval
        return true
    end

    body.nextUnconsciousCardioNetAt = now + minInterval
    return false
end

SendCardioUpdate = function(ply, force)
    local body = BodyState[ply]
    if not body then return end

    WoundSystem.Health.RecomputeBodyPain(body, PlayerLimbs[ply])
    if WoundSystem.Health.ShouldSkipUnconsciousCardioNet(ply, body, force) then return end

    net.Start("WoundSystem_UpdateCardio")
        net.WriteFloat(body.bloodVolume)
        net.WriteFloat(body.internalBleeding)
        net.WriteFloat(body.hemothorax)
        net.WriteFloat(body.heartRate)
        net.WriteFloat(body.bloodPressure)
        net.WriteFloat(body.bloodOxygen)
        net.WriteFloat(body.fibrillationProgress)
        net.WriteFloat(body.cardioShock)
        net.WriteFloat(body.adrenaline)
        net.WriteFloat(body.temperature)
        net.WriteFloat(body.avgPain)
        net.WriteFloat(body.immunity)
        net.WriteFloat(body.respiratoryRate)
        net.WriteFloat(body.brainHealth)
        net.WriteFloat(body.consciousness)
        net.WriteBool(body.unconscious)
        net.WriteFloat(body.stamina)
        net.WriteFloat(body.bloodViscosity or 0)
        net.WriteFloat(body.radiationSickness or 0)
        net.WriteFloat(body.wetness or 0)
        net.WriteFloat(body.totalBleedSpeed or 0)
        net.WriteFloat(body.sicknessAmount or 0)
        net.WriteFloat(body.hearingLoss or 0)
        net.WriteFloat(body.strokeAmount or 0)
        net.WriteBool(body.hasPulmonaryEmbolism or false)
        net.WriteFloat(body.hunger or 100)
        net.WriteFloat(body.thirst or 100)
        net.WriteFloat(body.energy or 100)
        net.WriteFloat(body.weightOffset or 0)
        net.WriteFloat(body.septicShock or 0)
        net.WriteFloat(body.dirtyness or 0)
        net.WriteFloat(body.traumaAmount or 0)
        net.WriteFloat(body.clawHealth or 100)
        net.WriteFloat(body.clawRegrowTime or 0)
        net.WriteFloat(body.caffeinated or 0)
        net.WriteFloat(body.badSleepAmount or 0)
        net.WriteFloat(body.venomCurrent or 0)
        net.WriteFloat(body.overdoseIndex or 0)
        net.WriteFloat(body.painShock or 0)
        net.WriteFloat(body.opiateHappiness or 0)
        net.WriteFloat(body.antidepressantHappiness or 0)
        net.WriteFloat(body.opiateAmount or 0)
        net.WriteFloat(body.opiateReception or 0)
        net.WriteFloat(body.actualOpiateReception or 0)
        net.WriteFloat(body.opiateTolerance or 0)
        net.WriteFloat(body.lastStandTime or 0)
        net.WriteFloat(body.focusedLevel or 0)
        net.WriteFloat(body.horrifiedLevel or 0)
        net.WriteFloat(body.overEncumberance or 0)
        net.WriteFloat(body.brainGrowSickness or 0)
        net.WriteBool(body.sleeping or false)
        net.WriteBool(body.disfigured or false)
        net.WriteBool(body.eyeGone or false)
        net.WriteBool(body.bothEyesGone or false)
        net.WriteBool(body.onHardStimulants or false)
        net.WriteBool(body.impairedSpeech or false)
        net.WriteBool(body.mindWipe or false)
        net.WriteUInt(WoundSystem.Health.GetLifecycleSeq(ply), 24)
        local skills = body.skills or (WoundSystem.Skills and WoundSystem.Skills.AttachToBody and WoundSystem.Skills.AttachToBody(ply, body)) or {}
        net.WriteUInt(math.Clamp(math.floor(tonumber(skills.STR) or 9), 0, 255), 8)
        net.WriteUInt(math.Clamp(math.floor(tonumber(skills.RES) or 8), 0, 255), 8)
        net.WriteUInt(math.Clamp(math.floor(tonumber(skills.INT) or 7), 0, 255), 8)
    net.Send(ply)

    if body.unconscious then
        WoundSystem.Health.RememberUnconsciousCardioNetSnapshot(body)
    else
        body.lastUnconsciousCardioNetSnapshot = nil
        body.nextUnconsciousCardioNetAt = nil
    end
end

local function InitBody(ply)
    local keepGodMode = BodyState[ply] and BodyState[ply].isGodMode or (IsValid(ply) and ply.WoundSystemGodMode) or false

    BodyState[ply] = {
        bloodVolume = 100,
        internalBleeding = 0,
        hemothorax = 0,
        heartRate = 70,
        respiratoryRate = 100,
        bloodPressure = 120,
        bloodOxygen = 98,
        fibrillationProgress = 0,
        cardioShock = 0,
        shock = 0,
        cardioDamageBuffer = 0,
        adrenaline = 0,
        temperature = 37,
        avgPain = 0,
        averagePain = 0,
        immunity = 100,
        immunityMult = 1,
        brainHealth = 100,
        consciousness = 100,
        brainDamageBuffer = 0,
        unconscious = false,
        brainDead = false,
        wasUnconscious = false,
        unconsciousRagdoll = nil,
        deathRagdollOverride = nil,
        ragdollWakePos = nil,
        ragdollWakeAng = nil,
        ragdollModeFailed = false,
        lastDamageAttacker = nil,
        lastDamageInflictor = nil,
        lastDamageType = 0,
        lastDamageTime = 0,
        lastDamageHitRagdoll = false,
        stamina = 100,
        hunger = 100,
        frozenHunger = 100,
        thirst = 100,
        frozenThirst = 100,
        energy = 100,
        weightOffset = 0,
        bloodViscosity = 0,
        curAdrenaline = 0,
        radiationSickness = 0,
        wetness = 0,
        sicknessAmount = 0,
        septicShock = 0,
        opiateHappiness = 0,
        antidepressantHappiness = 0,
        antidepressantAmount = 0,
        antidepressantCurrentAmount = 0,
        sleepingPillAmount = 0,
        sleepingPillWasSleeping = false,
        opiateAmount = 0,
        opiateReception = 0,
        actualOpiateReception = 0,
        opiateTolerance = 0,
        dirtyness = 0,
        traumaAmount = 0,
        clawHealth = 100,
        clawRegrowTime = 0,
        caffeinated = 0,
        badSleepAmount = 0,
        venomCurrent = 0,
        overdoseIndex = 0,
        painShock = 0,
        bloodVomitTime = 0,
        bloodVomiting = false,
        vomitTime = 0,
        vomiting = false,
        vomitPower = 0,
        badLookAmount = 0,
        specialCryingUntil = 0,
        totalBleedSpeed = 0,
        hearingLoss = 0,
        hasPulmonaryEmbolism = false,
        bloodVesselSize = 1,
        radiationExposureTimer = 0,
        strokeAmount = 0,
        sleeping = false,
        disfigured = false,
        eyeGone = false,
        bothEyesGone = false,
        onHardStimulants = false,
        stimulantMultiplier = 0,
        impairedSpeech = false,
        mindWipe = false,
        lastStandTime = 0,
        focusedLevel = 0,
        horrifiedLevel = 0,
        overEncumberance = 0,
        brainGrowSickness = 0,
        temporarySlowdown = 0,
        bloodPressureChangeFromMedicine = 0,
        antibioticImmunityTime = 0,
        timedBodyEffects = {},
        happiness = 0,
        totalHappiness = 0,
        jumpSpeed = 6.5,
        fallingRagdoll = false,
        fallingRagdollWakeTime = 0,
        fallingRagdollReason = nil,
        nextWeaponRagdollTime = 0,
        isGodMode = keepGodMode,
        lastFurBloodTotal = 0,
        lastFurBloodRegions = Fn.EmptyFurBloodRegions()
    }

    if WoundSystem.Skills and WoundSystem.Skills.AttachToBody then
        WoundSystem.Skills.AttachToBody(ply, BodyState[ply])
    end

    ply:SetNWFloat("BloodAmount", 100)
    ply:SetNWFloat("WoundSystemFurBlood", 0)
    Fn.ResetFurBloodRegionNW(ply)
    ply:SetNWFloat("BrainHealth", 100)
    ply:SetNWFloat("Consciousness", 100)
    ply:SetNWBool("WoundSystemUnconscious", false)
    WoundSystem.Health.SetFacialExpressionNW(ply, "normal", 0, 2)
    WoundSystem.Health.ResetForcedFacialExpressionNW(ply)
    if WoundSystem.Health.CAS3BodyFeel and WoundSystem.Health.CAS3BodyFeel.InitBodyFields then
        WoundSystem.Health.CAS3BodyFeel.InitBodyFields(BodyState[ply])
    end
end

local function EnsureBrainState(ply, body)
    body.brainHealth = body.brainHealth or 100
    body.consciousness = body.consciousness or 100
    body.brainDamageBuffer = body.brainDamageBuffer or 0
    body.unconscious = body.unconscious or false
    body.brainDead = body.brainDead or false
    body.wasUnconscious = body.wasUnconscious or false
    body.ragdollModeFailed = body.ragdollModeFailed or false
    body.stamina = body.stamina or 100
    body.hunger = body.hunger or 100
    if body.frozenHunger == nil then
        body.frozenHunger = body.hunger
    end
    body.thirst = body.thirst or 100
    if body.frozenThirst == nil then
        body.frozenThirst = body.thirst
    end
    body.energy = body.energy or 100
    body.weightOffset = body.weightOffset or 0
    body.bloodViscosity = body.bloodViscosity or 0
    body.fallingRagdoll = body.fallingRagdoll or false
    body.fallingRagdollWakeTime = body.fallingRagdollWakeTime or 0
    body.fallingRagdollReason = body.fallingRagdollReason or nil
    body.nextWeaponRagdollTime = body.nextWeaponRagdollTime or 0
    body.curAdrenaline = body.curAdrenaline or 0
    body.radiationSickness = body.radiationSickness or 0
    body.wetness = body.wetness or 0
    body.sicknessAmount = body.sicknessAmount or 0
    body.septicShock = body.septicShock or 0
    body.shock = body.shock or 0
    body.opiateHappiness = body.opiateHappiness or 0
    body.antidepressantHappiness = body.antidepressantHappiness or 0
    body.antidepressantAmount = body.antidepressantAmount or 0
    body.antidepressantCurrentAmount = body.antidepressantCurrentAmount or 0
    body.sleepingPillAmount = body.sleepingPillAmount or 0
    body.sleepingPillWasSleeping = body.sleepingPillWasSleeping or false
    body.opiateAmount = body.opiateAmount or 0
    body.opiateReception = body.opiateReception or 0
    body.actualOpiateReception = body.actualOpiateReception or 0
    body.opiateTolerance = body.opiateTolerance or 0
    body.antagonistAmount = body.antagonistAmount or 0
    body.dirtyness = body.dirtyness or 0
    body.traumaAmount = body.traumaAmount or 0
    body.clawHealth = body.clawHealth or 100
    body.clawRegrowTime = body.clawRegrowTime or 0
    body.caffeinated = body.caffeinated or 0
    body.badSleepAmount = body.badSleepAmount or 0
    body.venomCurrent = body.venomCurrent or 0
    body.overdoseIndex = body.overdoseIndex or 0
    body.painShock = body.painShock or 0
    body.bloodVomitTime = body.bloodVomitTime or 0
    body.bloodVomiting = body.bloodVomiting or false
    body.vomitTime = body.vomitTime or 0
    body.vomiting = body.vomiting or false
    body.vomitPower = body.vomitPower or 0
    body.badLookAmount = body.badLookAmount or 0
    body.specialCryingUntil = body.specialCryingUntil or 0
    body.totalBleedSpeed = body.totalBleedSpeed or 0
    body.hearingLoss = body.hearingLoss or 0
    body.hasPulmonaryEmbolism = body.hasPulmonaryEmbolism or false
    body.bloodVesselSize = body.bloodVesselSize or 1
    body.radiationExposureTimer = body.radiationExposureTimer or 0
    body.strokeAmount = body.strokeAmount or 0
    body.sleeping = body.sleeping or false
    body.disfigured = body.disfigured or false
    body.eyeGone = body.eyeGone or false
    body.bothEyesGone = body.bothEyesGone or false
    body.onHardStimulants = body.onHardStimulants or false
    body.stimulantMultiplier = body.stimulantMultiplier or 0
    body.impairedSpeech = body.impairedSpeech or false
    body.mindWipe = body.mindWipe or false
    body.lastStandTime = body.lastStandTime or 0
    body.focusedLevel = body.focusedLevel or 0
    body.horrifiedLevel = body.horrifiedLevel or 0
    body.overEncumberance = body.overEncumberance or 0
    body.brainGrowSickness = body.brainGrowSickness or 0
    body.temporarySlowdown = body.temporarySlowdown or 0
    body.bloodPressureChangeFromMedicine = body.bloodPressureChangeFromMedicine or 0
    body.antibioticImmunityTime = body.antibioticImmunityTime or 0
    body.timedBodyEffects = body.timedBodyEffects or {}
    if WoundSystem.Skills and WoundSystem.Skills.AttachToBody then
        WoundSystem.Skills.AttachToBody(ply, body)
    elseif not body.skills and WoundSystem.Skills and WoundSystem.Skills.CreateDefault then
        body.skills = WoundSystem.Skills.CreateDefault()
    end

    if IsValid(ply) then
        ply:SetNWFloat("BrainHealth", body.brainHealth)
        ply:SetNWFloat("Consciousness", body.consciousness)
        ply:SetNWBool("WoundSystemUnconscious", body.unconscious)
    end
end

local function UpdateOpiateState(ply, body, dt, limbs)
    if not body then return 0 end

    body.antagonistAmount = math.max((body.antagonistAmount or 0) - dt, 0)
    body.opiateAmount = math.max(body.opiateAmount or 0, 0)
    body.opiateTolerance = math.max(body.opiateTolerance or 0, 0)

    body.opiateReception = (body.opiateAmount or 0) - (body.opiateTolerance or 0)
    body.actualOpiateReception = math.Approach(body.actualOpiateReception or 0, body.opiateReception or 0, dt * 5)

    if (body.opiateTolerance or 0) < (body.opiateAmount or 0) then
        body.opiateTolerance = math.Approach(body.opiateTolerance or 0, body.opiateAmount or 0, dt * 0.08)
    else
        body.opiateTolerance = math.Approach(body.opiateTolerance or 0, body.opiateAmount or 0, dt * 0.04)
    end

    if (body.opiateReception or 0) > 45 then
        body.opiateTolerance = math.Approach(body.opiateTolerance or 0, body.opiateAmount or 0, dt * 0.022)
    end

    if (body.opiateReception or 0) < -30 then
        body.opiateTolerance = math.Approach(body.opiateTolerance or 0, body.opiateAmount or 0, dt * 0.025)
    end

    body.opiateTolerance = math.max(body.opiateTolerance or 0, 0)

    local function DecayOpiateAmount(rate)
        body.opiateAmount = math.Approach(body.opiateAmount or 0, 0, dt * rate)
    end

    DecayOpiateAmount(0.059)
    if (body.opiateAmount or 0) > 100 then DecayOpiateAmount(0.05) end
    if (body.opiateAmount or 0) > 130 then DecayOpiateAmount(0.07) end
    if (body.opiateAmount or 0) > 160 then DecayOpiateAmount(0.09) end
    if (body.opiateAmount or 0) > 195 then DecayOpiateAmount(0.11) end
    if (body.opiateAmount or 0) > 235 then DecayOpiateAmount(0.13) end
    if (body.opiateAmount or 0) > 260 then DecayOpiateAmount(0.15) end
    if (body.opiateAmount or 0) > 300 then DecayOpiateAmount(0.18) end
    if (body.antagonistAmount or 0) > 0 then DecayOpiateAmount(8) end

    local actual = body.actualOpiateReception or 0
    if actual > 0 and limbs then
        for _, state in pairs(limbs) do
            state.pain = math.max(0, (state.pain or 0) - dt * (actual * 0.3))
        end
    end

    if actual > 0 then
        body.opiateHappiness = actual
    else
        body.opiateHappiness = math.max(actual * 1.66, -80)
    end

    if actual > 5 then
        local baseHappiness = body.happiness or 0
        if WoundSystemHappiness and WoundSystemHappiness.GetBase and IsValid(ply) then
            baseHappiness = WoundSystemHappiness.GetBase(ply)
        end

        if baseHappiness > -60 then
            local gain = dt * actual * 0.00003
            if WoundSystemHappiness and WoundSystemHappiness.Add and IsValid(ply) then
                WoundSystemHappiness.Add(ply, gain)
            else
                body.happiness = math.min(100, baseHappiness + gain)
            end
        end
    end

    if actual < -16 then
        body.sicknessAmount = math.Clamp((body.sicknessAmount or 0) + dt * 0.09, 0, 100)
    end

    if actual < -15 and body.sleeping and (body.sleepingPillAmount or 0) <= 0 then
        body.sleeping = false
    end

    if actual < -34 and (body.fibrillationProgress or 0) <= 0 then
        body.fibrillationProgress = 0.1
    end

    if (body.opiateAmount or 0) == 0 and (body.opiateTolerance or 0) == 0 then
        body.opiateHappiness = 0
    end

    return actual
end

GetBody = function(ply)
    if not BodyState[ply] then
        InitBody(ply)
    end
    EnsureBrainState(ply, BodyState[ply])
    return BodyState[ply]
end

local function GetGunshotOrigin(ent)
    if IsValid(ent) and ent.GetShootPos then
        return ent:GetShootPos()
    end
    if IsValid(ent) and ent.EyePos then
        return ent:EyePos()
    end
    if IsValid(ent) and ent.WorldSpaceCenter then
        return ent:WorldSpaceCenter()
    end
    return nil
end

local function GetGunshotHearingGain(ent, bulletData)
    bulletData = bulletData or {}

    local bulletDamage = tonumber(bulletData.Damage) or 0
    local weaponDamage = 0
    local weapon = IsValid(ent) and ent.GetActiveWeapon and ent:GetActiveWeapon() or nil
    if IsValid(weapon) and weapon.Primary then
        weaponDamage = tonumber(weapon.Primary.Damage) or 0
    end

    local damage = math.max(bulletDamage, weaponDamage, 10)
    local pelletBonus = math.min(tonumber(bulletData.Num) or 1, 8) * 0.01
    local scale = WoundSystem.Health.Config.CvFloat(WoundSystem.Health.Config.CVars.GunshotHearingScale, 1)
    return math.Clamp(0.08 + (damage * 0.006) + pelletBonus, 0.08, 0.55) * scale
end

local function PlayerCanReceiveGunshotHearingLoss(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false end
    local body = GetBody(ply)
    if not body or body.isGodMode then return false end
    return true, body
end

local function ApplyGunshotHearingLoss(shooter, origin, shooterGain)
    if not origin or shooterGain <= 0 then return end

    local shooterOk, shooterBody = PlayerCanReceiveGunshotHearingLoss(shooter)
    if shooterOk then
        Fn.AddHearingLoss(shooterBody, shooterGain)
    end

    local radius = math.max(WoundSystem.Health.Config.CvFloat(WoundSystem.Health.Config.CVars.GunshotHearingRadius, 1400), 0)
    if radius <= 0 then return end

    for _, ply in ipairs(player.GetAll()) do
        if ply ~= shooter then
            local ok, body = PlayerCanReceiveGunshotHearingLoss(ply)
            if ok then
                local dist = ply:WorldSpaceCenter():Distance(origin)
                local falloff = math.Clamp(1 - (dist / radius), 0, 1)
                local nearbyGain = shooterGain * 0.55 * falloff
                if nearbyGain >= 0.02 then
                    Fn.AddHearingLoss(body, nearbyGain)
                end
            end
        end
    end
end

hook.Add("EntityFireBullets", "WoundSystem_GunshotHearingLoss", function(ent, bulletData)
    if not WoundSystemHealthEnabled() then return end
    if not WoundSystem.Health.Config.CVars.GunshotHearingEnabled:GetBool() then return end
    if not IsValid(ent) or not ent:IsPlayer() then return end
    if not ent:Alive() then return end

    local origin = GetGunshotOrigin(ent)
    local gain = GetGunshotHearingGain(ent, bulletData)
    ApplyGunshotHearingLoss(ent, origin, gain)
end)

local function ProcessImpactDamage(ply, limb, force)
    local body = GetBody(ply)
    local state = PlayerLimbs[ply] and PlayerLimbs[ply][limb]
    if not body or body.isGodMode then return end
    if not state then return end
    force = tonumber(force) or 0

    -- C:U passes limb collision force directly into ImpactDamage. Keep this
    -- unamplified; Source speeds are converted by the caller before this point.
    local jumpSpeed = (body and body.jumpSpeed) and body.jumpSpeed or 6.5
    if force <= jumpSpeed then return end

    local armorReduction = 1.0

    -- muscleHealth -= force * 0.33 / armorReduction
    local muscleDamage = (force * 0.33) / armorReduction
    state.muscle = math.Clamp(state.muscle - muscleDamage, 0, 100)

    -- pain += force * 0.4 / armorReduction
    state.pain = math.Clamp(state.pain + (force * 0.4) / armorReduction, 0, 100)

    -- body.adrenaline += force * 0.075 / armorReduction
    body.adrenaline = math.Clamp((body.adrenaline or 0) + (force * 0.075) / armorReduction, 0, 100)

    -- body.shock += force * 0.05 / armorReduction
    Fn.AddBodyShock(body, (force * 0.05) / armorReduction)

    -- skinHealth checks
    local muscleFactor = (state.muscle < 50) and 0.632 or 1.0
    local skinCheckThreshold = math.Rand(jumpSpeed * 1.55, jumpSpeed * 4.4) * muscleFactor
    if force > skinCheckThreshold then
        local skinDamage = (force * 0.33) / armorReduction
        state.skin = math.Clamp(state.skin - skinDamage, 0, 100)

        if force > jumpSpeed * 2.6 then
            local randBleed = math.Rand(state.bleed, (100 - state.skin) * 0.4)
            state.bleed = math.max(state.bleed, randBleed)
            Fn.ClearLimbBandage(state)
        end
    end

    -- dislocation check
    local structuralMultiplier = math.Clamp(((state.muscle or 100) * 0.01) + 0.5, 0, 1)
    local dislocateThreshold = math.Rand(jumpSpeed * 3.5, jumpSpeed * 5.0) * structuralMultiplier
    if force > dislocateThreshold then
        ApplyDislocation(ply, limb, state)
        state.pain = math.Clamp(state.pain + math.Rand(40, 80), 0, 100)
        body.adrenaline = math.Clamp((body.adrenaline or 0) + 75, 0, 100)
    end

    -- fracture check
    local fractureThreshold = math.Rand(jumpSpeed * 4.0, jumpSpeed * 7.0) * structuralMultiplier
    if force > fractureThreshold then
        ApplyFracture(ply, limb, state)
        state.skin = math.Clamp(state.skin - 33, 0, 100)
        state.bleed = math.Clamp(state.bleed + math.Rand(0, 20), 0, 100)
        state.pain = math.Clamp(state.pain + math.Rand(60, 100), 0, 100)
        body.adrenaline = math.Clamp((body.adrenaline or 0) + 80, 0, 100)
        body.internalBleeding = (body.internalBleeding or 0) + (Fn.IsCriticalLimb(limb) and 34 or 10)
    end

    -- internal bleeding check for vitals/head
    if (Fn.IsCriticalLimb(limb)) and force > jumpSpeed * 2.0 and math.Rand(0, 1) < 0.66 then
        body.internalBleeding = (body.internalBleeding or 0) + (force * 0.22) / armorReduction
    end

    -- head specific damage
    if limb == "head" then
        body.consciousness = math.Clamp((body.consciousness or 100) - (force * 1.6) / armorReduction, 0, 100)
        if force > jumpSpeed * 1.8 then
            body.brainHealth = math.Clamp((body.brainHealth or 100) - (force * 0.04) / armorReduction, 0, 100)
        end
        if force > jumpSpeed * 3.2 then
            body.brainHealth = math.Clamp((body.brainHealth or 100) - (force * 0.12) / armorReduction, 0, 100)
        end
        if force > jumpSpeed * 0.5 and math.Rand(0, 1) < 0.25 then
            body.brainHealth = math.Clamp((body.brainHealth or 100) - (force * 0.025) / armorReduction, 0, 100)
        end
    end

    hook.Run("WoundSystem_OnImpact", ply, limb, force)

    SendLimbUpdate(ply, limb, true)
    SendCardioUpdate(ply, true)
end

function WoundSystemDebugSetHemothorax(ply, amount)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local body = GetBody(ply)
    body.hemothorax = math.Clamp(tonumber(amount) or 100, 0, 100)
    SendCardioUpdate(ply)
end

local function NextRagdollStateSeq(ply)
    ply.WoundSystemRagdollStateSeq = ((ply.WoundSystemRagdollStateSeq or 0) + 1) % 16777216
    if ply.WoundSystemRagdollStateSeq <= 0 then
        ply.WoundSystemRagdollStateSeq = 1
    end

    return ply.WoundSystemRagdollStateSeq
end

WoundSystem.Health.BumpLifecycleSeq = function(ply)
    ply.WoundSystemLifecycleSeq = ((ply.WoundSystemLifecycleSeq or 0) + 1) % 16777216
    if ply.WoundSystemLifecycleSeq <= 0 then
        ply.WoundSystemLifecycleSeq = 1
    end

    return ply.WoundSystemLifecycleSeq
end

WoundSystem.Health.GetLifecycleSeq = function(ply)
    if not IsValid(ply) then return 0 end
    return ply.WoundSystemLifecycleSeq or 0
end

local function SendRagdollState(ply, active, ragdoll, seqOverride)
    if not IsValid(ply) then return end

    net.Start("WoundSystem_RagdollState")
        net.WriteUInt(seqOverride or NextRagdollStateSeq(ply), 24)
        net.WriteBool(active == true)
        net.WriteEntity(IsValid(ragdoll) and ragdoll or NULL)
        net.WriteUInt(WoundSystem.Health.GetLifecycleSeq(ply), 24)
    net.Send(ply)
end

local function SendUnconsciousRagdoll(ply, ragdoll)
    if not IsValid(ply) then return end

    ply:SetNWEntity("WoundSystemUnconsciousRagdoll", IsValid(ragdoll) and ragdoll or NULL)

    net.Start("WoundSystem_UnconsciousRagdoll")
        net.WriteEntity(IsValid(ragdoll) and ragdoll or NULL)
        net.WriteUInt(WoundSystem.Health.GetLifecycleSeq(ply), 24)
    net.Send(ply)

    SendRagdollState(ply, IsValid(ragdoll), ragdoll)
end

local function ResetPlayerRagdollCamera(ply)
    if not IsValid(ply) then return end

    ply:SetNWEntity("WoundSystemUnconsciousRagdoll", NULL)
    ply:SetNWBool("WoundSystemUnconscious", false)
    ply:SetNoDraw(false)
    ply:DrawShadow(true)
    ply:SetNotSolid(false)
    ply:Freeze(false)

    if ply:GetMoveType() == MOVETYPE_NONE or ply:GetMoveType() == MOVETYPE_OBSERVER then
        ply:SetMoveType(MOVETYPE_WALK)
    end

    if ply.ResetHull then
        ply:ResetHull()
    end

    if ply.UnDuck then
        ply:UnDuck()
    end

    if ply.SetViewEntity then
        ply:SetViewEntity(ply)
    end

    local resetSeq = NextRagdollStateSeq(ply)
    net.Start("WoundSystem_ResetRagdollCamera")
        net.WriteUInt(resetSeq, 24)
        net.WriteUInt(WoundSystem.Health.GetLifecycleSeq(ply), 24)
    net.Send(ply)

    SendRagdollState(ply, false, nil, resetSeq)
end

function WoundSystem.Health.IsLiveUnconsciousRagdollProxy(ragdoll, owner, body)
    if not IsValid(ragdoll) then return false end

    if not IsValid(owner) and ragdoll.GetNWEntity then
        owner = ragdoll:GetNWEntity("WoundSystemOwner")
    end

    if not IsValid(owner) or not owner:IsPlayer() or not owner:Alive() then return false end
    if ragdoll.WoundSystemDeadUnconsciousBody or ragdoll:GetNWBool("WoundSystemDeadUnconsciousBody", false) then return false end

    body = body or (BodyState and BodyState[owner])
    if not body then return false end
    if body.diedWhileUnconscious or IsValid(body.deathRagdollOverride) then return false end
    if body.unconsciousRagdoll ~= ragdoll then return false end
    if owner:GetNWEntity("WoundSystemUnconsciousRagdoll") ~= ragdoll then return false end

    return body.unconscious == true or body.fallingRagdoll == true
end

function WoundSystem.Health.GetCurrentCharacter(ply)
    if not IsValid(ply) then return nil end

    local body = BodyState and BodyState[ply]
    local ragdoll = body and body.unconsciousRagdoll or ply:GetNWEntity("WoundSystemUnconsciousRagdoll")
    if WoundSystem.Health.IsLiveUnconsciousRagdollProxy(ragdoll, ply, body) then
        return ragdoll
    end

    local deathRagdoll = ply:GetNWEntity("WoundSystemDeathRagdoll")
    if IsValid(deathRagdoll) then
        return deathRagdoll
    end

    return ply
end
WoundSystem.GetCurrentCharacter = WoundSystem.Health.GetCurrentCharacter

local function MakeRagdollNonCollidingWithActors(ragdoll)
    if not IsValid(ragdoll) then return end

    ragdoll.WoundSystemNoActorCollide = true
    ragdoll:SetCollisionGroup(COLLISION_GROUP_WEAPON)

    for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:EnableCollisions(true)
            phys:Wake()
        end
    end
end

function WoundSystem.Health.SetUnconsciousRagdollPhysicsFrozen(ragdoll, frozen)
    if not IsValid(ragdoll) then return end

    ragdoll.WoundSystemPhysicsFrozen = frozen == true

    for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:EnableMotion(true)
            if frozen then
                phys:SetVelocity(Vector(0, 0, 0))
                if phys.SetAngleVelocity then
                    phys:SetAngleVelocity(Vector(0, 0, 0))
                end
                phys:Sleep()
            else
                phys:Wake()
            end
        end
    end
end

function WoundSystem.Health.WakeUnconsciousRagdollPhysics(ragdoll)
    if not IsValid(ragdoll) or not ragdoll.WoundSystemPhysicsFrozen then return end

    WoundSystem.Health.SetUnconsciousRagdollPhysicsFrozen(ragdoll, false)
end

local function DisableRagdollForPlayerRestore(ragdoll)
    if not IsValid(ragdoll) then return end

    WoundSystem.Health.SetUnconsciousRagdollPhysicsFrozen(ragdoll, false)
    ragdoll:SetNotSolid(true)
    ragdoll:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

    for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:EnableCollisions(false)
            phys:SetVelocity(Vector(0, 0, 0))
            if phys.SetAngleVelocity then
                phys:SetAngleVelocity(Vector(0, 0, 0))
            end
            phys:Sleep()
        end
    end
end

function WoundSystem.Health.DetachWakeBridgeRagdoll(ragdoll)
    if not IsValid(ragdoll) then return end

    ragdoll.WoundSystemUnconsciousRagdoll = false
    ragdoll.WoundSystemDeadUnconsciousBody = false
    ragdoll.WoundSystemWakeBridgeRagdoll = true
    ragdoll.WoundSystemOwner = nil
    ragdoll:SetNWEntity("WoundSystemOwner", NULL)
    ragdoll:SetNWBool("WoundSystemUnconsciousRagdoll", false)
    ragdoll:SetNWBool("WoundSystemDeadUnconsciousBody", false)
    ragdoll:SetNWBool("WoundSystemWakeBridgeRagdoll", true)

    if ragdoll.SetOwner then
        ragdoll:SetOwner(NULL)
    end

    if ragdoll:IsOnFire() then
        ragdoll:Extinguish()
    end
end

function WoundSystem.Health.BridgeRagdollForPlayerRestore(ply, ragdoll)
    if not IsValid(ragdoll) then return end

    WoundSystem.Health.DetachWakeBridgeRagdoll(ragdoll)
    DisableRagdollForPlayerRestore(ragdoll)

    local duration = tonumber(WoundSystem.Health.Constants.RagdollWakeBridgeDuration) or 0.75
    if duration <= 0 then
        ragdoll:Remove()
        return
    end

    if ragdoll.SetRenderMode then
        ragdoll:SetRenderMode(RENDERMODE_TRANSALPHA)
    end

    local baseColor = ragdoll:GetColor()
    local timerName = "WoundSystem_WakeBridge_" .. ragdoll:EntIndex()
    local started = CurTime()
    timer.Remove(timerName)
    timer.Create(timerName, 0.05, 0, function()
        if not IsValid(ragdoll) then
            timer.Remove(timerName)
            return
        end

        local fraction = math.Clamp((CurTime() - started) / duration, 0, 1)
        local alpha = math.floor((baseColor.a or 255) * 0.7 * (1 - fraction))
        ragdoll:SetColor(Color(baseColor.r or 255, baseColor.g or 255, baseColor.b or 255, alpha))

        if fraction >= 1 then
            timer.Remove(timerName)
            ragdoll:Remove()
        end
    end)
end

local function HideUnconsciousPlayerBody(ply)
    if not IsValid(ply) then return end

    ply:SetNoDraw(true)
    ply:DrawShadow(false)
    ply:SetNotSolid(true)
    ply:Freeze(true)
    ply:SetMoveType(MOVETYPE_NONE)
    ply:SetLocalVelocity(Vector(0, 0, 0))

    local activeWep = ply:GetActiveWeapon()
    if IsValid(activeWep) then
        activeWep:SetNoDraw(true)
    end

    for _, child in pairs(ply:GetChildren()) do
        if child:GetClass() == "prop_physics" or child:GetClass() == "base_gmodentity" then
            child:SetNoDraw(true)
        end
    end
end

function WoundSystem.Health.StartWakeCollisionGrace(ply)
    if not IsValid(ply) then return end

    local duration = tonumber(WoundSystem.Health.Constants.RagdollWakeCollisionGraceDuration) or 1.1
    if duration <= 0 then return end

    local timerName = "WoundSystem_WakeCollisionGrace_" .. ply:EntIndex()
    local oldGroup = ply.WoundSystemPreWakeCollisionGroup
    if oldGroup == nil then
        oldGroup = ply:GetCollisionGroup()
        ply.WoundSystemPreWakeCollisionGroup = oldGroup
    end

    ply.WoundSystemWakeCollisionGraceUntil = math.max(ply.WoundSystemWakeCollisionGraceUntil or 0, CurTime() + duration)
    ply:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)

    if ply.CollisionRulesChanged then
        ply:CollisionRulesChanged()
    end

    timer.Remove(timerName)
    timer.Create(timerName, tonumber(WoundSystem.Health.Constants.RagdollWakeCollisionGracePoll) or 0.1, 0, function()
        if not IsValid(ply) then
            timer.Remove(timerName)
            return
        end

        local now = CurTime()
        local graceUntil = ply.WoundSystemWakeCollisionGraceUntil or 0
        local body = BodyState and BodyState[ply]
        if now < graceUntil and body and (body.unconscious or body.fallingRagdoll or IsValid(body.unconsciousRagdoll)) then
            return
        end

        if now < graceUntil then
            local wakePositions = WoundSystem.Health and WoundSystem.Health.WakePositions
            if wakePositions and wakePositions.IsPlayerWakePosClear and not wakePositions.IsPlayerWakePosClear(ply, nil, ply:GetPos()) then
                return
            end
        end

        timer.Remove(timerName)
        ply:SetCollisionGroup(ply.WoundSystemPreWakeCollisionGroup or COLLISION_GROUP_PLAYER)
        ply.WoundSystemPreWakeCollisionGroup = nil
        ply.WoundSystemWakeCollisionGraceUntil = nil

        if ply.CollisionRulesChanged then
            ply:CollisionRulesChanged()
        end
    end)
end

local function SetPlayerWakePosition(ply, pos)
    if not IsValid(ply) or not pos then return end

    ply:SetPos(pos)
    ply:SetLocalVelocity(Vector(0, 0, 0))

    if ply.ResetHull then
        ply:ResetHull()
    end

    if ply.SetGroundEntity then
        ply:SetGroundEntity(NULL)
    end

    if ply.UnDuck then
        ply:UnDuck()
    end
end

local function GetUnconsciousRagdollBodyAnchor(ragdoll)
    if not IsValid(ragdoll) then return nil end

    local now = CurTime()
    if ragdoll.WoundSystemCachedBodyAnchor and now < (ragdoll.WoundSystemNextBodyAnchorAt or 0) then
        return ragdoll.WoundSystemCachedBodyAnchor
    end

    local wakePositions = WoundSystem.Health and WoundSystem.Health.WakePositions
    local pelvisPos = wakePositions and wakePositions.GetRagdollPelvisPos and wakePositions.GetRagdollPelvisPos(ragdoll) or nil
    if pelvisPos then
        ragdoll.WoundSystemCachedBodyAnchor = pelvisPos
        ragdoll.WoundSystemNextBodyAnchorAt = now + 0.12
        return pelvisPos
    end

    local headPos = wakePositions and wakePositions.GetRagdollHeadPos and wakePositions.GetRagdollHeadPos(ragdoll) or nil
    if headPos then
        ragdoll.WoundSystemCachedBodyAnchor = headPos
        ragdoll.WoundSystemNextBodyAnchorAt = now + 0.12
        return headPos
    end

    if ragdoll.WorldSpaceCenter then
        local pos = ragdoll:WorldSpaceCenter()
        ragdoll.WoundSystemCachedBodyAnchor = pos
        ragdoll.WoundSystemNextBodyAnchorAt = now + 0.12
        return pos
    end

    local pos = ragdoll:GetPos()
    ragdoll.WoundSystemCachedBodyAnchor = pos
    ragdoll.WoundSystemNextBodyAnchorAt = now + 0.12
    return pos
end

local function NormalizeWakeMoveType(moveType)
    if type(moveType) ~= "number" then return MOVETYPE_WALK end
    if moveType == MOVETYPE_NOCLIP or moveType == MOVETYPE_NONE or moveType == MOVETYPE_OBSERVER then
        return MOVETYPE_WALK
    end

    return moveType
end

local function RefreshPlayerWakeMovement(ply, moveType, skipDropToFloor)
    if not IsValid(ply) then return end

    ply:SetNotSolid(false)

    if ply.CollisionRulesChanged then
        ply:CollisionRulesChanged()
    end

    ply:Freeze(false)
    ply:SetMoveType(NormalizeWakeMoveType(moveType))
    ply:SetLocalVelocity(Vector(0, 0, 0))

    if ply.ResetHull then
        ply:ResetHull()
    end

    if ply.UnDuck then
        ply:UnDuck()
    end

    if ply.SetGroundEntity then
        ply:SetGroundEntity(NULL)
    end

    if not skipDropToFloor and ply.DropToFloor then
        ply:DropToFloor(MASK_PLAYERSOLID, nil, 64)
    end
end

local function SchedulePostWakePositionCheck(ply, desiredPos, wakeAng)
    if not IsValid(ply) then return end

    local wakeMoveType = NormalizeWakeMoveType(ply:GetMoveType())
    local delays = {0.15, 0.35}

    for _, delay in ipairs(delays) do
        timer.Simple(delay, function()
            if not IsValid(ply) or not ply:Alive() then return end

            local body = BodyState and BodyState[ply]
            if body and (body.unconscious or body.fallingRagdoll or IsValid(body.unconsciousRagdoll)) then return end

            RefreshPlayerWakeMovement(ply, wakeMoveType, true)

            local wakePositions = WoundSystem.Health and WoundSystem.Health.WakePositions
            if not wakePositions then return end

            if wakePositions.IsPlayerWakePosClear and wakePositions.IsPlayerWakePosClear(ply, nil, ply:GetPos()) then
                return
            end

            local safePos = wakePositions.FindSafePlayerWakePos and wakePositions.FindSafePlayerWakePos(ply, nil, desiredPos or ply:GetPos(), {
                anchorPos = desiredPos or ply:GetPos(),
                maxDistance = 96,
                preferClosest = false,
                includePlayerBase = false
            })
            if safePos then
                SetPlayerWakePosition(ply, safePos)

                if wakeAng then
                    ply:SetEyeAngles(Angle(math.Clamp(wakeAng.p or 0, -30, 30), wakeAng.y, 0))
                end
            end
        end)
    end
end

local function GetSafeUnconsciousMoveOrigin(ply, body)
    if not IsValid(ply) or not body then return nil end

    local ragdoll = body.unconsciousRagdoll
    local now = CurTime()
    if body.cachedUnconsciousMoveOrigin and (body.nextUnconsciousMoveOriginCheck or 0) > now then
        return body.cachedUnconsciousMoveOrigin
    end

    body.nextUnconsciousMoveOriginCheck = now + 0.35

    local desiredPos = GetUnconsciousRagdollBodyAnchor(ragdoll)
    desiredPos = desiredPos or body.ragdollWakePos or ply:GetPos()
    body.ragdollWakePos = desiredPos

    local wakePositions = WoundSystem.Health and WoundSystem.Health.WakePositions
    local safePos = wakePositions and wakePositions.FindSafePlayerWakePos and wakePositions.FindSafePlayerWakePos(ply, ragdoll, desiredPos, {
        anchorPos = desiredPos,
        maxDistance = 96,
        preferClosest = false,
        includePlayerBase = false
    })
    body.cachedUnconsciousMoveOrigin = safePos or desiredPos or body.cachedUnconsciousMoveOrigin or ply:GetPos()
    return body.cachedUnconsciousMoveOrigin
end

function WoundSystem.Health.FindRecoveryWakeFallback(ply, body, ragdoll, desiredWakePos)
    if not IsValid(ply) or not body then return nil end

    local wakePositions = WoundSystem.Health and WoundSystem.Health.WakePositions
    if not wakePositions then return nil end

    local now = CurTime()
    body.ragdollRestoreRetryStarted = body.ragdollRestoreRetryStarted or now
    body.ragdollRestoreRetryCount = (body.ragdollRestoreRetryCount or 0) + 1

    local anchorPos = body.cachedUnconsciousMoveOrigin or ply:GetPos()
    local safePos = wakePositions.FindSafePlayerWakePos and wakePositions.FindSafePlayerWakePos(ply, ragdoll, desiredWakePos or anchorPos, {
        anchorPos = anchorPos,
        maxDistance = 256,
        maxVerticalDistance = 192,
        preferClosest = false,
        includePlayerBase = true
    })
    if safePos then return safePos end

    if (now - (body.ragdollRestoreRetryStarted or now)) < 1.25 and (body.ragdollRestoreRetryCount or 0) < 6 then
        return nil
    end

    if wakePositions.IsPlayerWakePosClear and wakePositions.IsPlayerWakePosClear(ply, nil, anchorPos) then
        return anchorPos
    end

    local playerPos = ply:GetPos()
    if wakePositions.IsPlayerWakePosClear and wakePositions.IsPlayerWakePosClear(ply, nil, playerPos) then
        return playerPos
    end

    return wakePositions.FindSafePlayerWakePos and wakePositions.FindSafePlayerWakePos(ply, nil, playerPos, {
        anchorPos = playerPos,
        maxDistance = 256,
        maxVerticalDistance = 192,
        preferClosest = false,
        includePlayerBase = true
    }) or playerPos
end

function WoundSystem.Health.ResolveAttributionActor(ent)
    if not IsValid(ent) then return nil end
    if ent:IsPlayer() or ent:IsNPC() then return ent end

    local owner
    if ent.CPPIGetOwner then
        owner = ent:CPPIGetOwner()
        if IsValid(owner) and (owner:IsPlayer() or owner:IsNPC()) then return owner end
    end

    if ent.GetOwner then
        owner = ent:GetOwner()
        if IsValid(owner) and (owner:IsPlayer() or owner:IsNPC()) then return owner end
    end

    return nil
end

function WoundSystem.Health.RecordDamageAttribution(victim, body, dmginfo, hitRagdoll)
    if not IsValid(victim) or not body or not dmginfo then return end

    local attacker = WoundSystem.Health.ResolveAttributionActor(dmginfo:GetAttacker()) or WoundSystem.Health.ResolveAttributionActor(dmginfo:GetInflictor())
    if not IsValid(attacker) or attacker == victim then return end

    body.lastDamageAttacker = attacker
    body.lastDamageInflictor = IsValid(dmginfo:GetInflictor()) and dmginfo:GetInflictor() or attacker
    body.lastDamageType = dmginfo:GetDamageType() or DMG_GENERIC
    body.lastDamageTime = CurTime()
    body.lastDamageHitRagdoll = hitRagdoll == true
end

function WoundSystem.Health.GetRecentDamageAttribution(body)
    if not body or not IsValid(body.lastDamageAttacker) then return nil end
    if CurTime() - (body.lastDamageTime or 0) > WoundSystem.Health.DamageAttributionWindow then return nil end

    return body.lastDamageAttacker, (IsValid(body.lastDamageInflictor) and body.lastDamageInflictor or body.lastDamageAttacker), body.lastDamageType or DMG_GENERIC
end

function WoundSystem.Health.KillWithAttribution(ply, body, reason)
    if not IsValid(ply) or not ply:Alive() then return end

    local attacker, inflictor, damageType = WoundSystem.Health.GetRecentDamageAttribution(body)
    if IsValid(attacker) and attacker ~= ply then
        local dmg = DamageInfo()
        dmg:SetDamage(10000)
        dmg:SetDamageType(damageType or DMG_GENERIC)
        dmg:SetAttacker(attacker)
        dmg:SetInflictor(IsValid(inflictor) and inflictor or attacker)
        dmg:SetDamagePosition(ply:WorldSpaceCenter())
        dmg:SetDamageForce(Vector(0, 0, 0))

        ply._WoundSystemApplyingAttributedDeath = true
        ply._WoundSystemAttributedDeathReason = reason
        ply:TakeDamageInfo(dmg)
        ply._WoundSystemApplyingAttributedDeath = nil
        ply._WoundSystemAttributedDeathReason = nil

        if not ply:Alive() then return end
    end

    ply:Kill()
end

function WoundSystem.Health.IsDuplicateDeathRagdoll(ply, body, ragdoll)
    local preserved = body and ((IsValid(body.deathRagdollOverride) and body.deathRagdollOverride) or body.unconsciousRagdoll)
    if not IsValid(ply) or not body or not IsValid(preserved) or not IsValid(ragdoll) then return false end
    if ragdoll == preserved then return false end
    if ragdoll.WoundSystemUnconsciousRagdoll or ragdoll:GetNWBool("WoundSystemUnconsciousRagdoll", false) then return false end
    if ragdoll.WoundSystemDeadUnconsciousBody or ragdoll:GetNWBool("WoundSystemDeadUnconsciousBody", false) then return false end

    if ply.GetRagdollEntity and ragdoll == ply:GetRagdollEntity() then
        return true
    end

    local model = string.lower(preserved:GetModel() or ply:GetModel() or "")
    local ragClass = ragdoll:GetClass()
    local isVanillaDeathRagdoll = ragClass == "hl2mp_ragdoll"

    if not isVanillaDeathRagdoll and (model == "" or string.lower(ragdoll:GetModel() or "") ~= model) then return false end

    local ownerMatches = false
    if ragdoll.GetOwner and ragdoll:GetOwner() == ply then
        ownerMatches = true
    elseif ragdoll:GetNWEntity("WoundSystemOwner") == ply then
        ownerMatches = true
    end

    local radiusSqr = WoundSystem.Health.DeathRagdollCleanupRadiusSqr
    local ragCenter = ragdoll:WorldSpaceCenter()
    local center = preserved:WorldSpaceCenter()
    local nearPreserved = ragCenter:DistToSqr(center) <= radiusSqr
    local nearPlayer = ragCenter:DistToSqr(ply:WorldSpaceCenter()) <= radiusSqr
    local nearWake = body.ragdollWakePos and ragCenter:DistToSqr(body.ragdollWakePos) <= radiusSqr

    return ownerMatches or nearPreserved or nearPlayer or nearWake
end

function WoundSystem.Health.CleanupDuplicateDeathRagdolls(ply, body)
    local preserved = body and ((IsValid(body.deathRagdollOverride) and body.deathRagdollOverride) or body.unconsciousRagdoll)
    if not IsValid(ply) or not IsValid(preserved) then return end

    if ply.GetRagdollEntity then
        local deathRagdoll = ply:GetRagdollEntity()
        if WoundSystem.Health.IsDuplicateDeathRagdoll(ply, body, deathRagdoll) then
            deathRagdoll:Remove()
        end
    end

    for _, ragdoll in ipairs(ents.FindByClass("prop_ragdoll")) do
        if WoundSystem.Health.IsDuplicateDeathRagdoll(ply, body, ragdoll) then
            ragdoll:Remove()
        end
    end

    for _, ragdoll in ipairs(ents.FindByClass("hl2mp_ragdoll")) do
        if WoundSystem.Health.IsDuplicateDeathRagdoll(ply, body, ragdoll) then
            ragdoll:Remove()
        end
    end
end

function WoundSystem.Health.ScheduleDuplicateDeathRagdollCleanup(ply, body)
    if not IsValid(ply) or not body or not IsValid(body.unconsciousRagdoll) then return end

    body.deathRagdollCleanupUntil = CurTime() + WoundSystem.Health.DeathRagdollCleanupDuration
    local timerName = "WoundSystem_DeathRagdollCleanup_" .. ply:EntIndex()
    timer.Remove(timerName)
    timer.Create(timerName, 0.1, math.ceil(WoundSystem.Health.DeathRagdollCleanupDuration / 0.1) + 1, function()
        if not IsValid(ply) then
            timer.Remove(timerName)
            return
        end

        local currentBody = BodyState[ply]
        local preserved = currentBody and ((IsValid(currentBody.deathRagdollOverride) and currentBody.deathRagdollOverride) or currentBody.unconsciousRagdoll)
        if not currentBody or not IsValid(preserved) then
            timer.Remove(timerName)
            return
        end

        WoundSystem.Health.CleanupDuplicateDeathRagdolls(ply, currentBody)
    end)
end

hook.Add("OnEntityCreated", "WoundSystem_RemoveDelayedDuplicateDeathRagdoll", function(ent)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ent) then return end
    local class = ent:GetClass()
    if class ~= "prop_ragdoll" and class ~= "hl2mp_ragdoll" then return end

    timer.Simple(0, function()
        if not IsValid(ent) then return end

        for ply, body in pairs(BodyState or {}) do
            if IsValid(ply)
                and body
                and body.diedWhileUnconscious
                and (body.deathRagdollCleanupUntil or 0) >= CurTime()
                and WoundSystem.Health.IsDuplicateDeathRagdoll(ply, body, ent) then
                SafeRemoveEntityDelayed(ent, 0)
                return
            end
        end
    end)
end)

local SnapshotCorpseVisualState

local function PreserveUnconsciousRagdollForDeath(ply, body)
    if not IsValid(ply) or not body then return false end
    -- Z-City turns its own fake ragdoll into the death ragdoll (DoPlayerDeath), nothing to preserve here.
    if WoundSystemBridgeActive() then return false end

    local ragdoll = body.unconsciousRagdoll
    if not IsValid(ragdoll) then return false end

    body.diedWhileUnconscious = true
    body.deathRagdollOverride = ragdoll
    body.unconscious = true
    body.fallingRagdoll = false
    body.fallingRagdollWakeTime = nil
    body.fallingRagdollReason = "dead"

    HideUnconsciousPlayerBody(ply)
    MakeRagdollNonCollidingWithActors(ragdoll)

    ragdoll.WoundSystemDeadUnconsciousBody = true
    ragdoll.WoundSystemUnconsciousRagdoll = false
    ragdoll.WoundSystemOwner = ply
    ragdoll:SetNWEntity("WoundSystemOwner", ply)
    ragdoll:SetNWBool("WoundSystemDeadUnconsciousBody", true)
    ragdoll:SetNWBool("WoundSystemUnconsciousRagdoll", false)
    if WoundSystem.RagdollVisuals and WoundSystem.RagdollVisuals.CopyFromPlayer then
        WoundSystem.RagdollVisuals.CopyFromPlayer(ply, ragdoll)
    end
    SnapshotCorpseVisualState(ply, ragdoll)

    SendUnconsciousRagdoll(ply, ragdoll)
    WoundSystem.Health.ScheduleDuplicateDeathRagdollCleanup(ply, body)
    return true
end

SnapshotCorpseVisualState = function(ply, ragdoll)
    if not IsValid(ply) or not IsValid(ragdoll) then return end

    local furBlood = ply:GetNWFloat("WoundSystemFurBlood", 0)
    if math.abs(ragdoll:GetNWFloat("WoundSystemFurBlood", 0) - furBlood) > 0.001 then
        ragdoll:SetNWFloat("WoundSystemFurBlood", furBlood)
    end

    for _, region in ipairs(WoundSystem.Health.Constants.FurBloodRegions) do
        local key = "WoundSystemFurBlood_" .. region
        local amount = ply:GetNWFloat(key, 0)
        if math.abs(ragdoll:GetNWFloat(key, 0) - amount) > 0.001 then
            ragdoll:SetNWFloat(key, amount)
        end
    end

    local limbs = PlayerLimbs and PlayerLimbs[ply]
    if limbs then
        for limbName, state in pairs(limbs) do
            local key = "WoundSystemDismembered_" .. limbName
            local dismembered = state and state.dismembered == true or false
            if ragdoll:GetNWBool(key, false) ~= dismembered then
                ragdoll:SetNWBool(key, dismembered)
            end
        end
    end
end

local function RestorePlayerFromUnconsciousRagdoll(ply, body, keepRagdoll, preserveCurrentTransform)
    if not IsValid(ply) then return end
    local WB = WoundSystemBridgeActive()
    if WB then return WB.RestoreRagdoll(ply, body, keepRagdoll, preserveCurrentTransform) end
    local debugWakePerf = GetConVar("woundsys_wake_perf_debug")
    local wakePerfEnabled = debugWakePerf and debugWakePerf:GetBool()
    local restoreStarted = wakePerfEnabled and SysTime() or 0

    local ragdoll = body and body.unconsciousRagdoll
    if IsValid(ragdoll) then
        body.ragdollWakePos = GetUnconsciousRagdollBodyAnchor(ragdoll) or ragdoll:GetPos()
        body.ragdollWakeAng = body.ragdollWakeAng or (WoundSystem.Health.WakePositions.GetRandomWakeEyeAngles and WoundSystem.Health.WakePositions.GetRandomWakeEyeAngles(ragdoll)) or Angle(0, math.Rand(-180, 180), 0)
    end

    local finalWakePos
    local finalWakeAng

    if body and not preserveCurrentTransform then
        local wakePositions = WoundSystem.Health and WoundSystem.Health.WakePositions
        local desiredWakePos = body.ragdollWakePos or (IsValid(ragdoll) and ragdoll:GetPos()) or ply:GetPos()
        local wakePos = wakePositions and wakePositions.FindSafePlayerWakePos and wakePositions.FindSafePlayerWakePos(ply, ragdoll, desiredWakePos, {
            anchorPos = desiredWakePos,
            maxDistance = 96,
            preferClosest = false,
            includePlayerBase = false
        }) or nil
        local wakeAng = body.ragdollWakeAng

        if not wakePos and WoundSystem.Health.FindRecoveryWakeFallback then
            wakePos = WoundSystem.Health.FindRecoveryWakeFallback(ply, body, ragdoll, desiredWakePos)
        end

        if not wakePos and IsValid(ragdoll) and ply:Alive() then
            body.ragdollWakePos = desiredWakePos
            body.fallingRagdoll = true
            body.fallingRagdollWakeTime = CurTime() + 0.25
            body.fallingRagdollReason = body.fallingRagdollReason or "recovery"
            return false
        end

        wakePos = wakePos or desiredWakePos
        if wakePos then
            body.ragdollWakePos = wakePos
            SetPlayerWakePosition(ply, wakePos)
            finalWakePos = wakePos
        end

        if wakeAng then
            ply:SetEyeAngles(Angle(math.Clamp(wakeAng.p or 0, -30, 30), wakeAng.y, 0))
            finalWakeAng = wakeAng
        end
    end

    if IsValid(ragdoll) and not keepRagdoll then
        WoundSystem.Health.BridgeRagdollForPlayerRestore(ply, ragdoll)
    end

    if body then
        body.fallingRagdoll = nil
        body.fallingRagdollWakeTime = nil
        body.fallingRagdollReason = nil
        body.ragdollRestoreRetryStarted = nil
        body.ragdollRestoreRetryCount = nil
    end

    local wakeMoveType = NormalizeWakeMoveType(body and body.savedMoveType or MOVETYPE_WALK)

    ply:SetNoDraw(false)
    ply:DrawShadow(true)
    ply:SetNWEntity("WoundSystemUnconsciousRagdoll", NULL)

    if finalWakePos then
        SetPlayerWakePosition(ply, finalWakePos)
    end

    RefreshPlayerWakeMovement(ply, wakeMoveType, finalWakePos ~= nil)
    WoundSystem.Health.StartWakeCollisionGrace(ply)

    local activeWep = ply:GetActiveWeapon()
    if IsValid(activeWep) then
        activeWep:SetNoDraw(false)
    end

    for _, child in pairs(ply:GetChildren()) do
        if child:GetClass() == "prop_physics" or child:GetClass() == "base_gmodentity" then
            child:SetNoDraw(false)
        end
    end

    if body then
        body.unconsciousRagdoll = nil
        body.cachedUnconsciousMoveOrigin = nil
        body.nextUnconsciousMoveOriginCheck = nil
        body.nextHiddenPlayerRagdollPinAt = nil
        body.diedWhileUnconscious = nil
        body.deathRagdollOverride = nil
        body.deathRagdollCleanupUntil = nil
        body.ragdollWakePos = nil
        body.ragdollWakeAng = nil
        body.savedMoveType = nil
        body.fallingRagdoll = nil
        body.fallingRagdollWakeTime = nil
        body.fallingRagdollReason = nil
        body.ragdollRestoreRetryStarted = nil
        body.ragdollRestoreRetryCount = nil
    end

    SendUnconsciousRagdoll(ply, nil)
    ResetPlayerRagdollCamera(ply)
    SchedulePostWakePositionCheck(ply, finalWakePos, finalWakeAng)
    if wakePerfEnabled then
        local threshold = GetConVar("woundsys_wake_perf_threshold_ms")
        local elapsedMs = (SysTime() - restoreStarted) * 1000
        if elapsedMs >= (threshold and threshold:GetFloat() or 4) then
            print(string.format(
                "[WoundSystem wake restore perf] ply=%s ms=%.2f keep=%s preserve=%s hadRagdoll=%s",
                ply:Nick(),
                elapsedMs,
                tostring(keepRagdoll == true),
                tostring(preserveCurrentTransform == true),
                tostring(IsValid(ragdoll))
            ))
        end
    end
    return true
end

function WoundSystemRemoveOwnedRagdolls(ply)
    if not IsValid(ply) then return end

    for _, className in ipairs({"prop_ragdoll", "hl2mp_ragdoll"}) do
        for _, ragdoll in ipairs(ents.FindByClass(className)) do
            if IsValid(ragdoll)
                and (ragdoll.WoundSystemOwner == ply or ragdoll:GetNWEntity("WoundSystemOwner") == ply)
                and (ragdoll.WoundSystemUnconsciousRagdoll
                    or ragdoll.WoundSystemDeadUnconsciousBody
                    or ragdoll:GetNWBool("WoundSystemUnconsciousRagdoll", false)
                    or ragdoll:GetNWBool("WoundSystemDeadUnconsciousBody", false)
                    or ragdoll:GetNWBool("WoundSystemDeathRagdoll", false)) then
                DisableRagdollForPlayerRestore(ragdoll)
                ragdoll:Remove()
            end
        end
    end
end

function WoundSystemForceClearUnconsciousRagdollState(ply, body)
    if not IsValid(ply) then return end

    if body then
        local restored = RestorePlayerFromUnconsciousRagdoll(ply, body, false, false)
        if restored == false then
            RestorePlayerFromUnconsciousRagdoll(ply, body, false, true)
        end
    else
        local ragdoll = ply:GetNWEntity("WoundSystemUnconsciousRagdoll")
        if IsValid(ragdoll) then
            DisableRagdollForPlayerRestore(ragdoll)
            ragdoll:Remove()
        end
    end

    WoundSystemRemoveOwnedRagdolls(ply)
    ResetPlayerRagdollCamera(ply)
    ply:SetNWEntity("WoundSystemDeathRagdoll", NULL)

    local activeWep = ply:GetActiveWeapon()
    if IsValid(activeWep) then
        activeWep:SetNoDraw(false)
    end

    for _, child in pairs(ply:GetChildren()) do
        if child:GetClass() == "prop_physics" or child:GetClass() == "base_gmodentity" then
            child:SetNoDraw(false)
        end
    end
end

local function RestorePlayerOnRespawn(ply)
    local body = BodyState[ply]
    if not body then return end

    local keepCorpse = body.diedWhileUnconscious == true
        or body.fallingRagdollReason == "dead"
        or IsValid(body.deathRagdollOverride)
        or (IsValid(body.unconsciousRagdoll) and body.unconscious == true and not ply:Alive())

    RestorePlayerFromUnconsciousRagdoll(ply, body, keepCorpse, true)
end

local function MarkRecoverableDroppedWeapon(ply, wep)
    if not IsValid(ply) or not IsValid(wep) or not wep:IsWeapon() then return end

    wep.WoundSystemRecoverableDrop = true
    wep.WoundSystemDroppedBy = ply
    wep.WoundSystemDroppedAt = CurTime()
    wep:SetNWBool("WoundSystemRecoverableDrop", true)
    wep:SetNWEntity("WoundSystemDroppedBy", ply)
end

Const.ProtectedDropWeaponClasses = {
    gmod_camera = true,
    gmod_tool = true,
    weapon_physgun = true,
}

local function IsProtectedDropWeapon(wep)
    if not IsValid(wep) or not wep.GetClass then return false end

    local class = string.lower(wep:GetClass() or "")
    return Const.ProtectedDropWeaponClasses[class] == true
end

local function DropRecoverableWeapon(ply, wep)
    if not IsValid(ply) or not IsValid(wep) or not wep:IsWeapon() then return false end
    if IsProtectedDropWeapon(wep) then return false end

    MarkRecoverableDroppedWeapon(ply, wep)
    ply:DropWeapon(wep)

    timer.Simple(0, function()
        if IsValid(wep) then
            MarkRecoverableDroppedWeapon(ply, wep)
            if wep.SetCollisionGroup then
                wep:SetCollisionGroup(COLLISION_GROUP_WEAPON)
            end
        end
    end)

    return true
end

function WoundSystem.Health.DropRecoverableActiveWeapon(ply)
    if not IsValid(ply) or not ply:Alive() then return false end

    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return false end

    return DropRecoverableWeapon(ply, wep)
end

local function TryRecoverDroppedWeapon(ply, wep)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    if not IsValid(wep) or not wep:IsWeapon() or not wep.WoundSystemRecoverableDrop then return end
    if CurTime() - (wep.WoundSystemDroppedAt or 0) < 0.45 then return end

    local body = BodyState[ply]
    if body and (body.unconscious or body.fallingRagdoll) then return end

    local class = wep:GetClass()
    if not class or class == "" or (ply.HasWeapon and ply:HasWeapon(class)) then return end

    local clip1 = wep.Clip1 and wep:Clip1() or -1
    local clip2 = wep.Clip2 and wep:Clip2() or -1
    local primaryAmmoType = wep.GetPrimaryAmmoType and wep:GetPrimaryAmmoType() or -1
    local secondaryAmmoType = wep.GetSecondaryAmmoType and wep:GetSecondaryAmmoType() or -1

    local given = ply:Give(class)
    if not IsValid(given) then return end

    if given.SetClip1 and clip1 and clip1 >= 0 then given:SetClip1(clip1) end
    if given.SetClip2 and clip2 and clip2 >= 0 then given:SetClip2(clip2) end
    if primaryAmmoType and primaryAmmoType >= 0 and wep.Ammo1 then ply:SetAmmo(wep:Ammo1(), primaryAmmoType) end
    if secondaryAmmoType and secondaryAmmoType >= 0 and wep.Ammo2 then ply:SetAmmo(wep:Ammo2(), secondaryAmmoType) end

    wep:Remove()
end

local function TryCreateUnconsciousRagdoll(ply, body)
    local WB = WoundSystemBridgeActive()
    if WB then return WB.CreateRagdoll(ply, body) end
    if not IsValid(ply) or not body then return false end

    ply:SetNWFloat("WoundSystemBrainShakeUntil", 0)
    ply:SetNWFloat("WoundSystemBrainReverseUntil", 0)

    if IsValid(body.unconsciousRagdoll) then return true end

    local model = ply:GetModel()
    if not model or model == "" then
        body.ragdollModeFailed = true
        SendUnconsciousRagdoll(ply, nil)
        return false
    end

    local ragdoll = ents.Create("prop_ragdoll")
    if not IsValid(ragdoll) then
        body.ragdollModeFailed = true
        SendUnconsciousRagdoll(ply, nil)
        return false
    end

    ragdoll:SetModel(model)
    ragdoll:SetPos(ply:GetPos())
    ragdoll:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    ragdoll:SetOwner(ply)
    ragdoll:Spawn()
    ragdoll:Activate()
    WoundSystem.Health.Config.ApplyVanillaBloodMode(ragdoll)
	
    if body.unconscious then
        local activeWep = ply:GetActiveWeapon()
        if IsValid(activeWep) then
            DropRecoverableWeapon(ply, activeWep)
        end
    end

	-- If you have accessories or other held items, hide them too:
	for _, child in pairs(ply:GetChildren()) do
		-- Only hide things that are being held or attached
		if child:GetClass() == "prop_physics" or child:GetClass() == "base_gmodentity" then
			child:SetNoDraw(true)
		end
	end

    if string.lower(ragdoll:GetModel() or "") ~= string.lower(model) then
        ragdoll:Remove()
        body.ragdollModeFailed = true
        SendUnconsciousRagdoll(ply, nil)
        return false
    end

    if ragdoll:GetPhysicsObjectCount() <= 0 then
        ragdoll:Remove()
        body.ragdollModeFailed = true
        SendUnconsciousRagdoll(ply, nil)
        return false
    end

    if WoundSystem.RagdollVisuals and WoundSystem.RagdollVisuals.CopyFromPlayer then
        WoundSystem.RagdollVisuals.CopyFromPlayer(ply, ragdoll)
    end

    if ply.GetSkin and ragdoll.SetSkin then
        ragdoll:SetSkin(ply:GetSkin())
    end

    if ply.GetNumBodyGroups and ply.GetBodygroup and ragdoll.SetBodygroup then
        for i = 0, ply:GetNumBodyGroups() - 1 do
            ragdoll:SetBodygroup(i, ply:GetBodygroup(i))
        end
    end

    if ragdoll.SetPlayerColor and ply.GetPlayerColor then
        ragdoll:SetPlayerColor(ply:GetPlayerColor())
    end

    ragdoll.WoundSystemOwner = ply
    ragdoll.WoundSystemUnconsciousRagdoll = true
    ragdoll:SetNWEntity("WoundSystemOwner", ply)
    ragdoll:SetNWBool("WoundSystemUnconsciousRagdoll", true)
    MakeRagdollNonCollidingWithActors(ragdoll)

    ragdoll:AddCallback("PhysicsCollide", function(ent, data)
        local owner = ent.WoundSystemOwner
        if not IsValid(owner) and ent.GetNWEntity then
            owner = ent:GetNWEntity("WoundSystemOwner")
        end

        local impactBody = IsValid(owner) and BodyState and BodyState[owner] or nil
        if not WoundSystem.Health.IsLiveUnconsciousRagdollProxy(ent, owner, impactBody) then return end

        local speed = tonumber(data.Speed) or 0
        if speed > 220 then
            local physIndex = nil
            for i = 0, ent:GetPhysicsObjectCount() - 1 do
                if ent:GetPhysicsObjectNum(i) == data.PhysObject then
                    physIndex = i
                    break
                end
            end

            local boneName = ""
            if physIndex then
                local boneId = ent:TranslatePhysBoneToBone(physIndex)
                if boneId and boneId >= 0 then
                    boneName = string.lower(ent:GetBoneName(boneId) or "")
                end
            end

            local hitLimb = RagdollBoneNameToLimb(boneName) or "thorax"

            local dot = 1.0
            if data.OurOldVelocity and data.OurOldVelocity:LengthSqr() > 0 then
                dot = math.abs(data.OurOldVelocity:GetNormalized():Dot(data.HitNormal))
            end

            local jumpSpeed = (impactBody and impactBody.jumpSpeed) or 6.5
            local force = math.Clamp((speed * dot) / 50, 0, jumpSpeed * 7)
            if force > jumpSpeed then
                local curTime = CurTime()
                owner._nextLimbPhysicsDamage = owner._nextLimbPhysicsDamage or {}
                if not owner._nextLimbPhysicsDamage[hitLimb] or curTime > owner._nextLimbPhysicsDamage[hitLimb] then
                    owner._nextLimbPhysicsDamage[hitLimb] = curTime + 0.22

                    ProcessImpactDamage(owner, hitLimb, force)
                end
            end
        end
    end)

    if ply.SetupBones then
        ply:SetupBones()
    end
    local velocity = ply:GetVelocity()
    for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            local boneId = ragdoll:TranslatePhysBoneToBone(i)
            if boneId and boneId >= 0 then
                local pPos, pAng = ply:GetBonePosition(boneId)
                if pPos and pAng then
                    phys:SetPos(pPos)
                    phys:SetAngles(pAng)
                end
            end
            phys:SetVelocity(velocity)
        end
    end

    local phys = ragdoll:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end

    body.unconsciousRagdoll = ragdoll
    body.ragdollWakePos = GetUnconsciousRagdollBodyAnchor(ragdoll) or ragdoll:GetPos()
    body.ragdollWakeAng = (WoundSystem.Health.WakePositions.GetRandomWakeEyeAngles and WoundSystem.Health.WakePositions.GetRandomWakeEyeAngles(ragdoll)) or Angle(0, math.Rand(-180, 180), 0)
    body.ragdollModeFailed = false
    body.ragdollRestoreRetryStarted = nil
    body.ragdollRestoreRetryCount = nil
    body.savedMoveType = NormalizeWakeMoveType(ply:GetMoveType())
    body.cachedUnconsciousMoveOrigin = WoundSystem.Health.WakePositions.FindSafePlayerWakePos(ply, ragdoll, body.ragdollWakePos, {
        anchorPos = body.ragdollWakePos,
        maxDistance = 96,
        preferClosest = true,
        includePlayerBase = false
    }) or ply:GetPos()
    body.nextUnconsciousMoveOriginCheck = CurTime() + 0.35

    HideUnconsciousPlayerBody(ply)
    SetPlayerWakePosition(ply, body.cachedUnconsciousMoveOrigin)

    if PlayerLimbs[ply] then
        WoundSystem.ApplyDismembermentVisuals(ragdoll, PlayerLimbs[ply])
    end

    SendUnconsciousRagdoll(ply, ragdoll)
    return true
end

local function IsWeaponKnockdownDamage(dmginfo)
    if dmginfo:IsFallDamage() or dmginfo:IsDamageType(DMG_RADIATION) then return false end
    if dmginfo:IsDamageType(DMG_DROWN) or dmginfo:IsDamageType(DMG_POISON) then return false end

    if dmginfo:IsDamageType(DMG_BULLET)
        or dmginfo:IsDamageType(DMG_BUCKSHOT)
        or dmginfo:IsDamageType(DMG_BLAST)
        or dmginfo:IsDamageType(DMG_CLUB)
        or dmginfo:IsDamageType(DMG_SLASH) then
        return true
    end

    local attacker = dmginfo:GetAttacker()
    if IsValid(attacker) and (attacker:IsPlayer() or attacker:IsNPC()) then
        local inflictor = dmginfo:GetInflictor()
        if IsValid(inflictor) and (inflictor:IsWeapon() or string.find(inflictor:GetClass() or "", "weapon", 1, true)) then
            return true
        end

        local weapon = attacker.GetActiveWeapon and attacker:GetActiveWeapon()
        if IsValid(weapon) then return true end
    end

    return false
end

local function WeaponKnockdownChance(dmg)
    return math.Clamp(((dmg or 0) - 15) / 85, 0, 1)
end

local function WeaponKnockdownDuration(dmg)
    return math.Clamp(1.0 + ((dmg or 0) / 35), 1.0, 5.0)
end

function Fn.GetKnockdownDirection(ply, dmginfo)
    local dir = dmginfo:GetDamageForce()
    if dir:LengthSqr() > 1 then
        return dir:GetNormalized()
    end

    local attacker = dmginfo:GetAttacker()
    if IsValid(attacker) then
        if attacker.GetShootPos then
            local fromAttacker = ply:WorldSpaceCenter() - attacker:GetShootPos()
            if fromAttacker:LengthSqr() > 1 then
                return fromAttacker:GetNormalized()
            end
        end

        if attacker.GetAimVector then
            local aim = attacker:GetAimVector()
            if aim:LengthSqr() > 0 then return aim:GetNormalized() end
        end
    end

    return ply:GetForward()
end

function Fn.PushRagdollFromDamage(ragdoll, dir, dmg, forceScale)
    if not IsValid(ragdoll) then return end

    local damageRatio = math.Clamp((dmg or 0) / 100, 0, 1)
    local push = (dir + Vector(0, 0, 0.06 + damageRatio * 0.06)):GetNormalized()
    local force = Lerp(damageRatio, 120, 733) * (forceScale or 1)

    for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:Wake()
            phys:ApplyForceCenter(push * force)
        end
    end
end

function Fn.PushRagdollLimbFromDamage(ragdoll, limb, dir, dmg, forceScale)
    if not IsValid(ragdoll) then return false end

    local bones = Const.LimbToBones[limb]
    if not bones then return false end

    local damageRatio = math.Clamp((dmg or 0) / 100, 0, 1)
    local push = (dir + Vector(0, 0, 0.035 + damageRatio * 0.035)):GetNormalized()
    local force = Lerp(damageRatio, 90, 520) * (forceScale or 1)
    local pushed = false
    local usedPhys = {}

    for _, boneName in ipairs(bones) do
        local boneId = ragdoll:LookupBone(boneName)
        if boneId then
            local physId = ragdoll:TranslateBoneToPhysBone(boneId)
            if physId and physId >= 0 and not usedPhys[physId] then
                local phys = ragdoll:GetPhysicsObjectNum(physId)
                if IsValid(phys) then
                    usedPhys[physId] = true
                    phys:Wake()
                    phys:ApplyForceCenter(push * force)
                    pushed = true
                end
            end
        end
    end

    return pushed
end

function WoundSystem.Health.SuppressLimbPhysicsDamage(ply, limb, duration)
    if not IsValid(ply) or not limb then return end

    ply._nextLimbPhysicsDamage = ply._nextLimbPhysicsDamage or {}
    ply._nextLimbPhysicsDamage[limb] = math.max(
        ply._nextLimbPhysicsDamage[limb] or 0,
        CurTime() + (duration or 0.16)
    )
end

local function TryWeaponKnockdown(ply, body, dmginfo, dmg)
    if not IsValid(ply) or not body or not ply:Alive() then return end
    if body.isGodMode or body.unconscious or body.fallingRagdoll then return end
    if not IsWeaponKnockdownDamage(dmginfo) then return end

    local chance = WeaponKnockdownChance(dmg)
    if chance <= 0 then return end

    local curTime = CurTime()
    if curTime < (body.nextWeaponRagdollTime or 0) then return end

    if math.Rand(0, 1) > chance then
        body.nextWeaponRagdollTime = curTime + 0.35
        return
    end

    body.nextWeaponRagdollTime = curTime + 1.25
    Fn.AddBodyShock(body, 20)
    body.fallingRagdoll = true
    body.fallingRagdollWakeTime = curTime + WeaponKnockdownDuration(dmg)
    body.fallingRagdollReason = "weapon"

    if TryCreateUnconsciousRagdoll(ply, body) then
        Fn.PushRagdollFromDamage(body.unconsciousRagdoll, Fn.GetKnockdownDirection(ply, dmginfo), dmg)
    end
end

function Fn.IsDismemberingDamage(dmginfo)
    return dmginfo:IsDamageType(DMG_BLAST)
        or dmginfo:IsDamageType(DMG_SLASH)
        or dmginfo:IsDamageType(DMG_BULLET)
        or dmginfo:IsDamageType(DMG_BUCKSHOT)
        or dmginfo:IsDamageType(DMG_CLUB)
end

Const.SharpMeleeClassPatterns = {
    "knife",
    "dagger",
    "blade",
    "bayonet",
    "cleaver",
    "machete",
    "sword",
    "katana",
    "axe",
    "hatchet",
    "sickle",
    "scythe",
    "chainsaw"
}

Const.BluntMeleeClassPatterns = {
    "stunstick",
    "stun_stick",
    "stunbaton",
    "stun_baton",
    "baton",
    "crowbar",
    "club",
    "bat",
    "hammer",
    "mace",
    "wrench",
    "pipe",
    "fist"
}

local function ClassMatchesAnyPattern(class, patterns)
    class = string.lower(tostring(class or ""))
    if class == "" then return false end

    for _, pattern in ipairs(patterns) do
        if string.find(class, pattern, 1, true) then return true end
    end

    return false
end

local function IsWeaponLikeDamageInflictor(ent)
    if not IsValid(ent) then return true end
    if ent.IsWeapon and ent:IsWeapon() then return true end

    local class = ent.GetClass and string.lower(ent:GetClass() or "") or ""
    return string.find(class, "weapon", 1, true) ~= nil
end

local function DamageInfoWeaponClasses(dmginfo)
    local classes = {}
    if not dmginfo then return classes end

    local inflictor = dmginfo:GetInflictor()
    if IsValid(inflictor) and inflictor.GetClass then
        classes[#classes + 1] = inflictor:GetClass()
    end

    local attacker = dmginfo:GetAttacker()
    if IsValid(attacker) and attacker.GetActiveWeapon and (not IsValid(inflictor) or inflictor == attacker or IsWeaponLikeDamageInflictor(inflictor)) then
        local weapon = attacker:GetActiveWeapon()
        if IsValid(weapon) and weapon.GetClass then
            classes[#classes + 1] = weapon:GetClass()
        end
    end

    if IsValid(attacker) and attacker.GetClass then
        classes[#classes + 1] = attacker:GetClass()
    end

    return classes
end

local function DamageInfoHasClassPattern(dmginfo, patterns)
    for _, class in ipairs(DamageInfoWeaponClasses(dmginfo)) do
        if ClassMatchesAnyPattern(class, patterns) then return true end
    end

    return false
end

local function IsDamageTypeProtectedFromMeleeNormalize(dmginfo)
    return dmginfo:IsFallDamage()
        or dmginfo:IsDamageType(DMG_BULLET)
        or dmginfo:IsDamageType(DMG_BUCKSHOT)
        or dmginfo:IsDamageType(DMG_BLAST)
        or dmginfo:IsDamageType(DMG_BURN)
        or dmginfo:IsDamageType(DMG_DIRECT)
        or dmginfo:IsDamageType(DMG_RADIATION)
        or dmginfo:IsDamageType(DMG_DROWN)
        or dmginfo:IsDamageType(DMG_POISON)
end

local function NormalizeMeleeDamageType(dmginfo)
    if not dmginfo or not dmginfo.SetDamageType then return end
    if IsDamageTypeProtectedFromMeleeNormalize(dmginfo) then return end

    if DamageInfoHasClassPattern(dmginfo, Const.SharpMeleeClassPatterns) then
        dmginfo:SetDamageType(DMG_SLASH)
    elseif DamageInfoHasClassPattern(dmginfo, Const.BluntMeleeClassPatterns) then
        dmginfo:SetDamageType(DMG_CLUB)
    end
end

function Fn.IsBloodVisualDamage(dmginfo)
    return dmginfo:IsDamageType(DMG_BULLET)
        or dmginfo:IsDamageType(DMG_BUCKSHOT)
        or dmginfo:IsDamageType(DMG_SLASH)
        or dmginfo:IsDamageType(DMG_CLUB)
        or dmginfo:IsDamageType(DMG_BLAST)
end

function Fn.IsBulletImpactDamage(dmginfo)
    return dmginfo:IsDamageType(DMG_BULLET) or dmginfo:IsDamageType(DMG_BUCKSHOT)
end

local function ShouldUseOgGunshotDamage(dmginfo, dmg)
    dmg = tonumber(dmg) or 0
    return dmg > 0 and Fn.IsBulletImpactDamage(dmginfo)
end

function Fn.GetOgGunshotDamageMultiplier(dmginfo, dmg, limb)
    dmg = math.max(tonumber(dmg) or 0, 0)

    -- C:U gun wounds are driven by playerDamageMultiplier, not raw Source
    -- damage. Map GMod damage into that space so pistols still use the same
    -- wound package, but at a much less violent scale.
    local divisor = dmginfo:IsDamageType(DMG_BUCKSHOT) and 55 or 35
    local mult = dmg / divisor

    if limb == "head" then
        mult = math.max(mult, 0.35)
    end

    local maxMult = dmginfo:IsDamageType(DMG_BUCKSHOT) and 1.1 or 1.35
    return math.Clamp(mult, 0.25, maxMult)
end

function Fn.AddGunshotShrapnel(state, ply)
    if not state then return end

    if IsValid(ply) and WoundSystem and WoundSystem.HEVGetShrapnelBlockChance then
        local chance = WoundSystem.HEVGetShrapnelBlockChance(ply)
        if chance > 0 and math.random() < chance then
            return
        end
    end

    local maxShrapnel = WoundSystem.Health.Constants.ShrapnelPieceCount or 5
    state.shrapnel = math.min((tonumber(state.shrapnel) or 0) + 1, maxShrapnel)
end

function Fn.GetGunshotPhysicalResponseTier(dmg)
    dmg = tonumber(dmg) or 0
    if dmg <= 0 then return 0 end
    if dmg <= 15 then return 1 end
    if dmg <= 30 then return 2 end
    if dmg <= 45 then return 3 end
    return 4
end

local function SendBallisticStaggerFeedback(ply, tier, dmg)
    if not IsValid(ply) then return end

    net.Start("WoundSystem_BallisticStagger")
        net.WriteUInt(math.Clamp(tier or 1, 1, 3), 3)
        net.WriteFloat(math.Clamp((tonumber(dmg) or 0) / 45, 0, 1))
    net.Send(ply)
end

local function ApplyActiveBallisticStagger(ply, body, dmginfo, dmg, tier)
    if not IsValid(ply) or not body or body.unconscious or body.fallingRagdoll then return end

    local now = CurTime()
    local dir = Fn.GetKnockdownDirection(ply, dmginfo)
    dir = Vector(dir.x, dir.y, 0)
    if dir:LengthSqr() <= 0.0001 then
        dir = -ply:GetForward()
        dir.z = 0
    end
    dir:Normalize()

    local pushForce
    if tier == 1 then
        pushForce = Lerp(math.Clamp(((tonumber(dmg) or 1) - 1) / 14, 0, 1), 65, 125)
    elseif tier == 2 then
        pushForce = Lerp(math.Clamp(((tonumber(dmg) or 16) - 16) / 14, 0, 1), 145, 220)
    else
        pushForce = 220
    end

    ply:SetVelocity((dir * pushForce) + Vector(0, 0, tier == 1 and 6 or 12))

    body.ballisticStaggerTier = tier
    body.ballisticStaggerUntil = math.max(body.ballisticStaggerUntil or 0, now + (tier == 1 and 0.34 or tier == 2 and 0.52 or 0.68))
    body.ballisticControlDelayUntil = math.max(body.ballisticControlDelayUntil or 0, now + (tier == 1 and 0.16 or tier == 2 and 0.28 or 0.38))
    body.suppressShockRagdollUntil = math.max(body.suppressShockRagdollUntil or 0, now + 0.9)

    if tier >= 2 then
        local forcedForward = 0
        local forcedSide = 0
        if ply:KeyDown(IN_BACK) then forcedForward = -220 end
        if ply:KeyDown(IN_MOVELEFT) then forcedSide = forcedSide - 220 end
        if ply:KeyDown(IN_MOVERIGHT) then forcedSide = forcedSide + 220 end

        body.ballisticHeldForward = forcedForward
        body.ballisticHeldSide = forcedSide
        body.ballisticHeldMoveUntil = math.max(body.ballisticHeldMoveUntil or 0, now + (tier == 2 and 0.26 or 0.34))
    end

    if tier == 3 then
        body.ballisticWasDucking = ply:KeyDown(IN_DUCK) == true
        if not body.ballisticWasDucking then
            body.ballisticForceDuckUntil = math.max(body.ballisticForceDuckUntil or 0, now + 0.22)
            body.ballisticForceUnduckUntil = math.max(body.ballisticForceUnduckUntil or 0, now + 0.42)
        end
    end

    SendBallisticStaggerFeedback(ply, tier, dmg)
end

local function ApplyOgGunshotDamage(ply, body, limb, state, dmginfo, dmg)
    if not IsValid(ply) or not body or not state then return false end

    local mult = Fn.GetOgGunshotDamageMultiplier(dmginfo, dmg, limb)
    local physicalTier = Fn.GetGunshotPhysicalResponseTier(dmg)

    state.pain = math.Clamp((state.pain or 0) + (math.Rand(80, 100) * mult), 0, 100)
    state.skin = math.Clamp((state.skin or 100) - (math.Rand(70, 100) * mult), 0, 100)
    state.muscle = math.Clamp((state.muscle or 100) - (math.Rand(70, 100) * mult), 0, 100)
    state.bleed = math.Clamp((state.bleed or 0) + (math.Rand(30, 40) * mult), 0, 100)
    Fn.AddGunshotShrapnel(state, ply)
    if (state.infectionSpeed or 0) <= 0 then state.infectionSpeed = 0.5 end
    Fn.ClearLimbBandage(state)

    body.adrenaline = 100
    body.temporarySlowdown = math.max(body.temporarySlowdown or 0, 0.25)
    Fn.AddBodyShock(body, 20 * mult)

    if Fn.IsCriticalLimb(limb) then
        body.internalBleeding = math.Clamp((body.internalBleeding or 0) + (math.Rand(18, 22) * mult), 0, 100)
    end

    if not Fn.IsCriticalLimb(limb) and math.Rand(0, 1) < math.Clamp(0.3 * mult, 0, 0.75) then
        ApplyFracture(ply, limb, state)
    end

    if limb == "head" then
        local brainTrauma = math.Rand(10, 85) * mult
        body.consciousness = 0
        body.unconscious = true
        body.wasUnconscious = true
        body.brainHealth = math.Clamp((body.brainHealth or 100) - brainTrauma, 0, 100)
        body.brainDamageBuffer = math.max(body.brainDamageBuffer or 0, brainTrauma)
        Fn.AddHearingLoss(body, (tonumber(dmg) or 0) * 0.6)

        if math.Rand(0, 1) < math.Clamp(0.5 * mult, 0, 0.95) then
            body.disfigured = true
        end

        if body.brainHealth <= 0 then
            body.brainDead = true
            PreserveUnconsciousRagdollForDeath(ply, body)
            SendLimbUpdate(ply, limb, true)
            SendCardioUpdate(ply)
            WoundSystem.Health.QueueDamageFeedback(ply, limb, dmginfo, dmg, body, state, true)
            WoundSystem.Health.KillWithAttribution(ply, body, "og_ballistic_head_trauma")
            return true
        end
    end

    if body.unconscious then
        if TryCreateUnconsciousRagdoll(ply, body) and physicalTier >= 4 then
            Fn.PushRagdollLimbFromDamage(body.unconsciousRagdoll, limb, Fn.GetKnockdownDirection(ply, dmginfo), dmg, 0.35)
        end
    elseif physicalTier >= 4 and not body.fallingRagdoll then
        body.fallingRagdoll = true
        body.fallingRagdollWakeTime = CurTime() + math.Clamp(2.0 + mult * 2.5, 2.5, 5.5)
        body.fallingRagdollReason = "og_ballistic_hit"
        if TryCreateUnconsciousRagdoll(ply, body) then
            Fn.PushRagdollLimbFromDamage(body.unconsciousRagdoll, limb, Fn.GetKnockdownDirection(ply, dmginfo), dmg, 0.35)
        end
    elseif physicalTier > 0 then
        ApplyActiveBallisticStagger(ply, body, dmginfo, dmg, physicalTier)
    end

    WoundSystem.Health.QueueDamageFeedback(ply, limb, dmginfo, dmg, body, state, physicalTier >= 4 or body.unconscious or body.fallingRagdoll)
    return false
end

function Fn.EmitBulletHitSound(ent, dmginfo)
    if not IsValid(ent) or not Fn.IsBulletImpactDamage(dmginfo) then return end
    if (dmginfo:GetDamage() or 0) <= 0 then return end

    local now = CurTime()
    if (ent._WoundSystemNextBulletHitSound or 0) > now then return end
    ent._WoundSystemNextBulletHitSound = now + 0.045
    ent:EmitSound("bullethit.ogg", 70, 100, 0.8)
end

function Fn.DamageBloodNormal(ent, pos, dmginfo)
    local attacker = dmginfo:GetAttacker()
    if IsValid(attacker) then
        local from = attacker.EyePos and attacker:EyePos() or attacker:WorldSpaceCenter()
        local normal = pos - from
        if normal:LengthSqr() > 0.001 then
            return normal:GetNormalized()
        end
    end

    local force = dmginfo:GetDamageForce()
    if force and force:LengthSqr() > 0.001 then
        return force:GetNormalized()
    end

    return Vector(0, 0, 1)
end

local function EmitDamageBloodEffect(ent, dmginfo, damageScale)
    if not WoundSystem.BloodEffects or not WoundSystem.BloodEffects.Emit then return end
    if not IsValid(ent) or not Fn.IsBloodVisualDamage(dmginfo) then return end

    local now = CurTime()
    if (ent._WoundSystemNextBloodImpact or 0) > now then return end
    ent._WoundSystemNextBloodImpact = now + 0.055

    local dmg = math.max(tonumber(damageScale) or dmginfo:GetDamage() or 0, 1)
    local severity = math.Clamp(dmg / 24, 0.6, 3)
    local pos = dmginfo:GetDamagePosition()
    if not pos or pos:LengthSqr() <= 0.001 then
        pos = ent:WorldSpaceCenter()
    end
    local normal = Fn.DamageBloodNormal(ent, pos, dmginfo)

    WoundSystem.BloodEffects.Emit(pos, normal, severity, "impact", nil, ent)

    if WoundSystem.BloodEffects.EmitGround and severity >= 0.45 then
        WoundSystem.BloodEffects.EmitGround(pos, severity * 0.25, "stain", ent)
    end
end

local function EmitDamageBodyFlow(ent, dmginfo, damageScale, limbId)
    if not WoundSystem.BloodEffects or not WoundSystem.BloodEffects.Emit then return end
    if not IsValid(ent) or not limbId or limbId == "" or not Fn.IsBloodVisualDamage(dmginfo) then return end

    local now = CurTime()
    ent._WoundSystemNextBodyFlow = ent._WoundSystemNextBodyFlow or {}
    if (ent._WoundSystemNextBodyFlow[limbId] or 0) > now then return end
    ent._WoundSystemNextBodyFlow[limbId] = now + 0.09

    local dmg = math.max(tonumber(damageScale) or dmginfo:GetDamage() or 0, 1)
    local severity = math.Clamp(dmg / 30, 0.35, 2.4)
    local pos = dmginfo:GetDamagePosition()
    if not pos or pos:LengthSqr() <= 0.001 then
        pos = ent.WorldSpaceCenter and ent:WorldSpaceCenter() or ent:GetPos()
    end

    local flowEnt = ent
    if ent:IsPlayer() then
        local body = BodyState[ent]
        if body and IsValid(body.unconsciousRagdoll) then
            flowEnt = body.unconsciousRagdoll
        end
    end

    WoundSystem.BloodEffects.Emit(pos, Fn.DamageBloodNormal(flowEnt, pos, dmginfo), severity, "bodyflow", nil, flowEnt, limbId)
end

function Fn.RollShouldDismember(state, dmginfo, appliedDmg, rawDmg)
    if not state or state.dismembered or not Fn.IsDismemberingDamage(dmginfo) then return false end

    local dmg = rawDmg or appliedDmg or 0
    local chance = 0

    if dmginfo:IsDamageType(DMG_BLAST) then
        chance = math.Clamp((dmg - 45) / 75, 0, 0.9)
    elseif dmginfo:IsDamageType(DMG_SLASH) then
        chance = math.Clamp((dmg - 30) / 70, 0, 0.75)
    elseif dmginfo:IsDamageType(DMG_BULLET) or dmginfo:IsDamageType(DMG_BUCKSHOT) then
        chance = math.Clamp((dmg - 70) / 90, 0, 0.55)
    elseif dmginfo:IsDamageType(DMG_CLUB) then
        chance = math.Clamp((dmg - 85) / 80, 0, 0.35)
    end

    if (state.muscle or 100) <= 0 and (state.skin or 100) <= 35 then
        chance = math.max(chance, 0.6)
    elseif (state.muscle or 100) <= 0 then
        chance = math.max(chance, 0.35)
    end

    return chance > 0 and math.Rand(0, 1) <= chance
end

local defaultLimbState = {
    skin = 100,
    muscle = 100,
    muscleStrength = 1,
    pain = 0,
    bleed = 0,
    infection = 0,
    infectionSpeed = 0,
    shrapnel = 0,
    disinfectTime = 0,
    broken = false,
    dislocated = false,
    dislocationTimer = 0,
    boneHealTimer = 0,
    isBandaged = false,
    blockedBleeding = false,
    bandageSlowAmount = 0,
    skinHealAmount = 0,
    furBloodAmount = 0,
    eyes = 2,
    dismembered = false,
    bandageMinigameSpeedMult = 1.0,
    customStatuses = {}
}

local function InitPlayer(ply)
    PlayerLimbs[ply] = {}

    for _, limb in ipairs({
        "foot_R", "foot_L",
        "crus_R", "crus_L",
        "thigh_R", "thigh_L",
        "abdomen",
        "thorax",
        "arm_R", "arm_L",
        "forearm_R", "forearm_L",
        "hand_R", "hand_L",
        "head"
    }) do
        PlayerLimbs[ply][limb] = table.Copy(defaultLimbState)
        if WoundSystem.Statuses then
            WoundSystem.Statuses.ApplyDefaultState(PlayerLimbs[ply][limb])
        end
    end
	
	if PlayerLimbs[ply]["head"] then
        PlayerLimbs[ply]["head"].eyes = 2
    end

    if IsValid(ply) then
        WoundSystem.Health.Config.ApplyVanillaBloodMode(ply)

        for limbName, _ in pairs(Const.LimbToBones) do
            Fn.ForEachDismembermentBone(ply, limbName, function(boneIndex)
                ply:ManipulateBoneScale(boneIndex, Vector(1, 1, 1))
            end)
            Fn.SetLimbBodygroupState(ply, limbName, false)
        end
    end

    -- OG values from Casualties Unknown's serialized Limb.bandageMinigameSpeedMult.
    -- Higher values damp hand velocity harder while holding the roll.
    local limbSpeedMultipliers = {
        hand_R = 0.5, hand_L = 0.5,
        forearm_R = 0.7, forearm_L = 0.7,
        arm_R = 0.95, arm_L = 0.95,

        thorax = 1.75,
        abdomen = 1.5,

        thigh_R = 1.15, thigh_L = 1.15,
        crus_R = 1.0, crus_L = 1.0,
        foot_R = 1.0, foot_L = 1.0,

        head = 1.0
    }
    
    for limbName, multiplier in pairs(limbSpeedMultipliers) do
        if PlayerLimbs[ply][limbName] then
            PlayerLimbs[ply][limbName].bandageMinigameSpeedMult = multiplier
        end
    end

    InitBody(ply)
end

local function ResetPlayerInventory(ply)
    PlayerInventory[ply] = BuildDefaultServerInventory()
    SyncInventoryToClient(ply)
end

local function CreateEmptyInventorySlot()
    return { type = "empty" }
end

function BuildDefaultServerInventory()
    -- no inventory items: the slots only exist as a hand for Z-City SWEP minigames (slot 6, created on demand)
    local slots = {}
    local numSlots = (WoundSystem.Health and WoundSystem.Health.Constants and WoundSystem.Health.Constants.InventorySlots) or 5

    for i = 1, numSlots do
        slots[i] = CreateEmptyInventorySlot()
    end

    return slots
end

GetInventory = function(ply)
    if not PlayerInventory[ply] then
        PlayerInventory[ply] = BuildDefaultServerInventory()
    end

    return PlayerInventory[ply]
end

function SyncInventoryToClient(ply)
    if not IsValid(ply) then return end

    local inv = GetInventory(ply)

    net.Start("WoundSystem_SyncInventory")
        for i = 1, WoundSystem.Health.Constants.InventorySlots do
            local slot = inv[i] or CreateEmptyInventorySlot()
            local kind = 0

            if slot.type == "tool" then
                kind = 1
            elseif slot.type == "weapon" then
                kind = 2
            end

            net.WriteUInt(kind, 2)

            if kind == 1 then
                net.WriteString(slot.toolName or "")
                net.WriteFloat(slot.durability or 0)
            end
        end

        -- temporary slot of a Z-City SWEP minigame (not part of the visible inventory)
        local temp = inv[6]
        local hasTemp = istable(temp) and temp.type == "tool"
        net.WriteBool(hasTemp)
        if hasTemp then
            net.WriteString(temp.toolName or "")
            net.WriteFloat(temp.durability or 0)
        end
    net.Send(ply)
end

local function GetInventorySlot(ply, slotIdx)
    slotIdx = tonumber(slotIdx)
    if not slotIdx or slotIdx < 1 or slotIdx > WoundSystem.Health.Constants.InventorySlots then return nil end

    local inv = GetInventory(ply)
    return inv[slotIdx]
end

local function NormalizeToolId(toolName)
    return WoundSystem.NormalizeItemId and WoundSystem.NormalizeItemId(toolName) or string.upper(tostring(toolName or ""))
end

local function ValidateToolSlot(ply, slotIdx, expectedTool)
    local slot
    if tonumber(slotIdx) == 6 then
        -- temporary slot of a Z-City SWEP minigame: valid only while its deferred session is open
        local bs, ss = Sessions.Bandage[ply], Sessions.Syringe[ply]
        if not ((bs and bs.external) or (ss and ss.external)) then return nil end
        slot = PlayerInventory[ply] and PlayerInventory[ply][6]
    else
        slot = GetInventorySlot(ply, slotIdx)
    end
    if not slot or slot.type ~= "tool" then return nil end

    if expectedTool and NormalizeToolId(slot.toolName) ~= NormalizeToolId(expectedTool) then
        return nil
    end

    return slot
end

local function SetInventorySlot(ply, slotIdx, slot)
    GetInventory(ply)[slotIdx] = slot or CreateEmptyInventorySlot()
end

local function ConsumeToolDurability(ply, slotIdx, cost)
    local slot = (tonumber(slotIdx) == 6) and (PlayerInventory[ply] and PlayerInventory[ply][6]) or GetInventorySlot(ply, slotIdx)
    if not slot or slot.type ~= "tool" then return false end

    cost = tonumber(cost) or 0
    if slot.durability < cost then return false end

    slot.durability = math.max(0, slot.durability - cost)

    local removeOnDepleted = true
    if WoundSystem.Items and WoundSystem.Items.ShouldRemoveOnDepleted then
        removeOnDepleted = WoundSystem.Items.ShouldRemoveOnDepleted(slot.toolName)
    end

    if (removeOnDepleted or tonumber(slotIdx) == 6) and slot.durability <= 0.001 then
        SetInventorySlot(ply, slotIdx, CreateEmptyInventorySlot())
    end

    SyncInventoryToClient(ply)
    return true
end

local function CopyLimbSnapshot(state)
    return {
        skin = state.skin,
        muscle = state.muscle,
        pain = state.pain,
        bleed = state.bleed,
        infection = state.infection,
        infectionSpeed = state.infectionSpeed,
        shrapnel = state.shrapnel,
        disinfectTime = state.disinfectTime,
        broken = state.broken,
        dislocated = state.dislocated,
        dislocationTimer = state.dislocationTimer or 0,
        boneHealTimer = state.boneHealTimer or 0,
        muscleStrength = state.muscleStrength or 1,
        isBandaged = state.isBandaged or false,
        hasInjection = state.hasInjection or false,
        furBloodAmount = state.furBloodAmount or 0,
        eyes = state.eyes or 2,
        dismembered = state.dismembered or false,
        bandageMinigameSpeedMult = state.bandageMinigameSpeedMult or 1,
        statusSnapshot = WoundSystem.Statuses and WoundSystem.Statuses.GetSnapshot(state) or ""
    }
end

local function LimbSnapshotChanged(previous, current)
    if not previous then return true end

    for key, value in pairs(current) do
        local oldValue = previous[key]
        if type(value) == "number" then
            if math.abs((oldValue or 0) - value) > WoundSystem.Health.Constants.LimbSyncEpsilon then
                return true
            end
        elseif oldValue ~= value then
            return true
        end
    end

    return false
end

local function RememberLimbSnapshot(ply, limb, state)
    LastSentLimbState[ply] = LastSentLimbState[ply] or {}
    LastSentLimbState[ply][limb] = CopyLimbSnapshot(state)
end

Const.DismembermentVisualLimbOrder = {
    "foot_R", "foot_L",
    "crus_R", "crus_L",
    "thigh_R", "thigh_L",
    "arm_R", "arm_L",
    "forearm_R", "forearm_L",
    "hand_R", "hand_L",
    "head"
}

local function SendDismembermentVisuals(ply, recipients)
    if not IsValid(ply) then return end

    local limbs = PlayerLimbs[ply]
    if not limbs then return end

    net.Start("WoundSystem_DismemberVisuals")
        net.WriteEntity(ply)
        net.WriteUInt(#Const.DismembermentVisualLimbOrder, 5)
        for _, limbName in ipairs(Const.DismembermentVisualLimbOrder) do
            local state = limbs[limbName]
            net.WriteString(limbName)
            net.WriteBool(state and state.dismembered == true or false)
        end

    if recipients then
        net.Send(recipients)
    else
        net.Broadcast()
    end
end

local function SendAllDismembermentVisuals(recipient)
    if not IsValid(recipient) then return end

    for _, ply in ipairs(player.GetAll()) do
        if PlayerLimbs[ply] then
            SendDismembermentVisuals(ply, recipient)
        end
    end
end

local function SendDismembermentVisualReset(ply, recipients)
    if not IsValid(ply) then return end

    net.Start("WoundSystem_ResetDismemberVisuals")
        net.WriteEntity(ply)

    if recipients then
        net.Send(recipients)
    else
        net.Broadcast()
    end
end

SendLimbUpdate = function(ply, limb, force)
    local state = PlayerLimbs[ply] and PlayerLimbs[ply][limb]
    if not state then return end

    local previous = LastSentLimbState[ply] and LastSentLimbState[ply][limb]
    local snapshot = CopyLimbSnapshot(state)
    if not force and not LimbSnapshotChanged(previous, snapshot) then
        return
    end

    RememberLimbSnapshot(ply, limb, state)
    if snapshot.dismembered ~= (previous and previous.dismembered or false) then
        SendDismembermentVisuals(ply)
    end

    net.Start("WoundSystem_UpdateLimb")
        net.WriteString(limb)
        net.WriteFloat(state.skin)
        net.WriteFloat(state.muscle)
        net.WriteFloat(state.pain)
        net.WriteFloat(state.bleed)
        net.WriteFloat(state.infection)
        net.WriteFloat(state.infectionSpeed)
        net.WriteUInt(state.shrapnel, 4)
        net.WriteFloat(state.disinfectTime)
        net.WriteBool(state.broken)
        net.WriteBool(state.dislocated)
        net.WriteFloat(state.dislocationTimer or 0)
        net.WriteFloat(state.boneHealTimer or 0)
        net.WriteFloat(state.muscleStrength or 1)
        net.WriteBool(state.isBandaged or false)
        net.WriteBool(state.hasInjection or false)
        net.WriteFloat(state.furBloodAmount or 0)
        net.WriteUInt(state.eyes or 2, 3)
        net.WriteBool(state.dismembered or false)
        net.WriteFloat(state.bandageMinigameSpeedMult or 1)
        if WoundSystem.Statuses and WoundSystem.Statuses.WriteNet then
            WoundSystem.Statuses.WriteNet(state)
        else
            net.WriteUInt(0, 5)
        end
    net.Send(ply)
end

-- ===================================================
-- DISMEMBERMENT SYSTEM
-- Placed here so PlayerLimbs, SendLimbUpdate,
-- GetBody, Fn.ClearLimbBandage & SendCardioUpdate are
-- all in scope as upvalues.
-- ===================================================
Const.NonDismemberableCoreLimbs = {
    abdomen = true,
    thorax = true,
}

function WoundSystem.ApplyDismembermentVisuals(ent, limbsState)
    if not IsValid(ent) or not limbsState then return end

    for limbName, _ in pairs(Const.LimbToBones) do
        Fn.ForEachDismembermentBone(ent, limbName, function(boneIndex)
            ent:ManipulateBoneScale(boneIndex, Vector(1, 1, 1))
        end)
        Fn.SetLimbBodygroupState(ent, limbName, false)
    end

    for limbName, state in pairs(limbsState) do
        if state.dismembered then
            Fn.ForEachDismembermentBone(ent, limbName, function(boneIndex)
                ent:ManipulateBoneScale(boneIndex, Vector(0, 0, 0))
            end)
            Fn.SetLimbBodygroupState(ent, limbName, true)
        end
    end
end

function WoundSystem.Dismember(ply, limbName)
    if not IsValid(ply) or not ply:Alive() then return false end
    if Const.NonDismemberableCoreLimbs[limbName] then return false end

    local limbs = PlayerLimbs[ply]
    if not limbs then return false end

    local state = limbs[limbName]
    if not state or state.dismembered then return false end
    local body = GetBody(ply)
    local visualEnt = (body and IsValid(body.unconsciousRagdoll)) and body.unconsciousRagdoll or ply
    if visualEnt == ply and WoundSystemBridgeActive() and IsValid(ply.FakeRagdoll) then
        visualEnt = ply.FakeRagdoll
    end

    visualEnt:EmitSound("physics/flesh/flesh_squishy_impact_hard4.wav", 65, 90, 1)

    local gorePos = visualEnt:WorldSpaceCenter()
    Fn.ForEachDismembermentBone(visualEnt, limbName, function(boneIndex)
        local bonePos = visualEnt:GetBonePosition(boneIndex)
        if bonePos then gorePos = bonePos end
    end)

    if WoundSystem.BloodEffects and WoundSystem.BloodEffects.Emit then
        WoundSystem.BloodEffects.Emit(gorePos, VectorRand():GetNormalized(), limbName == "head" and 3 or 2.4, "dismember", nil, visualEnt, limbName)
    end

    if WoundSystem.BloodEffects and WoundSystem.BloodEffects.EmitGround then
        WoundSystem.BloodEffects.EmitGround(gorePos, limbName == "head" and 3 or 2.2, "pool", visualEnt)
    end

    if body then
        body.consciousness = math.Clamp((body.consciousness or 100) - 30, 0, 100)
        body.adrenaline = math.Clamp((body.adrenaline or 0) + 40, 0, 100)
    end

    local lowerLimbs = Fn.GetLowerLimbs(limbName)
    for _, childLimb in ipairs(lowerLimbs) do
        local childState = limbs[childLimb]
        if childState then
            childState.dismembered  = true
            childState.infectionSpeed = 0
            childState.infection    = 0
            childState.muscle       = 0
            childState.skin         = 0
            childState.bleed        = 0
            childState.pain         = 0
            childState.isBandaged   = false
            childState.broken       = false
            childState.dislocated   = false
            SendLimbUpdate(ply, childLimb, true)
        end
    end

    local connections = Const.ConnectedLimbs[limbName]
    if connections then
        for _, connLimb in ipairs(connections) do
            local connState = limbs[connLimb]
            if connState and not connState.dismembered then
                connState.skin   = 0
                connState.muscle = math.Clamp(connState.muscle - 50, 0, 100)
                connState.bleed  = 100
                connState.pain   = 100
                Fn.ClearLimbBandage(connState)
                SendLimbUpdate(ply, connLimb, true)
            end
        end
    end

    state.dismembered   = true
    state.infectionSpeed = 0
    state.infection     = 0
    state.muscle        = 0
    state.skin          = 0
    state.bleed         = 0
    state.pain          = 0
    state.isBandaged    = false
    state.broken        = false
    state.dislocated    = false
    SendLimbUpdate(ply, limbName, true)

    WoundSystem.ApplyDismembermentVisuals(ply, limbs)
    if visualEnt ~= ply then
        WoundSystem.ApplyDismembermentVisuals(visualEnt, limbs)
    end
    
    hook.Run("WoundSystem_OnDismember", ply, limbName)

    SendCardioUpdate(ply)
    return true
end

concommand.Add("woundsys_dismember", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local target = ply
    local limb   = args[1] or "arm_L"
    if args[2] then
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(args[2])) then
                target = p
                break
            end
        end
    end
    if IsValid(target) then
        if WoundSystem.Dismember(target, limb) then
            print("[WoundSystem] Dismembered " .. limb .. " on " .. target:Nick())
        else
            print("[WoundSystem] Could not dismember " .. limb .. " on " .. target:Nick())
        end
    end
end)

hook.Add("CreateEntityRagdoll", "WoundSystem_DeathRagdollDismember", function(owner, ragdoll)
    if not WoundSystemHealthEnabled() then return end

    local body = IsValid(owner) and owner:IsPlayer() and BodyState[owner]
    if body and IsValid(body.unconsciousRagdoll) and (body.diedWhileUnconscious or body.unconscious or body.fallingRagdoll) then
        body.diedWhileUnconscious = true
        body.deathRagdollOverride = body.unconsciousRagdoll
        WoundSystem.Health.ScheduleDuplicateDeathRagdollCleanup(owner, body)
        if IsValid(ragdoll) and ragdoll ~= body.unconsciousRagdoll then
            ragdoll:Remove()
        end
        timer.Simple(0, function()
            if IsValid(ragdoll) and ragdoll ~= body.unconsciousRagdoll then
                ragdoll:Remove()
            end
            WoundSystem.Health.CleanupDuplicateDeathRagdolls(owner, body)
        end)
        return
    end

    if IsValid(owner) and owner:IsPlayer() and PlayerLimbs[owner] and IsValid(ragdoll) then
        ragdoll.WoundSystemOwner = owner
        ragdoll:SetNWEntity("WoundSystemOwner", owner)
        ragdoll:SetNWBool("WoundSystemDeathRagdoll", true)
        owner:SetNWEntity("WoundSystemDeathRagdoll", ragdoll)
        if WoundSystem.RagdollVisuals and WoundSystem.RagdollVisuals.CopyFromPlayer then
            WoundSystem.RagdollVisuals.CopyFromPlayer(owner, ragdoll)
        end
        SnapshotCorpseVisualState(owner, ragdoll)
        WoundSystem.Health.Config.ApplyVanillaBloodMode(ragdoll)
        WoundSystem.ApplyDismembermentVisuals(ragdoll, PlayerLimbs[owner])
    end
end)

hook.Add("ShouldCollide", "WoundSystem_UnconsciousRagdollActorCollision", function(ent1, ent2)
    if not WoundSystemHealthEnabled() then return end

    local ragdoll
    local other

    if IsValid(ent1) and ent1.WoundSystemNoActorCollide then
        ragdoll = ent1
        other = ent2
    elseif IsValid(ent2) and ent2.WoundSystemNoActorCollide then
        ragdoll = ent2
        other = ent1
    end

    if not IsValid(ragdoll) or not IsValid(other) then return end
    local isNextBot = other.IsNextBot and other:IsNextBot()
    if other:IsPlayer() or other:IsNPC() or isNextBot then
        return false
    end
end)

hook.Add("SetupPlayerVisibility", "WoundSystem_UnconsciousRagdollPVS", function(ply)
    if not WoundSystemHealthEnabled() then return end

    local body = BodyState and BodyState[ply]
    local ragdoll = body and body.unconsciousRagdoll
    if not IsValid(ragdoll) then return end

    local pvsPos = ragdoll.WorldSpaceCenter and ragdoll:WorldSpaceCenter() or ragdoll:GetPos()
    if pvsPos then
        local plyPos = ply:GetPos()
        if plyPos and plyPos:DistToSqr(pvsPos) <= (768 * 768) then return end

        AddOriginToPVS(pvsPos)
    end
end)

local function ResetClientLimbs(ply)
    LastSentLimbState[ply] = nil

    net.Start("WoundSystem_UpdateLimb")
        net.WriteString("RESET_ALL")
    net.Send(ply)
end

local function BuildShrapnelSession(limbId, shrapnelCount, hasTweezers)
    local session = {
        id = Sessions.NextShrapnelId,
        limbId = limbId,
        hasTweezers = hasTweezers == true,
        pieces = {},
        heldIndex = nil,
        grabArmed = false,
        holdSource = nil,
        holdOffsetX = 0,
        holdOffsetY = 0,
        lastInputAt = CurTime() - GetShrapnelInputDelay()
    }

    Sessions.NextShrapnelId = Sessions.NextShrapnelId + 1
    if Sessions.NextShrapnelId > 16000000 then
        Sessions.NextShrapnelId = 1
    end

    local activePieces = math.Clamp(math.floor(shrapnelCount), 0, WoundSystem.Health.Constants.ShrapnelPieceCount)
    local hiddenPieces = WoundSystem.Health.Constants.ShrapnelPieceCount - activePieces

    for i = 1, WoundSystem.Health.Constants.ShrapnelPieceCount do
        local base = WoundSystem.Health.Constants.ShrapnelBasePos[i]
        local angle = math.Rand(0, math.pi * 2)
        local radius = math.sqrt(math.Rand(0, 1)) * 20
        local jitterX = math.cos(angle) * radius
        local jitterY = math.sin(angle) * radius

        local piece = {
            x = base.x + jitterX,
            y = base.y + jitterY,
            active = true,
            embedded = true
        }

        if i <= hiddenPieces then
            piece.y = piece.y + 8000
            piece.active = false
            piece.embedded = false
        end

        session.pieces[i] = piece
    end

    return session
end

local function ShrapnelItemHasTweezers(ply, slotIdx)
    local slot = ValidateToolSlot(ply, slotIdx)
    if not slot then return false end

    local itemId = NormalizeToolId(slot.toolName)
    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    local use = item and item.use

    return itemId == "TWEEZERS" or (use and use.minigame == "shrapnel" and use.tweezers ~= false)
end

-----------------------------------------------------------
-- SHRAPNEL NETWORKING
-----------------------------------------------------------

net.Receive("WoundSystem_ShrapnelStart", function(_, ply)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local limbId = net.ReadString()
    local slotIdx = 0
    if net.BytesLeft then
        local bytesLeft, bitsLeft = net.BytesLeft()
        if (bitsLeft or 0) >= 3 or (bytesLeft or 0) >= 1 then
            slotIdx = net.ReadUInt(3)
        end
    end
    local existing = Sessions.Shrapnel[ply]
    if existing then
        if existing.limbId == limbId then
            SendShrapnelOpen(ply, existing)
            return
        end
        CloseShrapnelSession(ply, "replaced")
    end

    local state = GetLimbState(ply, limbId)
    if not state then return end
    if state.shrapnel <= 0 then return end

    local hasTweezers = ShrapnelItemHasTweezers(ply, slotIdx)
    if hasTweezers and not ConsumeToolDurability(ply, slotIdx, 1) then return end

    local session = BuildShrapnelSession(limbId, state.shrapnel, hasTweezers)
    Sessions.Shrapnel[ply] = session
    SendShrapnelOpen(ply, session)
    if hasTweezers then
        BroadcastMinigameOneShot(ply, "tweezeruse.ogg", 0.5)
    end
end)

net.Receive("WoundSystem_ShrapnelClose", function(_, ply)
    local session = Sessions.Shrapnel[ply]
    if not session then return end

    local sessionId = net.ReadUInt(24)
    local reason = net.ReadString()
    if sessionId ~= session.id then return end

    CloseShrapnelSession(ply, reason ~= "" and reason or "client_close")
end)

net.Receive("WoundSystem_ShrapnelInput", function(_, ply)
    if not WoundSystemHealthEnabled() then return end

    local session = Sessions.Shrapnel[ply]
    if not session then return end

    local sessionId = net.ReadUInt(24)
    local handX = net.ReadFloat()
    local handY = net.ReadFloat()
    local handVelY = net.ReadFloat()
    
    local startedClick = net.ReadBool()
    local holdingClick = net.ReadBool()
    local stoppedClick = net.ReadBool()
    local handBaseX = handX
    local handBaseY = handY

    if net.BytesLeft then
        local bytesLeft, bitsLeft = net.BytesLeft()
        -- BytesLeft includes a small engine trailer; require a full two-float payload.
        if (bitsLeft or 0) >= 64 or (bytesLeft or 0) >= 8 then
            handBaseX = net.ReadFloat()
            handBaseY = net.ReadFloat()
        end
    end
    local inputSeq = ReadOptionalInputSeq()

    if sessionId ~= session.id then return end
    if not IsValid(ply) or not ply:Alive() then
        CloseShrapnelSession(ply, "dead")
        return
    end

    local now = CurTime()
    local clickEdge = startedClick or stoppedClick
    if now - (session.lastInputAt or 0) < GetShrapnelInputDelay() and not clickEdge then return end
    session.lastInputAt = now
    session.lastAckSeq = inputSeq

    local state = GetLimbState(ply, session.limbId)
    if not state then
        CloseShrapnelSession(ply, "invalid_limb")
        return
    end

    local clickStartedInPullArea = startedClick
        and (handY > WoundSystem.Health.Constants.ShrapnelHandStartY or handBaseY > WoundSystem.Health.Constants.ShrapnelHandStartY)

    if clickStartedInPullArea then
        session.grabArmed = true
    elseif not holdingClick then
        session.grabArmed = false
    end

    -- Shrapnel interaction. The addon hand can lag behind the cursor, so allow
    -- a held click to latch once the grip/base actually reaches a shard.
    if not session.heldIndex and holdingClick and session.grabArmed then
        local closestDist = math.huge
        local closestIdx = nil
        local closestSource = nil
        local closestHandX = handX
        local closestHandY = handY
        local candidates = {
            {x = handX, y = handY, source = "grip"},
            {x = handBaseX, y = handBaseY, source = "base"}
        }

        for idx, piece in ipairs(session.pieces) do
            if piece.active then
                for _, candidate in ipairs(candidates) do
                    local dx = math.abs(candidate.x - piece.x)
                    local dy = math.abs(candidate.y - piece.y)

                    if dx <= WoundSystem.Health.Constants.ShrapnelGrabHalfX and dy <= WoundSystem.Health.Constants.ShrapnelGrabHalfY then
                        local dist = (dx * dx) + (dy * dy)
                        if dist < closestDist then
                            closestDist = dist
                            closestIdx = idx
                            closestSource = candidate.source
                            closestHandX = candidate.x
                            closestHandY = candidate.y
                        end
                    end
                end
            end
        end

        if closestIdx then
            session.heldIndex = closestIdx
            session.holdSource = closestSource
            session.holdOffsetX = session.pieces[closestIdx].x - closestHandX
            session.holdOffsetY = session.pieces[closestIdx].y - closestHandY
        end
    end

    local shouldReleaseHeldShrapnel = stoppedClick or (not holdingClick and not startedClick)

    -- Shrapnel drag physics
    local heldIndex = session.heldIndex
    if heldIndex and session.pieces[heldIndex] and session.pieces[heldIndex].active then
        local heldPiece = session.pieces[heldIndex]
        local dragHandX = session.holdSource == "base" and handBaseX or handX
        local dragHandY = session.holdSource == "base" and handBaseY or handY

        local targetX = dragHandX + session.holdOffsetX
        local targetY = dragHandY + session.holdOffsetY
        local smoothFactor = WoundSystem.Health.Constants.ShrapnelDragSmooth

        if heldPiece.embedded == false then
            heldPiece.x = Lerp(smoothFactor, heldPiece.x, targetX)
            heldPiece.y = Lerp(smoothFactor, heldPiece.y, targetY)
            heldPiece.y = math.Clamp(heldPiece.y, WoundSystem.Health.Constants.ShrapnelMinY, WoundSystem.Health.Constants.ShrapnelFreeMaxY)

            if heldPiece.y <= WoundSystem.Health.Constants.ShrapnelReimpaleY then
                heldPiece.embedded = true
            end
        else
            heldPiece.y = Lerp(smoothFactor, heldPiece.y, targetY)
            heldPiece.y = math.Clamp(heldPiece.y, WoundSystem.Health.Constants.ShrapnelMinY, WoundSystem.Health.Constants.ShrapnelExtractY)

            if heldPiece.y >= WoundSystem.Health.Constants.ShrapnelExtractY then
                heldPiece.y = WoundSystem.Health.Constants.ShrapnelExtractY
                heldPiece.embedded = false
            end

            if heldPiece.embedded ~= false and not session.hasTweezers then
                if math.abs(handVelY) > WoundSystem.Health.Constants.ShrapnelBreakVelY then
                    BreakShrapnelGrasp(ply, session, state)
                    SendShrapnelState(ply, session)
                    return
                end

                if math.abs(heldPiece.x - targetX) > WoundSystem.Health.Constants.ShrapnelBreakXDist then
                    BreakShrapnelGrasp(ply, session, state)
                    SendShrapnelState(ply, session)
                    return
                end
            end
        end
    end

    if shouldReleaseHeldShrapnel then
        session.heldIndex = nil
        session.grabArmed = false
        session.holdSource = nil
    end

    local heldPieceForSound = session.heldIndex and session.pieces[session.heldIndex] or nil
    local shouldPlaySquelch = heldPieceForSound
        and heldPieceForSound.active
        and heldPieceForSound.embedded ~= false

    if shouldPlaySquelch then
        if not session.playingSquelch then
            session.playingSquelch = true
            ply:SendLua([[
                if not WoundSystem.SquelchSound then
                    WoundSystem.SquelchSound = CreateSound(LocalPlayer(), "squelchloop.ogg")
                end
                WoundSystem.SquelchSound:Play()
                WoundSystem.SquelchSound:ChangeVolume(0.8, 0)
            ]])
            net.Start("WoundSystem_MinigameSound_Client")
            net.WriteEntity(ply)
            net.WriteString("squelchloop.ogg")
            net.WriteFloat(0.4)
            net.WriteBool(true)
            net.WriteBool(false)
            net.SendOmit(ply)
        end
    else
        if session.playingSquelch then
            session.playingSquelch = false
            ply:SendLua([[
                if WoundSystem.SquelchSound then
                    WoundSystem.SquelchSound:Stop()
                end
            ]])
            net.Start("WoundSystem_MinigameSound_Client")
            net.WriteEntity(ply)
            net.WriteString("squelchloop.ogg")
            net.WriteFloat(0.4)
            net.WriteBool(true)
            net.WriteBool(true)
            net.SendOmit(ply)
        end
    end

    local remaining = CountRemainingPieces(session)
    state.shrapnel = remaining
    SendLimbUpdate(ply, session.limbId, true)

    if remaining <= 0 and not holdingClick then
        SendShrapnelState(ply, session)
        CloseShrapnelSession(ply, "complete")
        return
    end

    SendShrapnelState(ply, session)
end)

local function BuildDislocationSession(limbId, dislocationTimer, hasWrench)
    local finishX = WoundSystem.Health.Constants.DislocationFinishX
    local finishY = WoundSystem.Health.Constants.DislocationFinishY
    local angle = math.Rand(-math.pi / 3, math.pi / 3)
    local distance = math.Clamp(tonumber(dislocationTimer) or 100, 0, 100) * WoundSystem.Health.Constants.DislocationStartSpread

    local session = {
        id = Sessions.NextDislocationId,
        limbId = limbId,
        hasWrench = hasWrench == true,
        boneX = finishX + (math.cos(angle) * distance),
        boneY = finishY + (math.sin(angle) * distance),
        boneVelX = 0,
        boneVelY = 0,
        dislocationTimer = math.Clamp(tonumber(dislocationTimer) or 100, 0, 100),
        painBlocked = false,
        hitLocked = false,
        hitThisInput = false,
        lastInputAt = CurTime()
    }

    Sessions.NextDislocationId = Sessions.NextDislocationId + 1
    if Sessions.NextDislocationId > 16000000 then
        Sessions.NextDislocationId = 1
    end

    return session
end

local function DislocationItemHasWrench(ply, slotIdx)
    slotIdx = tonumber(slotIdx) or 0
    if slotIdx <= 0 then return false end

    local slot = ValidateToolSlot(ply, slotIdx)
    if not slot or slot.type ~= "tool" then return false end

    local itemId = NormalizeToolId(slot.toolName)
    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    local use = item and item.use
    return itemId == "WRENCH" or (use and use.minigame == "dislocation" and use.wrench ~= false)
end

local WoundSystemDevDebugCVar = CreateConVar("woundsys_dev_debug", "0", FCVAR_CHEAT, "Enable internal WoundSystem development diagnostics.", 0, 1)

local function DislocationSegmentHitsBone(prevX, prevY, curX, curY, boneX, boneY, halfW, halfH)
    prevX = tonumber(prevX) or curX
    prevY = tonumber(prevY) or curY
    curX = tonumber(curX) or prevX
    curY = tonumber(curY) or prevY
    boneX = tonumber(boneX) or 0
    boneY = tonumber(boneY) or 0

    local dx = curX - prevX
    local dy = curY - prevY
    local lenSq = dx * dx + dy * dy
    local t = 0

    if lenSq > 0.0001 then
        t = math.Clamp(((boneX - prevX) * dx + (boneY - prevY) * dy) / lenSq, 0, 1)
    end

    local closestX = prevX + dx * t
    local closestY = prevY + dy * t

    halfW = math.Clamp(tonumber(halfW) or WoundSystem.Health.Constants.DislocationHitHalfW, WoundSystem.Health.Constants.DislocationHitHalfW, 380)
    halfH = math.Clamp(tonumber(halfH) or WoundSystem.Health.Constants.DislocationHitHalfH, WoundSystem.Health.Constants.DislocationHitHalfH, 180)

    local diffX = math.abs(closestX - boneX)
    local diffY = math.abs(closestY - boneY)

    return diffX <= halfW and diffY <= halfH, closestX, closestY, diffX, diffY, halfW, halfH
end

net.Receive("WoundSystem_DislocationStart", function(_, ply)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local limbId = net.ReadString()
    local slotIdx = 0
    if net.BytesLeft then
        local bytesLeft, bitsLeft = net.BytesLeft()
        if (bitsLeft or 0) >= 3 or (bytesLeft or 0) >= 1 then
            slotIdx = net.ReadUInt(3)
        end
    end

    local existing = Sessions.Dislocation[ply]
    if existing then
        if existing.limbId == limbId then
            SendDislocationOpen(ply, existing)
            return
        end
        CloseDislocationSession(ply, "replaced")
    end

    local state = GetLimbState(ply, limbId)
    if not state or not state.dislocated then return end

    local hasWrench = DislocationItemHasWrench(ply, slotIdx)
    local session = BuildDislocationSession(limbId, state.dislocationTimer or 100, hasWrench)
    Sessions.Dislocation[ply] = session
    SendDislocationOpen(ply, session)
    if hasWrench then
        BroadcastMinigameOneShot(ply, "wrenchhit.ogg", 0.5)
    end
end)

net.Receive("WoundSystem_DislocationClose", function(_, ply)
    local session = Sessions.Dislocation[ply]
    if not session then return end

    local sessionId = net.ReadUInt(24)
    local reason = net.ReadString()
    if sessionId ~= session.id then return end

    CloseDislocationSession(ply, reason ~= "" and reason or "client_close")
end)

net.Receive("WoundSystem_DislocationInput", function(_, ply)
    if not WoundSystemHealthEnabled() then return end

    local session = Sessions.Dislocation[ply]
    if not session then return end

    local sessionId = net.ReadUInt(24)
    local handX = net.ReadFloat()
    local handY = net.ReadFloat()
    local handVelX = net.ReadFloat()
    local handVelY = net.ReadFloat()
    local holdingClick = net.ReadBool()
    local stoppedClick = net.ReadBool()
    local prevHandX = handX
    local prevHandY = handY
    local boneHitOffsetX = 0
    local boneHitOffsetY = 0
    local boneHitHalfW = WoundSystem.Health.Constants.DislocationHitHalfW
    local boneHitHalfH = WoundSystem.Health.Constants.DislocationHitHalfH
    if net.BytesLeft then
        local bytesLeft, bitsLeft = net.BytesLeft()
        if (bitsLeft or 0) >= 64 or (bytesLeft or 0) >= 8 then
            prevHandX = net.ReadFloat()
            prevHandY = net.ReadFloat()
        end
        bytesLeft, bitsLeft = net.BytesLeft()
        if (bitsLeft or 0) >= 128 or (bytesLeft or 0) >= 16 then
            boneHitOffsetX = math.Clamp(net.ReadFloat(), -350, 350)
            boneHitOffsetY = math.Clamp(net.ReadFloat(), -220, 220)
            boneHitHalfW = net.ReadFloat()
            boneHitHalfH = net.ReadFloat()
        end
    end
    local inputSeq = ReadOptionalInputSeq()

    if sessionId ~= session.id then return end
    if not IsValid(ply) or not ply:Alive() then
        CloseDislocationSession(ply, "dead")
        return
    end

    local now = CurTime()
    local elapsed = math.Clamp(now - (session.lastInputAt or now), 0.001, 0.2)
    session.lastInputAt = now
    session.lastAckSeq = inputSeq

    local state = GetLimbState(ply, session.limbId)
    local body = BodyState[ply]
    if not state or not body then
        CloseDislocationSession(ply, "invalid_limb")
        return
    end
    if not state.dislocated then
        CloseDislocationSession(ply, "complete")
        return
    end

    if stoppedClick or not holdingClick then
        session.hitLocked = false
    end

    local dragT = math.Clamp(elapsed * WoundSystem.Health.Constants.DislocationBoneDrag, 0, 1)
    session.boneX = math.Clamp((session.boneX or 0) + ((session.boneVelX or 0) * elapsed * WoundSystem.Health.Constants.DislocationBoneMoveMult), -500, 900)
    session.boneY = math.Clamp((session.boneY or 0) + ((session.boneVelY or 0) * elapsed * WoundSystem.Health.Constants.DislocationBoneMoveMult), -500, 500)
    session.boneVelX = Lerp(dragT, session.boneVelX or 0, 0)
    session.boneVelY = Lerp(dragT, session.boneVelY or 0, 0)

    local avgPain = tonumber(body.avgPain or body.averagePain) or 0
    session.painBlocked = avgPain > WoundSystem.Health.Constants.DislocationPainBlock

    local handSpeed = math.sqrt((handVelX or 0) * (handVelX or 0) + (handVelY or 0) * (handVelY or 0))
    local boneSpeed = math.sqrt((session.boneVelX or 0) * (session.boneVelX or 0) + (session.boneVelY or 0) * (session.boneVelY or 0))
    local hitBone, closestX, closestY, hitDiffX, hitDiffY, usedHalfW, usedHalfH = DislocationSegmentHitsBone(
        prevHandX,
        prevHandY,
        handX,
        handY,
        (session.boneX or 0) + boneHitOffsetX,
        (session.boneY or 0) + boneHitOffsetY,
        boneHitHalfW,
        boneHitHalfH
    )

    local canHit = not session.painBlocked
        and not session.hitLocked
        and holdingClick
        and handSpeed >= WoundSystem.Health.Constants.DislocationHitMinHandSpeed
        and boneSpeed <= WoundSystem.Health.Constants.DislocationHitMaxBoneSpeed
        and hitBone

    if WoundSystemDevDebugCVar:GetBool() and (holdingClick or stoppedClick or handSpeed >= 2 or hitBone) then
        local fail = {}
        if session.painBlocked then fail[#fail + 1] = "pain" end
        if session.hitLocked then fail[#fail + 1] = "locked" end
        if not holdingClick then fail[#fail + 1] = "noClick" end
        if handSpeed < WoundSystem.Health.Constants.DislocationHitMinHandSpeed then fail[#fail + 1] = "slowHand" end
        if boneSpeed > WoundSystem.Health.Constants.DislocationHitMaxBoneSpeed then fail[#fail + 1] = "fastBone" end
        if not hitBone then fail[#fail + 1] = "missHitbox" end
        if #fail == 0 then fail[#fail + 1] = "none" end

        local debugLine = string.format(
            "[WS DISLOC SV] %s ply=%s click=%s stop=%s hand=(%.1f,%.1f) prev=(%.1f,%.1f) vel=(%.2f,%.2f) speed=%.2f bone=(%.1f,%.1f) hitCenter=(%.1f,%.1f) closest=(%.1f,%.1f) diff=(%.1f,%.1f) half=(%.1f,%.1f) boneSpeed=%.2f avgPain=%.1f timer=%.1f fail=%s",
            canHit and "HIT" or "NOHIT",
            IsValid(ply) and ply:Nick() or "unknown",
            tostring(holdingClick),
            tostring(stoppedClick),
            handX or 0,
            handY or 0,
            prevHandX or 0,
            prevHandY or 0,
            handVelX or 0,
            handVelY or 0,
            handSpeed,
            session.boneX or 0,
            session.boneY or 0,
            (session.boneX or 0) + boneHitOffsetX,
            (session.boneY or 0) + boneHitOffsetY,
            closestX or 0,
            closestY or 0,
            hitDiffX or 0,
            hitDiffY or 0,
            usedHalfW or 0,
            usedHalfH or 0,
            boneSpeed,
            avgPain,
            session.dislocationTimer or 0,
            table.concat(fail, ",")
        )

        print(debugLine)
        net.Start("WoundSystem_DislocationDebug")
            net.WriteString(debugLine)
        net.Send(ply)
    end

    if canHit then
        if session.hasWrench then
            session.boneVelX = (session.boneVelX or 0) + handVelX * 24
            session.boneVelY = (session.boneVelY or 0) + handVelY * 24
            state.pain = math.Clamp((state.pain or 0) + math.Rand(4, 10), 0, 100)
        else
            local hitMult = math.Rand(0.7, 1.3) * 20
            session.boneVelX = (session.boneVelX or 0) + handVelX * hitMult
            session.boneVelY = (session.boneVelY or 0) + handVelY * hitMult
            state.pain = math.Clamp((state.pain or 0) + math.Rand(15, 24), 0, 100)
            if math.Rand(0, 1) > 0.995 then
                ApplyFracture(ply, session.limbId, state)
            end
        end

        session.hitLocked = true
        session.hitThisInput = true
        ply:SendLua("surface.PlaySound(\"boneHit.ogg\")")
        SendLimbUpdate(ply, session.limbId, true)
        if SendCardioUpdate then SendCardioUpdate(ply) end
    end

    session.dislocationTimer = DislocationTimerFromBone(session)
    state.dislocationTimer = session.dislocationTimer

    if session.dislocationTimer < WoundSystem.Health.Constants.DislocationSuccessTimer then
        state.dislocated = false
        state.dislocationTimer = 0
        session.dislocationTimer = 0
        if WoundSystemHappiness and WoundSystemHappiness.Add then
            WoundSystemHappiness.Add(ply, 3)
        else
            body.happiness = math.Clamp((body.happiness or 0) + 3, -100, 100)
        end
        SendLimbUpdate(ply, session.limbId, true)
        SendDislocationState(ply, session)
        CloseDislocationSession(ply, "complete")
        return
    end

    SendLimbUpdate(ply, session.limbId, true)
    SendDislocationState(ply, session)
end)


-----------------------------------------------------------
-- BANDAGE NETWORKING
-----------------------------------------------------------

net.Receive("WoundSystem_BandageStart", function(_, ply)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local limbId = net.ReadString()
    local slotIdx = net.ReadUInt(3)
    local slot = ValidateToolSlot(ply, slotIdx)
    if not slot or slot.durability <= 0 then return end

    local itemId = NormalizeToolId(slot.toolName)
    local profile = Fn.GetBandageProfile(itemId)
    if not profile then return end

    local existing = Sessions.Bandage[ply]
    
    if existing then
        if existing.limbId == limbId and existing.slotIdx == slotIdx and existing.itemId == itemId then
            SendBandageOpen(ply, existing)
            return
        end
        CloseBandageSession(ply, "replaced")
    end

    local state = GetLimbState(ply, limbId)
    if not state then return end
    if profile.requireBleed and state.bleed <= 0 then return end

    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    local use = item and item.use
    if use and WoundSystem.Items and WoundSystem.Items.LimbAllowed and not WoundSystem.Items.LimbAllowed(use, limbId) then return end
    if use and type(use.canUse) == "function" then
        local ctx = BuildMedicalItemContext(ply, item, slotIdx, slot, limbId)
        if use.canUse(ctx) == false then return end
    end

    if slot.durability < ((use and use.minDurability) or 0) then return end

    if WoundSystemHappiness and WoundSystemHappiness.RollAllowsAction then
        if not WoundSystemHappiness.RollAllowsAction(ply, "") then
            return
        end
    end

    local session = {
        id = Sessions.NextBandageId,
        limbId = limbId,
        slotIdx = slotIdx,
        itemId = itemId,
        mode = profile.mode or "gauze",
        lastInputAt = CurTime()
    }

    Sessions.NextBandageId = Sessions.NextBandageId + 1
    if Sessions.NextBandageId > 16000000 then Sessions.NextBandageId = 1 end

    Sessions.Bandage[ply] = session

    SendBandageOpen(ply, session)
end)

net.Receive("WoundSystem_BandageClose", function(_, ply)
    local sessionId = net.ReadUInt(24)
    local session = Sessions.Bandage[ply]
    if session and session.id == sessionId then
        CloseBandageSession(ply, "client_close")
    end
end)

net.Receive("WoundSystem_BandageInput", function(_, ply)
    if not WoundSystemHealthEnabled() then return end

    local session = Sessions.Bandage[ply]
    if not session then return end

    local sessionId = net.ReadUInt(24)
    local degreesMoved = net.ReadFloat()
    local inputSeq = ReadOptionalInputSeq()

    if sessionId ~= session.id then return end
    if not IsValid(ply) or not ply:Alive() then
        CloseBandageSession(ply, "dead")
        return
    end

    local state = GetLimbState(ply, session.limbId)
    if not state then
        CloseBandageSession(ply, "invalid_limb")
        return
    end

    degreesMoved = math.Clamp(tonumber(degreesMoved) or 0, 0, 360)
    if degreesMoved <= 0 then return end
    session.lastInputAt = CurTime()
    session.lastAckSeq = inputSeq

    local itemId = NormalizeToolId(session.itemId or "GAUZE")
    local profile = Fn.GetBandageProfile(itemId)
    if not profile then
        CloseBandageSession(ply, "invalid_tool")
        return
    end

    local slotIdx = session.slotIdx
    local slot = ValidateToolSlot(ply, slotIdx, itemId)
    if not slot or slot.durability <= 0 then
        CloseBandageSession(ply, "no_tool")
        return
    end

    local wrapFraction = degreesMoved / 360
    local durCost = wrapFraction * (profile.durabilityPerWrap or WoundSystem.Health.Constants.BandageDurabilityPerWrap)
    durCost = math.min(durCost, slot.durability)
    if durCost <= 0 then return end

    if not ConsumeToolDurability(ply, slotIdx, durCost) then
        CloseBandageSession(ply, "no_tool")
        return
    end

    if session.deferred then
        -- Z-City SWEP: only measure the work, the effect is applied when the minigame is completed
        session.deferredUsed = (session.deferredUsed or 0) + durCost
        session.deferredWrap = (session.deferredWrap or 0) + wrapFraction
        if type(session.onProgress) == "function" then
            local ok, err = pcall(session.onProgress, ply, session, durCost, wrapFraction)
            if not ok then ErrorNoHalt("[WoundSystem] external minigame onProgress failed: " .. tostring(err) .. "\n") end
        end
        if Sessions.Bandage[ply] ~= session then return end -- onProgress ended the minigame
        SendMinigameAck(ply, MINIGAME_ACK_BANDAGE, session)
        return
    end

    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    local ctx = BuildMedicalItemContext(ply, item, slotIdx, slot, session.limbId)
    ctx.wrapFraction = wrapFraction
    ctx.degreesMoved = degreesMoved
    ctx.profile = profile

    if ApplyBandageProfile(ctx, profile) == false then
        return
    end

    if type(profile.applyWrap) == "function" then
        if profile.applyWrap(ctx) == false then
            return
        end
    end

    SendLimbUpdate(ply, session.limbId, true)
    SendMinigameAck(ply, MINIGAME_ACK_BANDAGE, session)
end)

-----------------------------------------------------------
-- SYRINGE NETWORKING
-----------------------------------------------------------

local function GetSyringeInputDelay()
    return 1 / math.max(WoundSystem.Health.Constants.SyringeInputHz, 1)
end

net.Receive("WoundSystem_SyringeStart", function(_, ply)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local limbId = net.ReadString()
    local slotIdx = net.ReadUInt(3)
    local slot = ValidateToolSlot(ply, slotIdx)
    if not slot or slot.durability <= 0 then return end

    local itemId = NormalizeToolId(slot.toolName)
    local profile = GetSyringeProfile(itemId)
    if not profile then return end

    local existing = Sessions.Syringe[ply]
    if existing then
        if existing.limbId == limbId and existing.slotIdx == slotIdx and existing.itemId == itemId then
            SendSyringeOpen(ply, existing)
            return
        end
        CloseSyringeSession(ply, "replaced")
    end

    local state = GetLimbState(ply, limbId)
    if not state then return end

    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    local use = item and item.use
    if use and WoundSystem.Items and WoundSystem.Items.LimbAllowed and not WoundSystem.Items.LimbAllowed(use, limbId) then return end
    if use and type(use.canUse) == "function" then
        local ctx = BuildMedicalItemContext(ply, item, slotIdx, slot, limbId)
        if use.canUse(ctx) == false then return end
    end
    if slot.durability < ((use and use.minDurability) or 0.01) then return end

    if WoundSystemHappiness and WoundSystemHappiness.RollAllowsAction then
        if not WoundSystemHappiness.RollAllowsAction(ply, "") then
            return
        end
    end

    local session = {
        id = Sessions.NextSyringeId,
        limbId = limbId,
        slotIdx = slotIdx,
        itemId = itemId,
        lastInputAt = CurTime()
    }

    Sessions.NextSyringeId = Sessions.NextSyringeId + 1
    if Sessions.NextSyringeId > 16000000 then Sessions.NextSyringeId = 1 end

    Sessions.Syringe[ply] = session
    if WoundSystem.Statuses and profile.woundStatus ~= false and profile.woundStatus ~= "" then
        WoundSystem.Statuses.Set(state, profile.woundStatus or "SYRINGE_WOUND", true)
        SendLimbUpdate(ply, limbId, true)
    end
    SendSyringeOpen(ply, session)
end)

net.Receive("WoundSystem_SyringeClose", function(_, ply)
    local sessionId = net.ReadUInt(24)
    net.ReadString()
    local session = Sessions.Syringe[ply]
    if session and session.id == sessionId then
        CloseSyringeSession(ply, "client_close")
    end
end)

net.Receive("WoundSystem_SyringeInput", function(_, ply)
    if not WoundSystemHealthEnabled() then return end

    local session = Sessions.Syringe[ply]
    if not session then return end

    local sessionId = net.ReadUInt(24)
    local depth = net.ReadFloat()
    local brokeNeedle = net.ReadBool()
    local inputSeq = ReadOptionalInputSeq()

    if sessionId ~= session.id then return end
    if not IsValid(ply) or not ply:Alive() then
        CloseSyringeSession(ply, "dead")
        return
    end

    local state = GetLimbState(ply, session.limbId)
    if not state then
        CloseSyringeSession(ply, "invalid_limb")
        return
    end

    if brokeNeedle then
        session.lastAckSeq = inputSeq
        state.shrapnel = math.max(tonumber(state.shrapnel) or 0, 1)
        state.pain = math.Clamp((state.pain or 0) + 20, 0, 100)
        SendLimbUpdate(ply, session.limbId, true)
        ply:EmitSound("bullethit.ogg", 70, 100, 0.8)
        CloseSyringeSession(ply, "needle_break")
        return
    end

    depth = math.Clamp(tonumber(depth) or 0, 0, 1)
    local now = CurTime()
    local elapsed = math.Clamp(now - (session.lastInputAt or now), 0, 0.2)
    if elapsed < GetSyringeInputDelay() then return end
    session.lastInputAt = now
    session.lastAckSeq = inputSeq

    if depth <= 0 then
        SendMinigameAck(ply, MINIGAME_ACK_SYRINGE, session)
        return
    end

    local itemId = NormalizeToolId(session.itemId or "")
    local profile = GetSyringeProfile(itemId)
    if not profile then
        CloseSyringeSession(ply, "invalid_tool")
        return
    end

    local slotIdx = session.slotIdx
    local slot = ValidateToolSlot(ply, slotIdx, itemId)
    if not slot or slot.durability <= 0 then
        CloseSyringeSession(ply, "no_tool")
        return
    end

    local maxDur = WoundSystem.Items and WoundSystem.Items.GetMax and WoundSystem.Items.GetMax(itemId) or 100
    local durCost = math.min(depth * elapsed * (profile.durabilityPerSecond or WoundSystem.Health.Constants.SyringeDurabilityPerSecond), slot.durability)
    if durCost <= 0 then return end

    if not ConsumeToolDurability(ply, slotIdx, durCost) then
        CloseSyringeSession(ply, "no_tool")
        return
    end

    if session.deferred then
        -- Z-City SWEP: only measure the injected amount, the effect is applied when the minigame is completed
        session.deferredUsed = (session.deferredUsed or 0) + durCost
        if type(session.onProgress) == "function" then
            local ok, err = pcall(session.onProgress, ply, session, durCost)
            if not ok then ErrorNoHalt("[WoundSystem] external minigame onProgress failed: " .. tostring(err) .. "\n") end
        end
        if Sessions.Syringe[ply] ~= session then return end -- onProgress ended the minigame
        SendSyringeState(ply, session)

        local left = ValidateToolSlot(ply, slotIdx, itemId)
        if not left or left.durability <= 0.001 then
            CloseSyringeSession(ply, "empty")
        end
        return
    end

    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    local ctx = BuildMedicalItemContext(ply, item, slotIdx, slot, session.limbId)
    ctx.syringeFraction = durCost / math.max(maxDur, 1)
    ctx.injectDepth = depth
    ctx.durabilityCost = durCost
    ctx.profile = profile

    if ApplySyringeProfile(ctx, profile) == false then
        SendSyringeState(ply, session)
        return
    end

    SendLimbUpdate(ply, session.limbId, true)
    if SendCardioUpdate then SendCardioUpdate(ply) end
    SendSyringeState(ply, session)

    local updatedSlot = ValidateToolSlot(ply, slotIdx, itemId)
    if not updatedSlot or updatedSlot.durability <= 0.001 then
        CloseSyringeSession(ply, "empty")
    end
end)

local function GetAedProfile(itemId)
    itemId = NormalizeToolId(itemId)
    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    local use = item and item.use
    if not use or use.minigame ~= "aed" then return nil end

    local aed = type(use.aed) == "table" and use.aed or {}
    return {
        startCost = tonumber(aed.startCost) or 1,
        analyzeCost = tonumber(aed.analyzeCost) or 2,
        shockCost = tonumber(aed.shockCost) or 14,
        analyzeTime = tonumber(aed.analyzeTime) or 4.25,
        chargeTime = tonumber(aed.chargeTime) or 3.5,
        shockChance = tonumber(aed.shockChance) or 1
    }
end

local function ApplyAedShock(ply, session, profile)
    local body = BodyState[ply]
    local limbs = PlayerLimbs[ply]
    local limb = limbs and limbs[session.limbId]
    if not body or not limb then return false end

    limb.skin = math.Clamp((limb.skin or 100) - 5, 0, 100)
    limb.pain = math.Clamp((limb.pain or 0) + 20, 0, 100)

    if session.limbId == "thorax" then
        local inCardiacArrest = (body.heartRate or 70) < 20
        if math.Rand(0, 1) < (profile.shockChance or 1) or inCardiacArrest then
            body.fibrillationProgress = 0
            if inCardiacArrest and math.Rand(0, 1) < 0.2 then
                body.heartRate = 200
            end
        end

        body.defibShockedFrames = 20
        body.heartProg = -1
        body.bloodPressure = 40
    end

    SendLimbUpdate(ply, session.limbId, true)
    SendCardioUpdate(ply)
    return true
end

function WoundSystem.Health.IsAedShockRecommended(body, limbId)
    if not body or limbId ~= "thorax" then return false end
    if (body.fibrillationProgress or 0) > 0 then return true end
    return (body.heartRate or 70) < 20
end

net.Receive("WoundSystem_AEDStart", function(_, ply)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local limbId = net.ReadString()
    local slotIdx = net.ReadUInt(3)
    local slot = ValidateToolSlot(ply, slotIdx)
    if not slot or slot.durability <= 0 then return end

    local itemId = NormalizeToolId(slot.toolName)
    local profile = GetAedProfile(itemId)
    if not profile then return end

    local state = GetLimbState(ply, limbId)
    if not state then return end
    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    local use = item and item.use
    if slot.durability <= ((use and use.minDurability) or 2) then return end

    local existing = Sessions.Aed[ply]
    if existing then
        if existing.limbId == limbId and existing.slotIdx == slotIdx and existing.itemId == itemId then
            SendAedOpen(ply, existing)
            return
        end
        CloseAedSession(ply, "replaced")
    end

    if not ConsumeToolDurability(ply, slotIdx, profile.startCost) then return end

    local session = {
        id = Sessions.NextAedId,
        limbId = limbId,
        slotIdx = slotIdx,
        itemId = itemId,
        state = 0,
        lastInputAt = CurTime()
    }

    Sessions.NextAedId = Sessions.NextAedId + 1
    if Sessions.NextAedId > 16000000 then Sessions.NextAedId = 1 end

    Sessions.Aed[ply] = session
    SendAedOpen(ply, session)
end)

net.Receive("WoundSystem_AEDClose", function(_, ply)
    local sessionId = net.ReadUInt(24)
    net.ReadString()
    local session = Sessions.Aed[ply]
    if session and session.id == sessionId then
        CloseAedSession(ply, "client_close")
    end
end)

net.Receive("WoundSystem_AEDInput", function(_, ply)
    if not WoundSystemHealthEnabled() then return end

    local session = Sessions.Aed[ply]
    if not session then return end

    local sessionId = net.ReadUInt(24)
    local action = net.ReadUInt(3)
    local inputSeq = ReadOptionalInputSeq()
    if sessionId ~= session.id then return end
    session.lastInputAt = CurTime()
    session.lastAckSeq = inputSeq
    if not IsValid(ply) or not ply:Alive() then
        CloseAedSession(ply, "dead")
        return
    end

    local profile = GetAedProfile(session.itemId)
    if not profile then
        CloseAedSession(ply, "invalid_tool")
        return
    end

    local slot = ValidateToolSlot(ply, session.slotIdx, session.itemId)
    if not slot or slot.durability <= 0 then
        CloseAedSession(ply, "no_tool")
        return
    end

    if action == 1 and session.state == 0 then
        session.state = 1
        session.analyzeStartedAt = CurTime()
        SendAedState(ply, session)

        timer.Simple(profile.analyzeTime, function()
            if not IsValid(ply) then return end
            local current = Sessions.Aed[ply]
            if current ~= session or current.state ~= 1 then return end
            if not ConsumeToolDurability(ply, current.slotIdx, profile.analyzeCost) then
                CloseAedSession(ply, "no_charge")
                return
            end

            local body = BodyState[ply]
            current.state = WoundSystem.Health.IsAedShockRecommended(body, current.limbId) and 2 or 5
            SendAedState(ply, current)
        end)
        return
    end

    if action == 2 and session.state == 2 then
        session.state = 3
        SendAedState(ply, session)

        timer.Simple(profile.chargeTime, function()
            if not IsValid(ply) then return end
            local current = Sessions.Aed[ply]
            if current ~= session or current.state ~= 3 then return end
            if not ConsumeToolDurability(ply, current.slotIdx, profile.shockCost) then
                CloseAedSession(ply, "no_charge")
                return
            end

            ApplyAedShock(ply, current, profile)
            current.state = 4
            SendAedState(ply, current)
        end)
        return
    end

    SendMinigameAck(ply, MINIGAME_ACK_AED, session)
end)

local function TryUseInventoryMedicalItem(ply, slotIdx, itemId, limbId)
    if not IsValid(ply) or not ply:Alive() then return false end
    if not PlayerLimbs[ply] then InitPlayer(ply) end

    itemId = NormalizeToolId(itemId)
    local slot = ValidateToolSlot(ply, slotIdx, itemId)
    if not slot then return false end

    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    local use = item and item.use
    local consumeAllDurability = use and use.consumeAllDurability == true
    local consumeDurability = use and tonumber(use.consumeDurability) or nil
    local minDur = (use and use.minDurability) or (consumeAllDurability and 0.01) or (use and use.durabilityCost) or 0
    local cost = (use and use.durabilityCost) or 0

    if use and use.requireFull then
        local maxDur = WoundSystem.Items.GetMax(itemId)
        if slot.durability < maxDur then return false end
    elseif slot.durability < minDur then
        return false
    end

    if use and WoundSystem.Items and WoundSystem.Items.LimbAllowed and not WoundSystem.Items.LimbAllowed(use, limbId) then
        return false
    end

    if use and type(use.canUse) == "function" then
        local ctx = BuildMedicalItemContext(ply, item, slotIdx, slot, limbId)
        if use.canUse(ctx) == false then return false end
    end

    if WoundSystemHappiness and WoundSystemHappiness.RollAllowsAction then
        if not WoundSystemHappiness.RollAllowsAction(ply, "") then
            return false
        end
    end

    if UseRegisteredMedicalItem(ply, itemId, limbId, slotIdx, slot) == false then
        return false
    end

    if consumeAllDurability then
        return ConsumeToolDurability(ply, slotIdx, math.max(tonumber(slot.durability) or 0, 0))
    end

    if consumeDurability and consumeDurability > 0 then
        return ConsumeToolDurability(ply, slotIdx, math.min(consumeDurability, math.max(tonumber(slot.durability) or 0, 0)))
    end

    if cost > 0 then
        return ConsumeToolDurability(ply, slotIdx, cost)
    end

    return true
end

-----------------------------------------------------------
-- No WoundSystem inventory / world items: Z-City SWEPs are the items (see hg.WoundBridge.SwepHeal).
-- A removed tourniquet goes back to the player as the Z-City SWEP.
-----------------------------------------------------------

function WoundSystem.Health.ReturnAttachedMedicalItem(ply, itemId, durability, preferredSlot)
    if not IsValid(ply) or not ply:Alive() then return false end

    itemId = NormalizeToolId(itemId)
    if itemId == "TOURNIQUET" and not ply:HasWeapon("weapon_tourniquet") then
        local wep = ply:Give("weapon_tourniquet")
        return IsValid(wep)
    end

    return false
end


-----------------------------------------------------------
-- HOOKS & GENERAL LOGIC
-----------------------------------------------------------



local function GetPlayerPersistKey(ply)
    if not IsValid(ply) then return nil end
    local id = ply:SteamID64()
    if id and id ~= "" and id ~= "0" then return id end
    id = ply:SteamID()
    if id and id ~= "" then
        return string.gsub(id, ":", "_")
    end
    if game.SinglePlayer() then return "singleplayer" end
    return "player_" .. ply:EntIndex()
end

local function PlayerIsInChangeLevelTrigger(ply)
    if not IsValid(ply) then return false end
    local pPos = ply:GetPos()
    local triggers = ents.FindByClass("trigger_changelevel")
    for _, tr in ipairs(triggers) do
        if IsValid(tr) then
            local mins, maxs = tr:WorldSpaceAABB()
            if mins and maxs then
                local margin = 48
                if pPos.x >= mins.x - margin and pPos.x <= maxs.x + margin
                   and pPos.y >= mins.y - margin and pPos.y <= maxs.y + margin
                   and pPos.z >= mins.z - margin and pPos.z <= maxs.z + margin then
                    return true
                end
            end
        end
    end
    return false
end

hook.Add("StartTouch", "WoundSystem_ChangeLevelDetect", function(trigger, ent)
    if IsValid(trigger) and trigger:GetClass() == "trigger_changelevel" and IsValid(ent) and ent:IsPlayer() then
        ent._WoundSystemInChangeLevel = true
        ent._WoundSystemChangeLevelTime = CurTime()
        if SavePlayerPersistData then
            pcall(SavePlayerPersistData, ent)
            if WoundSystem and WoundSystem.DebugPersist then
                print("[WoundSystem Persist] Saved persist data on StartTouch for", ent:Nick(), ent:SteamID())
            end
        end
    end
end)

hook.Add("Touch", "WoundSystem_ChangeLevelTouch", function(trigger, ent)
    if IsValid(trigger) and trigger:GetClass() == "trigger_changelevel" and IsValid(ent) and ent:IsPlayer() then
        ent._WoundSystemInChangeLevel = true
        ent._WoundSystemChangeLevelTime = CurTime()
        -- defer so SavePlayerPersistData is resolved at call time, not definition time
        timer.Simple(0, function()
            if IsValid(ent) and SavePlayerPersistData then
                pcall(SavePlayerPersistData, ent)
                if WoundSystem and WoundSystem.DebugPersist then
                    print("[WoundSystem Persist] Saved persist data on Touch for", ent:Nick(), ent:SteamID())
                end
            end
        end)
    end
end)

hook.Add("EndTouch", "WoundSystem_ChangeLevelEndTouch", function(trigger, ent)
    if IsValid(trigger) and trigger:GetClass() == "trigger_changelevel" and IsValid(ent) and ent:IsPlayer() then
        timer.Simple(2, function()
            if IsValid(ent) and not PlayerIsInChangeLevelTrigger(ent) then
                ent._WoundSystemInChangeLevel = false
            end
        end)
    end
end)

local function SavePlayerPersistData(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local cv = WoundSystem.Health.Config.CVars.PersistAcrossMaps
    local mode = cv and cv:GetInt() or 0
    if mode <= 0 then return end

    local isTransition = false
    if mode == 2 then
        isTransition = true
    elseif mode == 1 then
        if ply._WoundSystemInChangeLevel == true then
            isTransition = true
        elseif ply._WoundSystemChangeLevelTime and (CurTime() - ply._WoundSystemChangeLevelTime) < 5 then
            isTransition = true
        elseif PlayerIsInChangeLevelTrigger(ply) then
            isTransition = true
        end
    end

    if not isTransition then return end

    local body = BodyState[ply]
    local limbs = PlayerLimbs[ply]
    local inv = PlayerInventory[ply]

    if not body and not limbs and not inv then return end

    local cleanBody = {}
    if body then
        for k, v in pairs(body) do
            local t = type(v)
            if t == "number" or t == "string" or t == "boolean" then
                cleanBody[k] = v
            elseif t == "table" and (k == "timedBodyEffects" or k == "lastFurBloodRegions") then
                cleanBody[k] = table.Copy(v)
            end
        end
        cleanBody.unconsciousRagdoll = nil
        cleanBody.deathRagdollOverride = nil
        cleanBody.lastDamageAttacker = nil
        cleanBody.lastDamageInflictor = nil
        cleanBody.fallingRagdoll = false
        cleanBody.fallingRagdollWakeTime = 0
        cleanBody.fallingRagdollReason = nil
    end

    local cleanLimbs = {}
    if limbs then
        for limbName, state in pairs(limbs) do
            cleanLimbs[limbName] = {}
            for k, v in pairs(state) do
                local t = type(v)
                if t == "number" or t == "string" or t == "boolean" then
                    cleanLimbs[limbName][k] = v
                elseif t == "table" and k == "customStatuses" then
                    cleanLimbs[limbName][k] = table.Copy(v)
                end
            end
        end
    end

    local cleanInv = {}
    if inv then
        for i = 1, (WoundSystem.Health.Constants.InventorySlots or 5) do
            local slot = inv[i]
            if slot and type(slot) == "table" then
                cleanInv[i] = {
                    type = slot.type or "empty",
                    toolName = slot.toolName,
                    durability = slot.durability
                }
            else
                cleanInv[i] = { type = "empty" }
            end
        end
    end

    local hevPower = tonumber(ply.WoundSystemHEVPower) or tonumber(ply:Armor()) or 0
    local hevEquipped = (ply.HEVEquipped == true or ply.WoundSystemHEVEquipped == true) and (hevPower > 0 or tonumber(ply:Armor()) or 0 > 0)

    local payload = {
        body = cleanBody,
        limbs = cleanLimbs,
        inv = cleanInv,
        health = ply:Health(),
        armor = ply:Armor(),
        hevPower = hevPower,
        hevEquipped = hevEquipped,
        fromMap = game.GetMap(),
        isTransition = isTransition,
        time = os.time()
    }

    local key = GetPlayerPersistKey(ply)
    if not key then return end

    file.CreateDir("woundsystem/persist")
    file.Write("woundsystem/persist/" .. key .. ".json", util.TableToJSON(payload))
end

local function LoadPlayerPersistData(ply)
    local cv = WoundSystem.Health.Config.CVars.PersistAcrossMaps
    local mode = cv and cv:GetInt() or 0
    if mode <= 0 then return false end

    local key = GetPlayerPersistKey(ply)
    if not key then return false end

    local filePath = "woundsystem/persist/" .. key .. ".json"
    if not file.Exists(filePath, "DATA") then return false end

    local raw = file.Read(filePath, "DATA")
    file.Delete(filePath)

    if not raw or raw == "" then return false end

    local data = util.JSONToTable(raw)
    if not data or not istable(data) then return false end

    if data.time and (os.time() - data.time) > 900 then
        return false
    end

    if mode == 1 and not data.isTransition then
        return false
    end

    if data.body and istable(data.body) then
        if not BodyState[ply] then
            InitBody(ply)
        end
        local body = BodyState[ply]
        for k, v in pairs(data.body) do
            body[k] = v
        end
        body.unconscious = false
        body.unconsciousRagdoll = nil
        body.fallingRagdoll = false
        body.fallingRagdollWakeTime = 0
        body.fallingRagdollReason = nil
        ply:SetNWFloat("BloodAmount", body.bloodVolume or 100)
        ply:SetNWFloat("BrainHealth", body.brainHealth or 100)
        ply:SetNWFloat("Consciousness", body.consciousness or 100)
        ply:SetNWBool("WoundSystemUnconscious", false)
    end

    if data.limbs and istable(data.limbs) then
        PlayerLimbs[ply] = PlayerLimbs[ply] or {}
        for limbName, state in pairs(data.limbs) do
            if istable(state) then
                PlayerLimbs[ply][limbName] = PlayerLimbs[ply][limbName] or table.Copy(defaultLimbState)
                for k, v in pairs(state) do
                    PlayerLimbs[ply][limbName][k] = v
                end
            end
        end
    end

    if data.inv and istable(data.inv) then
        PlayerInventory[ply] = {}
        for i = 1, (WoundSystem.Health.Constants.InventorySlots or 5) do
            local slot = data.inv[i]
            if slot and istable(slot) then
                PlayerInventory[ply][i] = {
                    type = slot.type or "empty",
                    toolName = slot.toolName,
                    durability = slot.durability
                }
            else
                PlayerInventory[ply][i] = CreateEmptyInventorySlot()
            end
        end
        SyncInventoryToClient(ply)
    end

    if data.health and data.health > 0 then
        ply:SetHealth(math.Clamp(data.health, 1, ply:GetMaxHealth()))
    end
    if data.armor then
        ply:SetArmor(math.max(0, data.armor))
    end

    if data.hevPower ~= nil then
        local power = math.Clamp(tonumber(data.hevPower) or 0, 0, 100)
        ply.WoundSystemHEVPower = power
        if (data.hevEquipped == true) then
            ply.WoundSystemHEVEquipped = true
            ply.HEVEquipped = true
            ply.WoundSystemHEVBootOnline = true
        else
            ply.WoundSystemHEVEquipped = false
            ply.HEVEquipped = false
            ply.WoundSystemHEVBootOnline = false
        end
        if power > 0 then
            ply:SetArmor(power)
        end
    end

    return true
end

hook.Add("PlayerSpawn", "WoundSystem_SpawnSync", function(ply)
    if OverrideSpawn then return end -- Z-City get-up from fake ragdoll, not a real respawn
    WoundSystem.Health.BumpLifecycleSeq(ply)
    ply:SetNWEntity("WoundSystemDeathRagdoll", NULL)
    if not WoundSystemHealthEnabled() then
        WoundSystem.Health.Config.ApplyVanillaBloodMode(ply)
        return
    end

    local restoredFromTransition = LoadPlayerPersistData(ply)
    -- only count as "had first spawn" once we're sure we didn't restore from a transition
    if not restoredFromTransition then
        ply._WoundSystemHadFirstSpawn = true
    end

    if not restoredFromTransition then
        if BodyState[ply] then
            RestorePlayerOnRespawn(ply)
        end
        ResetPlayerRagdollCamera(ply)
        CloseShrapnelSession(ply, "respawn")
        CloseDislocationSession(ply, "respawn")
        CloseBandageSession(ply, "respawn")
        CloseSyringeSession(ply, "respawn")
        CloseAedSession(ply, "respawn")
        InitPlayer(ply)
        ResetPlayerInventory(ply)
    else
        ResetPlayerRagdollCamera(ply)
        CloseShrapnelSession(ply, "respawn")
        CloseDislocationSession(ply, "respawn")
        CloseBandageSession(ply, "respawn")
        CloseSyringeSession(ply, "respawn")
        CloseAedSession(ply, "respawn")
    end

    ResetClientLimbs(ply)
    if restoredFromTransition and PlayerLimbs[ply] then
        for limbId in pairs(PlayerLimbs[ply]) do
            SendLimbUpdate(ply, limbId, true)
        end
    end
    SendCardioUpdate(ply)
    SendDismembermentVisualReset(ply)
    SendDismembermentVisuals(ply)
    timer.Simple(1, function()
        if IsValid(ply) then SendAllDismembermentVisuals(ply) end
    end)
end)

WoundSystem.Health.HandleDamage = function(ent, dmginfo)
    if IsValid(ent) and ent:IsPlayer() and ent._WoundSystemApplyingAttributedDeath then
        return
    end

    if not WoundSystemHealthEnabled() then return end

    -- ==========================================
    -- 1. UNCONSCIOUS RAGDOLL DAMAGE HANDLING
    -- ==========================================
    if ent.WoundSystemWakeBridgeRagdoll then
        dmginfo:SetDamage(0)
        return true
    end

    if ent.WoundSystemUnconsciousRagdoll then
        local owner = ent.WoundSystemOwner
        if not IsValid(owner) and ent.GetNWEntity then
            owner = ent:GetNWEntity("WoundSystemOwner")
        end

        local body = IsValid(owner) and BodyState and BodyState[owner] or nil
        if WoundSystem.Health.IsLiveUnconsciousRagdollProxy(ent, owner, body) then
            if body and body.isGodMode then
                dmginfo:SetDamage(0)
                return true
            end

            local dmg = dmginfo:GetDamage()
            local rawDmg = dmg
            NormalizeMeleeDamageType(dmginfo)
            WoundSystem.Health.RecordDamageAttribution(owner, body, dmginfo, true)
            Fn.EmitBulletHitSound(ent, dmginfo)
            EmitDamageBloodEffect(ent, dmginfo, dmg)

            -- PhysicsCollide handles impact damage via ProcessImpactDamage.
            -- Ignore DMG_CRUSH here to prevent massive double-dipping on physics impacts.
            if dmginfo:IsDamageType(DMG_CRUSH) then
                dmginfo:SetDamage(0)
                return
            end

            if dmginfo:IsDamageType(DMG_RADIATION) and dmg > 0 then
                body.radiationSickness = math.Clamp((body.radiationSickness or 0) + (dmg * 0.65), 0, 100)
                if owner:WaterLevel() >= 2 then
                    body.radiationExposureTimer = math.max(body.radiationExposureTimer or 0, 20)
                end
            end

            local ragdollLimbs = {}
            local isAreaRagdollDamage = dmginfo:IsDamageType(DMG_BLAST)
                or dmginfo:IsDamageType(DMG_BURN)
                or dmginfo:IsDamageType(DMG_DIRECT)
            local ragdollPushDir = Fn.GetKnockdownDirection(owner, dmginfo)

            -- AOE Damage Spread for Ragdolls
            if isAreaRagdollDamage then
                if dmginfo:IsDamageType(DMG_BLAST) or dmginfo:IsDamageType(DMG_DIRECT) then
                    Fn.AddHearingLoss(body, dmg * 0.9)
                end
                for limbName, _ in pairs(PlayerLimbs[owner] or {}) do
                    table.insert(ragdollLimbs, limbName)
                end
                dmg = dmg / 4 -- Distribute damage to prevent instant death
                Fn.PushRagdollFromDamage(ent, ragdollPushDir, rawDmg or dmg, 0.18)
            else
                table.insert(ragdollLimbs, Fn.ResolveLivingLimb(owner, GuessRagdollDamageLimb(ent, dmginfo)))
            end

            for _, limb in ipairs(ragdollLimbs) do
                local state = GetLimbState(owner, limb)
                    if state then
                        if isAreaRagdollDamage then
                            WoundSystem.Health.SuppressLimbPhysicsDamage(owner, limb, 0.16)
                        elseif (rawDmg or dmg) > 0 then
                            local pushScale = 0.16
                            if Fn.IsBulletImpactDamage(dmginfo) then
                                local physicalTier = Fn.GetGunshotPhysicalResponseTier(rawDmg or dmg)
                                pushScale = physicalTier >= 4 and 0.08 or 0.24
                            end

                            WoundSystem.Health.SuppressLimbPhysicsDamage(owner, limb, 0.18)
                            if not Fn.PushRagdollLimbFromDamage(ent, limb, ragdollPushDir, rawDmg or dmg, pushScale) then
                                Fn.PushRagdollFromDamage(ent, ragdollPushDir, rawDmg or dmg, pushScale * 0.45)
                            end
                        end

                        if Fn.IsBloodVisualDamage(dmginfo) then
                            Fn.AddFurBloodToLimb(owner, limb, math.Clamp(dmg / 10, 0.35, 3.5))
                            EmitDamageBodyFlow(ent, dmginfo, dmg, limb)
                        end

                        if Fn.IsBulletImpactDamage(dmginfo) and ShouldUseOgGunshotDamage(dmginfo, rawDmg or dmg) then
                            if ApplyOgGunshotDamage(owner, body, limb, state, dmginfo, rawDmg or dmg) then
                                dmginfo:SetDamage(0)
                                return true
                            end
                            SendLimbUpdate(owner, limb, true)
                            continue
                        end

                        state.muscle = math.Clamp(state.muscle - (dmg * 0.8), 0, 100)
                    state.skin = math.Clamp(state.skin - (dmg * 0.45), 0, 100)
                    state.pain = math.Clamp(state.pain + (dmg * 0.9), 0, 100)

                    if dmginfo:IsDamageType(DMG_BURN) or dmginfo:IsDamageType(DMG_DIRECT) then
                        state.bleed = math.Clamp(state.bleed - (dmg * 0.3), 0, 100)
                    else
                        state.bleed = math.Clamp(state.bleed + (dmg * 0.45), 0, 100)
                        Fn.ClearLimbBandage(state)
                    end

                    if limb == "head" then
                        Fn.AddHearingLoss(body, dmg * 0.45)
                        body.consciousness = math.Clamp((body.consciousness or 100) - (dmg * 1.6), 0, 100)

                        if Fn.IsBulletImpactDamage(dmginfo) then
                            local ballisticDamage = math.max(rawDmg or 0, dmg or 0)
                            local brainTrauma = ballisticDamage * (dmginfo:IsDamageType(DMG_BUCKSHOT) and 1.35 or 1.7)
                            body.consciousness = 0
                            body.unconscious = true
                            body.wasUnconscious = true
                            body.brainHealth = math.Clamp((body.brainHealth or 100) - brainTrauma, 0, 100)
                            body.brainDamageBuffer = math.max(body.brainDamageBuffer or 0, brainTrauma)
                            state.muscle = 0
                            state.pain = 100

                            if body.brainHealth <= 0 or ballisticDamage >= 36 then
                                body.brainHealth = 0
                                body.brainDead = true
                                PreserveUnconsciousRagdollForDeath(owner, body)
                                SendLimbUpdate(owner, limb, true)
                                SendCardioUpdate(owner, true)
                                WoundSystem.Health.QueueDamageFeedback(owner, limb, dmginfo, rawDmg or dmg, body, state, true)
                                WoundSystem.Health.KillWithAttribution(owner, body, "ballistic_head_trauma")
                                dmginfo:SetDamage(0)
                                return true
                            end
                        else
                            if dmg > 18 then
                                body.brainHealth = math.Clamp((body.brainHealth or 100) - (dmg * 0.10), 0, 100)
                            end
                            if dmg > 32 then
                                body.brainHealth = math.Clamp((body.brainHealth or 100) - (dmg * 0.2), 0, 100)
                            end
                        end
                    elseif limb == "thorax" and dmg > 12 then
                        body.internalBleeding = body.internalBleeding + (dmg * 0.45)
                        if dmg > 18 then
                            body.hemothorax = math.Clamp(body.hemothorax + (dmg * 0.08), 0, 100)
                        end
                    elseif limb == "abdomen" and dmg > 12 then
                        body.internalBleeding = body.internalBleeding + (dmg * 0.55)
                    end

                    if Fn.RollShouldDismember(state, dmginfo, dmg, dmginfo:GetDamage()) then
                        WoundSystem.Dismember(owner, limb)
                        if Fn.IsCriticalLimb(limb) and owner:Alive() then
                            PreserveUnconsciousRagdollForDeath(owner, body)
                            WoundSystem.Health.KillWithAttribution(owner, body, "critical_limb")
                        end
                    end

                    WoundSystem.Health.QueueDamageFeedback(owner, limb, dmginfo, rawDmg or dmg, body, state, body.unconscious or body.fallingRagdoll)
                    SendLimbUpdate(owner, limb, true)
                end
            end
            SendCardioUpdate(owner, true)
        end

        dmginfo:SetDamage(0)
        return true
    end

    if not ent:IsPlayer() then return end

    local ply = ent
    if not PlayerLimbs[ply] then InitPlayer(ply) end

    local body = GetBody(ply)
    if body and body.isGodMode then
        dmginfo:SetDamage(0)
        return true
    end

    local dmg = dmginfo:GetDamage()
    local rawDmg = dmg
    NormalizeMeleeDamageType(dmginfo)
    local affectedLimbs = {}
    local fallSpeed = 0
    local fallForce = 0
    WoundSystem.Health.RecordDamageAttribution(ply, body, dmginfo, false)
    Fn.EmitBulletHitSound(ply, dmginfo)
    EmitDamageBloodEffect(ply, dmginfo, dmg)

    if not Fn.IsBulletImpactDamage(dmginfo) then
        TryWeaponKnockdown(ply, body, dmginfo, dmg)
    end

    if dmginfo:IsDamageType(DMG_RADIATION) and dmg > 0 then
        body.radiationSickness = math.Clamp((body.radiationSickness or 0) + (dmg * 0.65), 0, 100)
        if ply:WaterLevel() >= 2 then
            body.radiationExposureTimer = math.max(body.radiationExposureTimer or 0, 20)
        end
    end
    if (dmginfo:IsDamageType(DMG_BLAST) or dmginfo:IsDamageType(DMG_DIRECT)) and dmg > 0 then
        Fn.AddHearingLoss(body, dmg * 0.9)
    end

    local isShockDamage = dmginfo:IsDamageType(DMG_SHOCK)
    local atk = dmginfo:GetAttacker()
    if not isShockDamage and IsValid(atk) then
        local atkClass = atk:GetClass()
        if atkClass == "npc_vortigaunt" or atkClass == "npc_rollermine" or atkClass == "point_tesla" then
            isShockDamage = true
        end
    end

    if isShockDamage and dmg > 0 then
        local limbs = PlayerLimbs[ply]
        if limbs then
            for limbName, state in pairs(limbs) do
                if state and not state.dismembered then
                    state.shockStrengthLoss = math.Clamp((state.shockStrengthLoss or 0) + (dmg * 0.025), 0, 0.95)
                    state.muscle = math.Clamp((state.muscle or 100) - (dmg * 0.15), 5, 100)
                    state.muscleStrength = WoundSystem.Health.LimbForce.ComputeTotalForce(state, body, limbName)
                    SendLimbUpdate(ply, limbName, true)
                end
            end
        end
        body.shock = math.Clamp((body.shock or 0) + (dmg * 0.5), 0, 100)
    end

    -- ==========================================
    -- 2. ACTIVE PLAYER DAMAGE HANDLING
    -- ==========================================
    if dmginfo:IsFallDamage() then
        fallSpeed = WoundSystem.Health.GetRecentFallSpeed(ply, dmg)
        fallForce = WoundSystem.Health.FallSpeedToImpactForce(fallSpeed)
        if ply._woundSystemLastFallOnFloater then
            fallForce = fallForce * 0.5
        end

        affectedLimbs = {"foot_L", "foot_R"}
        local jumpSpeed = (body and body.jumpSpeed) or 6.5
        if fallForce > jumpSpeed * 1.8 then
            table.insert(affectedLimbs, "crus_L")
            table.insert(affectedLimbs, "crus_R")
        end

    -- AOE Blast Damage Spread for Active Players
    elseif dmginfo:IsDamageType(DMG_BLAST) then
        for limbName, _ in pairs(PlayerLimbs[ply]) do
            table.insert(affectedLimbs, limbName)
        end
        dmg = dmg / 4

    elseif dmginfo:IsDamageType(DMG_BURN) or dmginfo:IsDamageType(DMG_DIRECT) then
        for limbName, _ in pairs(PlayerLimbs[ply]) do
            table.insert(affectedLimbs, limbName)
        end
        dmg = dmg / 4

    else
        local hitgroup = ply:LastHitGroup()
        local singleLimb = Const.HitgroupToLimb[hitgroup]

        if ply._WoundBridgeLimb then
            -- Z-City bridge: the limb was resolved from the exact hit bone, no random pick.
            singleLimb = ply._WoundBridgeLimb
        elseif dmginfo:IsDamageType(DMG_CLUB) or dmginfo:IsDamageType(DMG_SLASH) or hitgroup == HITGROUP_GENERIC or not singleLimb then
            singleLimb = Fn.PickRandomDamageLimb(ply)
        end

        singleLimb = Fn.ResolveLivingLimb(ply, singleLimb)
        table.insert(affectedLimbs, singleLimb)
    end

    -- ==========================================
    -- NEUROGENIC SHOCK: Sudden massive pain spike
    -- ==========================================
    local painSpikeDmg = dmginfo:IsFallDamage() and (fallForce * 2.0) or (rawDmg or dmg)
    if painSpikeDmg >= 40 and not body.unconscious and not Fn.IsBulletImpactDamage(dmginfo) then
        local shockDuration = math.Rand(1.5, 3.5)
        Fn.AddBodyShock(body, math.Clamp(painSpikeDmg * 0.5, 20, 100))
        body.fallingRagdoll = true
        body.fallingRagdollWakeTime = CurTime() + shockDuration
        body.fallingRagdollReason = "neurogenic_shock"
        TryCreateUnconsciousRagdoll(ply, body)
    end

    for _, limb in ipairs(affectedLimbs) do
        local state = PlayerLimbs[ply][limb]
        if not state then continue end
        local usedOgGunshotDamage = false

        if Fn.IsBloodVisualDamage(dmginfo) then
            Fn.AddFurBloodToLimb(ply, limb, math.Clamp(dmg / 10, 0.35, 3.5))
            EmitDamageBodyFlow(ply, dmginfo, dmg, limb)
        end

        if dmginfo:IsFallDamage() then
            ply._nextLimbPhysicsDamage = ply._nextLimbPhysicsDamage or {}
            ply._nextLimbPhysicsDamage[limb] = math.max(ply._nextLimbPhysicsDamage[limb] or 0, CurTime() + 0.12)
            ProcessImpactDamage(ply, limb, fallForce)

        elseif Fn.IsBulletImpactDamage(dmginfo) then
            -- ==========================================
            -- BULLET: C:U-style wound package
            -- Every real bullet hit uses the original-style wound response.
            -- Low damage maps to a low playerDamageMultiplier instead of
            -- falling back to the older addon bullet math.
            -- ==========================================
            if ShouldUseOgGunshotDamage(dmginfo, rawDmg or dmg) then
                usedOgGunshotDamage = true
                if ApplyOgGunshotDamage(ply, body, limb, state, dmginfo, rawDmg or dmg) then
                    dmginfo:SetDamage(0)
                    return true
                end
            else
            local isHighCaliber = dmg > 30
            Fn.AddGunshotShrapnel(state, ply)

            if isHighCaliber then
                -- Overpenetration: massive tissue destruction, clean through
                state.muscle = math.Clamp(state.muscle - dmg * 4.5, 0, 100)
                state.skin   = math.Clamp(state.skin   - dmg * 2.5, 0, 100)
                state.pain   = math.Clamp(state.pain   + dmg * 5.0, 0, 100)
                -- Exit wound causes double bleed
                state.bleed  = math.Clamp(state.bleed  + dmg * 0.9, 0, 100)
                Fn.ClearLimbBandage(state)
                -- High-caliber shatters bone on hit (not critical limbs -- no bone to shatter there)
                if not Fn.IsCriticalLimb(limb) then
                    ApplyFracture(ply, limb, state)
                end
                -- No lodged bullet -- overpenetrated
            else
                -- Low-caliber tumbles and lodges inside
                state.muscle = math.Clamp(state.muscle - dmg * 3.0, 0, 100)
                state.skin   = math.Clamp(state.skin   - dmg * 1.0, 0, 100)
                state.pain   = math.Clamp(state.pain   + dmg * 4.0, 0, 100)
                state.bleed  = math.Clamp(state.bleed  + dmg * 0.4, 0, 100)
                Fn.ClearLimbBandage(state)
                -- Lower chance of fracture from tumbling
                if math.random(100) <= 20 then
                    ApplyFracture(ply, limb, state)
                end
            end

            -- Limb-specific bullet consequences
            if limb == "head" then
                local ballisticDamage = math.max(rawDmg or 0, dmg or 0)
                local buckshotScale = dmginfo:IsDamageType(DMG_BUCKSHOT) and 0.85 or 1
                local brainTrauma = ballisticDamage * (isHighCaliber and 2.125 or 1.575) * buckshotScale

                state.muscle = 0
                state.pain = 100
                state.bleed = math.Clamp((state.bleed or 0) + (ballisticDamage * 0.625), 0, 100)
                Fn.ClearLimbBandage(state)

                body.consciousness = 0
                body.unconscious = true
                body.wasUnconscious = true
                body.brainHealth = math.Clamp((body.brainHealth or 100) - brainTrauma, 0, 100)
                body.brainDamageBuffer = math.max(body.brainDamageBuffer or 0, brainTrauma)
                Fn.AddHearingLoss(body, ballisticDamage * 0.6)

                if body.brainHealth <= 0 or ballisticDamage >= 36 then
                    body.brainHealth = 0
                    body.brainDead = true
                    PreserveUnconsciousRagdollForDeath(ply, body)
                    SendLimbUpdate(ply, limb, true)
                    SendCardioUpdate(ply, true)
                    WoundSystem.Health.QueueDamageFeedback(ply, limb, dmginfo, rawDmg or dmg, body, state, true)
                    WoundSystem.Health.KillWithAttribution(ply, body, "ballistic_head_trauma")
                    dmginfo:SetDamage(0)
                    return true
                elseif not body.fallingRagdoll then
                    body.fallingRagdoll = true
                    body.fallingRagdollWakeTime = CurTime() + math.Rand(4, 9)
                    body.fallingRagdollReason = "ballistic_head_trauma"
                    TryCreateUnconsciousRagdoll(ply, body)
                end
            elseif limb == "thorax" then
                if dmg > 10 then
                    body.internalBleeding = body.internalBleeding + (dmg * (isHighCaliber and 0.575 or 0.375))
                end
                if dmg > 15 then
                    body.hemothorax = math.Clamp(body.hemothorax + (dmg * (isHighCaliber and 0.14 or 0.075)), 0, 100)
                end
                if dmg > 24 then
                    body.bloodPressure = math.max(0, (body.bloodPressure or 120) - (dmg * 0.175))
                end
                state.pain = math.Clamp(state.pain + (dmg * 4.0), 0, 100)
                body.adrenaline = math.Clamp((body.adrenaline or 0) + (dmg * 0.5), 0, 100)
            elseif limb == "abdomen" then
                if dmg > 10 then
                    body.internalBleeding = body.internalBleeding + (dmg * (isHighCaliber and 0.525 or 0.35))
                end
                state.pain = math.Clamp(state.pain + (dmg * 4.5), 0, 100)
            else
                -- Major vessel check (femoral, brachial arteries etc.)
                local vesselBleed = Fn.GetMajorVesselBleed(limb, dmg)
                if vesselBleed > 0 then
                    -- High-caliber destroys artery outright, far more bleed
                    state.bleed = math.Clamp(state.bleed + (isHighCaliber and vesselBleed * 1.8 or vesselBleed), 0, 100)
                    state.pain  = math.Clamp(state.pain  + (dmg * 0.5), 0, 100)
                    Fn.ClearLimbBandage(state)
                end
            end

            if state.infectionSpeed <= 0 then state.infectionSpeed = 0.5 end
            end

        elseif dmginfo:IsDamageType(DMG_BLAST) then
            -- ==========================================
            -- EXPLOSION: Shrapnel shower + shockwave fractures
            -- ==========================================
            state.muscle = math.Clamp(state.muscle - dmg * 0.8, 0, 100)
            state.skin   = math.Clamp(state.skin   - dmg * 0.45, 0, 100)
            state.pain   = math.Clamp(state.pain   + dmg * 0.9, 0, 100)

            if not Fn.IsCriticalLimb(limb) then
                -- Shrapnel shower: multiple fragments per blast
                local fragCount = 0
                if rawDmg >= 20 then fragCount = fragCount + (math.random() < 0.6 and 1 or 0) end
                if rawDmg >= 40 then fragCount = fragCount + (math.random() < 0.5 and 1 or 0) end
                if rawDmg >= 70 then fragCount = fragCount + (math.random() < 0.4 and 1 or 0) end
                state.shrapnel = math.min(state.shrapnel + fragCount, 5)

                -- Shockwave fractures
                local fracChance = math.Clamp((rawDmg - 25) / 75, 0, 0.85)
                if math.random() < fracChance then
                    ApplyFracture(ply, limb, state)
                end
            else
                -- Blast to core body: heavy internal damage
                if rawDmg > 20 then
                    body.internalBleeding = body.internalBleeding + (dmg * 0.55)
                end
                if rawDmg > 30 and limb == "thorax" then
                    body.hemothorax = math.Clamp(body.hemothorax + (dmg * 0.1), 0, 100)
                end
            end
            state.bleed = math.Clamp(state.bleed + dmg * 0.45, 0, 100)
            Fn.ClearLimbBandage(state)

        elseif dmginfo:IsDamageType(DMG_SLASH) then
            -- ==========================================
            -- SLASH: Artery laceration chance scales with damage
            -- ==========================================
            state.muscle = math.Clamp(state.muscle - dmg * 0.3, 0, 100)
            state.skin   = math.Clamp(state.skin   - dmg * 1.8, 0, 100)
            state.pain   = math.Clamp(state.pain   + dmg * 0.5, 0, 100)
            -- Base bleed from the wound
            state.bleed  = math.Clamp(state.bleed  + dmg * 1.0, 0, 100)
            Fn.ClearLimbBandage(state)

            -- Artery laceration: chance scales sharply with damage
            local arteryChance = math.Clamp((dmg - 8) / 40, 0, 0.85)
            if math.random() < arteryChance then
                -- Artery hit: massive uncontrollable bleed, double the wound bleed
                state.bleed = math.Clamp(state.bleed + dmg * 2.0, 0, 100)
                state.pain  = math.Clamp(state.pain  + dmg * 1.5, 0, 100)
            end

            -- Deep slash to critical limbs causes internal bleeding
            if Fn.IsCriticalLimb(limb) and dmg > 20 then
                body.internalBleeding = body.internalBleeding + (dmg * 0.4)
            end

            if state.infectionSpeed <= 0 then state.infectionSpeed = 1.5 end

        elseif dmginfo:IsDamageType(DMG_CLUB) then
            -- ==========================================
            -- BLUNT: Bone crush + concussion ragdoll
            -- ==========================================
            state.muscle = math.Clamp(state.muscle - dmg * 1.0, 0, 100)
            state.skin   = math.Clamp(state.skin   - dmg * 0.2, 0, 100)
            state.pain   = math.Clamp(state.pain   + dmg * 1.5, 0, 100)

            if Fn.IsCriticalLimb(limb) and dmg > 25 then
                body.internalBleeding = body.internalBleeding + (dmg * 0.35)
            end

            -- Heavy blunt to head/thorax: concussion ragdoll
            if (limb == "head" or limb == "thorax") and dmg > 20 and not body.unconscious then
                local stunDur = math.Rand(1.0, 2.5)
                body.fallingRagdoll = true
                body.fallingRagdollWakeTime = CurTime() + stunDur
                body.fallingRagdollReason = "concussion"
                TryCreateUnconsciousRagdoll(ply, body)
            end

            -- Heavy blunt to limbs: crush the muscle entirely + fracture
            if dmg > 35 then
                ApplyFracture(ply, limb, state)
                state.muscle = 0  -- Completely crushed
                state.pain   = math.Clamp(state.pain + math.random(60, 100), 0, 100)
            elseif dmg > 20 then
                -- Moderate blunt: high fracture chance
                if math.random(100) <= 55 then
                    ApplyFracture(ply, limb, state)
                end
            end

        elseif dmginfo:IsDamageType(DMG_BURN) or dmginfo:IsDamageType(DMG_DIRECT) then
            state.muscle = math.Clamp(state.muscle - dmg * 0.5, 0, 100)
            state.skin   = math.Clamp(state.skin   - dmg * 2.0, 0, 100)
            state.pain   = math.Clamp(state.pain   + dmg * 2.0, 0, 100)
            state.infectionSpeed = 0
            state.bleed  = math.Clamp(state.bleed  - dmg * 0.5, 0, 100)

        else
            state.muscle = math.Clamp(state.muscle - dmg,       0, 100)
            state.skin   = math.Clamp(state.skin   - dmg * 0.6, 0, 100)
            state.pain   = math.Clamp(state.pain   + dmg * 0.8, 0, 100)
            if dmg > 8 then
                state.bleed = math.Clamp(state.bleed + dmg * 0.4, 0, 100)
                Fn.ClearLimbBandage(state)
            end
        end

        if limb == "head" and not usedOgGunshotDamage then
            Fn.AddHearingLoss(body, dmg * 0.45)
            body.consciousness = math.Clamp((body.consciousness or 100) - (dmg * 3.5), 0, 100)

            if dmg > 15 then
                body.brainHealth = math.Clamp((body.brainHealth or 100) - (dmg * 0.8), 0, 100)
            end

            if dmg > 30 then
                body.brainHealth = math.Clamp((body.brainHealth or 100) - (dmg * 2.0), 0, 100)
            end

            if dmg > 5 and math.random() < 0.25 then
                body.brainHealth = math.Clamp((body.brainHealth or 100) - (dmg * 0.1), 0, 100)
            end
        end

        -- Dismemberment check
        if Fn.RollShouldDismember(state, dmginfo, dmg, rawDmg) then
            WoundSystem.Dismember(ply, limb)
            if Fn.IsCriticalLimb(limb) and ply:Alive() then
                PreserveUnconsciousRagdollForDeath(ply, body)
                WoundSystem.Health.KillWithAttribution(ply, body, "critical_limb")
            end
        end

        WoundSystem.Health.QueueDamageFeedback(ply, limb, dmginfo, rawDmg or dmg, body, state, body.unconscious or body.fallingRagdoll)
        SendLimbUpdate(ply, limb, true)
    end

    if dmginfo:IsFallDamage() and fallForce > ((body and body.jumpSpeed) or 6.5) * 2.0 then
        if not body.unconscious then
            body.fallingRagdoll = true
            body.fallingRagdollWakeTime = CurTime() + 3.0
            body.fallingRagdollReason = "fall"
            TryCreateUnconsciousRagdoll(ply, body)
            local feedbackLimb = affectedLimbs[1]
            WoundSystem.Health.QueueDamageFeedback(ply, feedbackLimb, dmginfo, rawDmg or dmg, body, feedbackLimb and PlayerLimbs[ply] and PlayerLimbs[ply][feedbackLimb] or nil, true)
        end
    end

    if not dmginfo:IsFallDamage() and dmg > 5 then
        body.adrenaline = math.Clamp((body.adrenaline or 0) + (dmg * 1.2), 0, 100)
    end

    SendCardioUpdate(ply, body and (body.unconscious or body.fallingRagdoll))
    dmginfo:SetDamage(0)
end

hook.Add("EntityTakeDamage", "WoundSystem_Damage", function(ent, dmginfo)
    -- With Z-City the damage is pre-processed by Z-City (armor, penetration, ragdoll redirect)
    -- and forwarded through hg.WoundBridge.ApplyDamage, which sets WB.InDamage while calling us.
    local WB = WoundSystemBridgeActive()
    if WB and not WB.InDamage then return end
    return WoundSystem.Health.HandleDamage(ent, dmginfo)
end)

local function LimbPhysiologyTick(dt)
    if not WoundSystemHealthEnabled() then return end

    for ply, limbs in pairs(PlayerLimbs) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local body = GetBody(ply)
        if body.isGodMode then continue end
        WoundSystem.Health.ApplyFrozenNeeds(body)

        local healingMult = WoundSystem.Health.Config.CvFloat(WoundSystem.Health.Config.CVars.HealingRate, 1)
        local hungerHeal = WoundSystem.Health.Config.ComputeHungerLimbHeal(body)
        local sleepingMult = (body.sleeping or body.unconscious) and 1.4 or 1

        body.bleedingSpeedMultiplier = WoundSystem.Health.Config.ComputeBleedingSpeedMultiplier(body)
        body.hungerLimbHealCurrent = hungerHeal
        body.bleedClottingSpeed = WoundSystem.Health.Config.ComputeBleedClottingSpeed(body)

        local totalFurBlood = 0
        local furBloodRegions = Fn.EmptyFurBloodRegions()

        for limbName, state in pairs(limbs) do
            if state.dismembered then
                state.skin = 0
                state.muscle = 0
                state.pain = 0
                state.bleed = 0
                state.muscleStrength = 0
                state.infection = 0
                state.infectionSpeed = 0
                state.broken = false
                state.dislocated = false
                state.splinted = false
                state.tourniqueted = false
                state.tourniquetDurability = nil
                state.chilled = false
                state.isBandaged = false
                state.blockedBleeding = false
                state.furBloodAmount = 0
                state.customStatuses = {}
                SendLimbUpdate(ply, limbName)
                continue
            end

            state.splinted = false
            state.tourniqueted = false
            state.chilled = false

            if WoundSystem.Statuses and WoundSystem.Statuses.TickState then
                WoundSystem.Statuses.TickState(state, dt, {
                    ply = ply,
                    limbId = limbName,
                    limb = state,
                    body = body,
                    limbs = limbs
                })
            end

            state.disinfectTime = math.max(0, state.disinfectTime - dt)

            -- C#: body.bloodVolume -= totalBleedAmount * bleedSpeedMult * dt
            local totalBleedAmount = (state.bleed or 0) * (state.blockedBleeding and 0 or 1)
            if totalBleedAmount > 0 then
                body.bloodVolume = math.max(-100, (body.bloodVolume or 100) - (totalBleedAmount * body.bleedingSpeedMultiplier * dt))
                state.furBloodAmount = math.Clamp((state.furBloodAmount or 0) + (WoundSystem.Health.Constants.FurBloodGainPerSecond * totalBleedAmount * dt), 0, WoundSystem.Health.Constants.FurBloodMax)
            else
                state.furBloodAmount = math.Clamp((state.furBloodAmount or 0) - (WoundSystem.Health.Constants.FurBloodDryPerSecond * dt), 0, WoundSystem.Health.Constants.FurBloodMax)
            end

            -- Infection contraction
            if state.infection <= 0 and state.infectionSpeed <= 0 and state.skin < 80 then
                local catchChance = 1 - math.pow(39 / 40, dt)
                if math.random() < catchChance then
                    local infectionThreshold = Lerp((state.skin / 100) / 0.8, 1, 0.77) - (state.bleed * 0.007)
                    if math.random() > infectionThreshold then
                        state.infectionSpeed = 1.0
                    end
                end
            end

            -- Infection progression
            if state.infection > 0 or state.infectionSpeed > 0 then
                local immunityMod = body.immunityMult or 1
                if state.disinfectTime > 0 then
                    immunityMod = immunityMod - 1.7
                end

                local infSpeed = (7.2 * immunityMod * state.infectionSpeed) / 60
                state.infection = state.infection + (infSpeed * dt)

                if state.infection > 100 then state.infection = 100 end
                if state.infection < 0 then
                    state.infection = 0
                    state.infectionSpeed = 0
                end
            else
                state.infection = math.Clamp(state.infection - (0.5 * dt), 0, 100)
            end

            if state.infection > 90 then
                local connections = Const.ConnectedLimbs[limbName]
                if connections then
                    for _, connLimb in ipairs(connections) do
                        local clState = limbs[connLimb]
                        if clState and clState.infection <= 0 and clState.infectionSpeed <= 0 then
                            clState.infectionSpeed = math.max(0.5, state.infectionSpeed * 0.8)
                        end
                    end
                end
            end

            -- Pain equilibrium (C# Limb.Update -- always runs)
            local painTarget = 15 - (state.skin or 100) * 0.15 + (state.infection or 0) * 0.1
            local painApproachRate = ((state.pain or 0) > painTarget) and 1 or 0.6
            state.pain = math.Clamp(math.Approach(state.pain or 0, painTarget, painApproachRate * dt), 0, 100)
            if (state.shrapnel or 0) > 0 then
                state.pain = math.Clamp(state.pain + (1 * dt), 0, 100)
            end
            if body.temperature < 32 then
                state.pain = math.max(0, state.pain - (5 * dt))
            end

            -- Bleed clotting + bandage slow (C# Limb.Update)
            local shrapnelClotMult = (state.shrapnel or 0) > 0 and 0 or 1
            local bandageClotTerm = 0
            if (state.bandageSlowAmount or 0) > 0 then
                bandageClotTerm = 1.25 * dt
            end

            local bleedReduction = dt * body.bleedClottingSpeed * shrapnelClotMult * healingMult + bandageClotTerm
            state.bleed = math.Clamp((state.bleed or 0) - bleedReduction, 0, 100 - (state.skin or 100))

            state.bandageSlowAmount = math.max(0, (state.bandageSlowAmount or 0) - (1.25 * dt))
            state.skinHealAmount = math.max(0, (state.skinHealAmount or 0) - (0.5 * dt))

            local limbHealingMult = healingMult
            local bodyEffects = {}
            if WoundSystem.LimbMuscle and WoundSystem.LimbMuscle.Tick then
                _, bodyEffects = WoundSystem.LimbMuscle.Tick(state, limbName, body, dt, limbHealingMult)
            end

            if bodyEffects.zeroRespiratory then
                body.respiratoryRate = 0
            end

            if bodyEffects.internalBleeding then
                body.internalBleeding = (body.internalBleeding or 0) + bodyEffects.internalBleeding
            end

            -- Skin heal (C# SkinHealRate)
            local canSkinHeal = (state.shrapnel or 0) == 0 and not Fn.LimbIsInfected(state) and (body.hunger or 100) > 0
            if canSkinHeal then
                local skinRate = 0.055 * sleepingMult
                    * (((state.skin or 100) > 10) and 1 or 0.25)
                    * (((state.bleed or 0) > 1) and 0.2 or 1)
                    * hungerHeal
                    * limbHealingMult
                state.skin = math.Clamp((state.skin or 100) + (skinRate * dt), 0, 100)
            end
            if (state.skinHealAmount or 0) > 0 then
                state.skin = math.Clamp((state.skin or 100) + (0.5 * dt), 0, 100)
            end

            if state.dislocated then
                local splintMult = state.splinted and 2 or 1
                state.dislocationTimer = math.max(0, state.dislocationTimer - (dt * WoundSystem.Health.Config.CvFloat(WoundSystem.Health.Config.CVars.DislocationHealSpeed, 0.07) * limbHealingMult * splintMult))
                if state.dislocationTimer <= 0 then
                    state.dislocated = false
                    state.dislocationTimer = 0
                end
            else
                state.dislocationTimer = 0
            end

            if state.broken then
                local splintMult = state.splinted and 2.5 or 1
                state.boneHealTimer = math.max(0, state.boneHealTimer - (dt * WoundSystem.Health.Config.CvFloat(WoundSystem.Health.Config.CVars.BoneHealSpeed, 0.043) * limbHealingMult * splintMult))
                if state.boneHealTimer <= 0 then
                    state.broken = false
                    state.boneHealTimer = 0
                end
            else
                state.boneHealTimer = 0
            end

            if state.hevBraceTimer and state.hevBraceTimer > 0 then
                state.hevBraceTimer = state.hevBraceTimer - dt
                if state.hevBraceTimer <= 0 then
                    state.hevBraceTimer = 0
                    state.hevBrace = false
                    if state.splinted and state.splintItemId == "HEV_BRACE" then
                        state.splinted = false
                        state.splintItemId = nil
                        state.splintDurability = nil
                        if WoundSystem.Statuses then
                            WoundSystem.Statuses.Clear(state, "SPLINTED")
                        end
                    end
                end
            end

            if (state.shockStrengthLoss or 0) > 0 then
                state.shockStrengthLoss = math.max(0, (state.shockStrengthLoss or 0) - (dt * 0.05))
            end

            -- C# totalForce → muscleStrength (stroke weakens affected limbs)
            state.muscleStrength = WoundSystem.Health.LimbForce.ComputeTotalForce(state, body, limbName)

            local furBloodAmount = state.furBloodAmount or 0
            local furBloodRegion = WoundSystem.Health.Constants.FurBloodRegionByLimb[limbName]
            totalFurBlood = totalFurBlood + furBloodAmount
            if furBloodRegion then
                furBloodRegions[furBloodRegion] = (furBloodRegions[furBloodRegion] or 0) + furBloodAmount
            end
            SendLimbUpdate(ply, limbName)
        end

        body.bloodVolume = math.Clamp(body.bloodVolume, -100, 200)
        ply:SetNWFloat("BloodAmount", body.bloodVolume)

        if math.abs((body.lastFurBloodTotal or 0) - totalFurBlood) > 0.05 then
            body.lastFurBloodTotal = totalFurBlood
            ply:SetNWFloat("WoundSystemFurBlood", totalFurBlood)
        end

        body.lastFurBloodRegions = body.lastFurBloodRegions or Fn.EmptyFurBloodRegions()
        for _, region in ipairs(WoundSystem.Health.Constants.FurBloodRegions) do
            local regionBlood = furBloodRegions[region] or 0
            if math.abs((body.lastFurBloodRegions[region] or 0) - regionBlood) > 0.05 then
                body.lastFurBloodRegions[region] = regionBlood
                ply:SetNWFloat("WoundSystemFurBlood_" .. region, regionBlood)
            end
        end
    end
end

function WoundSystem.Health.PlayerHasActiveMedicalSession(ply)
    return Sessions.Shrapnel[ply] ~= nil
        or Sessions.Dislocation[ply] ~= nil
        or Sessions.Syringe[ply] ~= nil
        or Sessions.Bandage[ply] ~= nil
        or Sessions.Aed[ply] ~= nil
end

function WoundSystem.Health.IsStableUnconsciousSlowTickEligible(ply, body)
    if not IsValid(ply) or not body then return false end

    if not body.unconscious or body.fallingRagdoll then return false end
    if not IsValid(body.unconsciousRagdoll) then return false end
    if WoundSystem.Health.PlayerHasActiveMedicalSession(ply) then return false end
    if body.bloodVomiting or body.vomiting then return false end
    if body.hasPulmonaryEmbolism then return false end

    if (body.totalBleedSpeed or 0) > 0.05 then return false end
    if (body.internalBleeding or 0) > 0.1 then return false end
    if (body.hemothorax or 0) > 3 then return false end
    if (body.fibrillationProgress or 0) > 0 then return false end
    if (body.bloodVolume or 100) < 70 then return false end
    if (body.bloodOxygen or 100) < 72 then return false end
    if (body.bloodPressure or 120) < 75 then return false end
    if (body.heartRate or 70) <= 15 then return false end
    if (body.temperature or 37) < 34 or (body.temperature or 37) > 39.5 then return false end
    if (body.brainHealth or 100) < 35 then return false end
    if (body.septicShock or 0) > 5 then return false end
    if (body.radiationSickness or 0) > 12 then return false end
    if (body.strokeAmount or 0) > 0 then return false end
    if (body.avgPain or 0) > 85 then return false end

    return true
end

function WoundSystem.Health.ShouldSkipStableUnconsciousTick(ply, body, dt)
    if not WoundSystem.Health.IsStableUnconsciousSlowTickEligible(ply, body) then
        body.nextStableUnconsciousTick = nil
        body.lastStableUnconsciousTick = nil
        return false, dt
    end

    local now = CurTime()
    local interval = 0.75

    if not body.lastStableUnconsciousTick then
        body.lastStableUnconsciousTick = now
        body.nextStableUnconsciousTick = now + interval
        return false, dt
    end

    if now < (body.nextStableUnconsciousTick or 0) then
        return true, dt
    end

    local elapsed = math.Clamp(now - body.lastStableUnconsciousTick, dt, 2)
    body.lastStableUnconsciousTick = now
    body.nextStableUnconsciousTick = now + interval

    return false, elapsed
end

local function CardioLiteTick(dt)
    if not WoundSystemHealthEnabled() then return end

    local baseDt = dt
    for ply, limbs in pairs(PlayerLimbs) do
        if not IsValid(ply) or not ply:Alive() then continue end

        dt = baseDt
        local body = GetBody(ply)
        body.energy = 100

        -- GOD MODE GUARD: Freeze and lock all vitals, then move to the next player
        if body.isGodMode then 
            body.pain = 0
            body.avgPain = 0
            body.averagePain = 0
            body.temperature = 37.0
            body.internalBleeding = 0
            body.bloodVolume = 200 -- Max based on your math.Clamp(body.bloodVolume, -100, 200)
            body.stamina = 100
            body.hunger = 100
            body.thirst = 100
            body.energy = 100
            body.weightOffset = 0
            body.bloodOxygen = 100
            body.brainHealth = 100
            body.consciousness = 100
            body.fibrillationProgress = 0
            body.heartRate = 70
            body.bloodPressure = 120
            body.respiratoryRate = 100
            body.hemothorax = 0
            body.cardioShock = 0
            body.shock = 0
            body.cardioDamageBuffer = 0
            body.brainDamageBuffer = 0
            body.bloodViscosity = 0
            body.radiationSickness = 0
            body.wetness = 0
            body.sicknessAmount = 0
            body.septicShock = 0
            body.opiateHappiness = 0
            body.antidepressantHappiness = 0
            body.antidepressantAmount = 0
            body.antidepressantCurrentAmount = 0
            body.sleepingPillAmount = 0
            body.sleepingPillWasSleeping = false
            body.opiateAmount = 0
            body.opiateReception = 0
            body.actualOpiateReception = 0
            body.opiateTolerance = 0
            body.dirtyness = 0
            body.traumaAmount = 0
            body.clawHealth = 100
            body.clawRegrowTime = 0
            body.caffeinated = 0
            body.badSleepAmount = 0
            body.venomCurrent = 0
            body.overdoseIndex = 0
            body.painShock = 0
            body.bloodVomitTime = 0
            body.bloodVomiting = false
            body.vomitTime = 0
            body.vomiting = false
            body.vomitPower = 0
            body.badLookAmount = 0
            body.specialCryingUntil = 0
            body.totalBleedSpeed = 0
            body.curAdrenaline = 0
            body.radiationExposureTimer = 0
            body.hasPulmonaryEmbolism = false
            body.strokeAmount = 0
            body.sleeping = false
            body.stimulantMultiplier = 0
            body.lastStandTime = 0
            body.focusedLevel = 0
            body.horrifiedLevel = 0
            body.overEncumberance = 0
            body.brainGrowSickness = 0
            body.temporarySlowdown = 0
            body.bloodPressureChangeFromMedicine = 0
            body.antibioticImmunityTime = 0
            body.timedBodyEffects = {}
            if WoundSystem.Health.CAS3BodyFeel and WoundSystem.Health.CAS3BodyFeel.ResetBodyFields then
                WoundSystem.Health.CAS3BodyFeel.ResetBodyFields(body)
            end

            -- If they were unconscious when god mode toggled on, wake them up cleanly
            if body.wasUnconscious then
                RestorePlayerFromUnconsciousRagdoll(ply, body, false)
                body.wasUnconscious = false
            end
            body.unconscious = false

            -- Network the clean vitals straight to the client HUD
            ply:SetNWFloat("BloodAmount", body.bloodVolume)
            ply:SetNWFloat("BrainHealth", body.brainHealth)
            ply:SetNWFloat("Consciousness", body.consciousness)
            ply:SetNWBool("WoundSystemUnconscious", body.unconscious)
            WoundSystem.Health.UpdateFacialExpressionState(ply, body, limbs)
            SendCardioUpdate(ply)

            continue -- Skip the rest of the simulation loop for this player
        end

        local skipStableUnconsciousTick, stableUnconsciousDt = WoundSystem.Health.ShouldSkipStableUnconsciousTick(ply, body, dt)
        if skipStableUnconsciousTick then continue end
        dt = stableUnconsciousDt

        -- Stamina Drain, Regeneration, & Movement Heat Generation 
        local isNoclip = ply:GetMoveType() == MOVETYPE_NOCLIP
        local speed = ply:GetVelocity():Length2D()
        local isSprinting = not isNoclip and ply:KeyDown(IN_SPEED) and speed > 100
        local cas3BodyFeel = WoundSystem.Health.CAS3BodyFeel
        local staminaRegenScale = cas3BodyFeel and cas3BodyFeel.GetStaminaRegenScale and cas3BodyFeel.GetStaminaRegenScale(body) or 1
        local cvarDrainScale = WoundSystem.Health.Config.CVars.StaminaDrainScale and WoundSystem.Health.Config.CVars.StaminaDrainScale:GetFloat() or 1.0
        local staminaDrainScale = (cas3BodyFeel and cas3BodyFeel.GetStaminaDrainScale and cas3BodyFeel.GetStaminaDrainScale(body) or 1) * cvarDrainScale

        if isNoclip then
            body.stamina = math.Approach(body.stamina, 100, 15 * dt)
        elseif isSprinting then
            body.stamina = math.max(0, body.stamina - (2 * dt * staminaDrainScale))
            body.temperature = body.temperature + (0.02 * dt) -- Sprinting exertion heat
        elseif speed > 10 then
            body.stamina = math.Approach(body.stamina, math.max(70, body.bloodOxygen), 2 * dt * staminaRegenScale)
            body.temperature = body.temperature + (0.005 * dt) -- Normal walking exertion heat
        else
            body.stamina = math.Approach(body.stamina, math.max(70, body.bloodOxygen), 8 * dt * staminaRegenScale)
        end

        if not WoundSystem.Health.FreezeHungerConVar:GetBool() then
            body.hunger = math.Clamp((body.hunger or 100) - (dt / 23), -50, 125)
        end
        if not WoundSystem.Health.FreezeThirstConVar:GetBool() then
            body.thirst = math.Clamp((body.thirst or 100) - (dt / 17), -50, 250)
        end
        WoundSystem.Health.ApplyFrozenNeeds(body)

        body.bloodViscosity = math.Approach(body.bloodViscosity or 0, 0, 0.05 * dt)
        body.bloodViscosity = math.Clamp(body.bloodViscosity, -100, 100)
        if body.thirst < 0 then
            body.bloodViscosity = math.Clamp(body.bloodViscosity + (0.25 * dt), -100, 100)
        end

        body.curAdrenaline = math.Approach(body.curAdrenaline or 0, body.adrenaline or 0, 5 * dt)
        body.hearingLoss = math.Clamp((body.hearingLoss or 0) - (0.05 * dt), 0, 100)
        body.sicknessAmount = math.Clamp((body.sicknessAmount or 0) - (0.06 * dt), 0, 100)
        body.opiateHappiness = math.Approach(body.opiateHappiness or 0, 0, 1.5 * dt)
        body.antidepressantHappiness = math.Approach(body.antidepressantHappiness or 0, 0, 0.05 * dt)
        body.dirtyness = math.Clamp((body.dirtyness or 0) + (dt / 1500), 0, 100)
        local actualOpiateReception = UpdateOpiateState(ply, body, dt, limbs)
        if cas3BodyFeel and cas3BodyFeel.TickBody then
            cas3BodyFeel.TickBody(ply, body, limbs, dt, actualOpiateReception)
        end
        TickTimedBodyEffects(ply, body, limbs, dt)
        body.temporarySlowdown = math.Approach(body.temporarySlowdown or 0, 0, dt * 0.1)
        body.bloodPressureChangeFromMedicine = math.Approach(body.bloodPressureChangeFromMedicine or 0, 0, dt)
        body.antibioticImmunityTime = math.max((body.antibioticImmunityTime or 0) - dt, 0)

        local waterLevelEnt = IsValid(body.unconsciousRagdoll) and body.unconsciousRagdoll or ply
        local waterLevel = waterLevelEnt:WaterLevel()
        if waterLevel > 0 then
            body.wetness = math.Clamp((body.wetness or 0) + (waterLevel * 4 * dt), 0, 100)
        end
        if (body.radiationExposureTimer or 0) > 0 and waterLevel >= 2 then
            body.radiationSickness = math.Clamp((body.radiationSickness or 0) + (2 * dt), 0, 100)
            body.radiationExposureTimer = body.radiationExposureTimer - dt
        elseif (body.radiationExposureTimer or 0) > 0 then
            body.radiationExposureTimer = body.radiationExposureTimer - dt
        end

        local totalBleed = 0
        local totalBleedSpeed = 0
        local maxPain = 0
        local totalPain = 0
        local totalInfection = 0

        body.bleedingSpeedMultiplier = body.bleedingSpeedMultiplier or WoundSystem.Health.Config.ComputeBleedingSpeedMultiplier(body)

        for _, state in pairs(limbs) do
            local bleedOpen = state.blockedBleeding and 0 or 1
            totalBleed = totalBleed + (state.bleed or 0)
            totalBleedSpeed = totalBleedSpeed + ((state.bleed or 0) * body.bleedingSpeedMultiplier * bleedOpen)

            if not state.dismembered then
                maxPain = math.max(maxPain, (state.pain or 0) - ((body.curAdrenaline or 0) * 0.5))
            end
            totalPain = totalPain + (state.pain or 0)
            totalInfection = totalInfection + (state.infection or 0)
        end

        if WoundSystem.Health.ApplyCAS3PainResilience then
            body.avgPain = WoundSystem.Health.ApplyCAS3PainResilience(body, maxPain)
        else
            body.avgPain = math.max(maxPain, 0)
        end
        body.averagePain = body.avgPain

        if body.avgPain > 0 and not body.unconscious and (body.consciousness or 100) > 0
            and WoundSystem.Skills and WoundSystem.Skills.AddSkillExp then
            WoundSystem.Skills.AddSkillExp(ply, "RES", dt * body.avgPain * 0.0125)
        end

        if body.avgPain > 50 and not body.unconscious and (body.consciousness or 100) > 0 then
            body.traumaAmount = math.Clamp((body.traumaAmount or 0) + (body.avgPain * dt * 0.0034), 0, 100)
        else
            body.traumaAmount = math.Clamp((body.traumaAmount or 0) - (dt / 35), 0, 100)
        end

        if body.avgPain > 75 then
            body.painShock = math.Clamp((body.painShock or 0) + (dt / 30), 0, 1)
        else
            body.painShock = math.Clamp((body.painShock or 0) - (dt / 30), 0, 1)
        end

        if (body.painShock or 0) > 0.66 then
            body.consciousness = 0
        end
        if body.avgPain > 99 then
            Fn.AddBodyShock(body, 100)
        end

        if totalInfection > 100 then
            body.septicShock = math.Clamp((body.septicShock or 0) + (dt * totalInfection * 0.00028), 0, 100)
        else
            body.septicShock = math.Clamp((body.septicShock or 0) - (dt * 0.07), 0, 100)
        end

        local clampedInternalBleedEarly = Fn.IntBleedingClamped(body.internalBleeding)
        totalBleedSpeed = totalBleedSpeed + (clampedInternalBleedEarly * 0.0057)
        totalBleedSpeed = totalBleedSpeed - WoundSystem.Health.Config.BloodRegenSpeed(body)
        body.totalBleedSpeed = math.max(0, totalBleedSpeed)

        body.bleedClottingSpeed = WoundSystem.Health.Config.ComputeBleedClottingSpeed(body)

        if WoundSystem.Health.Config and WoundSystem.Health.Config.TemperatureEnabled and WoundSystem.Health.Config.TemperatureEnabled() then
            local ambientTemp = 23.5
            local totalInsulation = 1 + ((body.weightOffset or 0) * 0.01)
            if body.usingSleepingBag then
                totalInsulation = totalInsulation + 0.5
            end
            totalInsulation = math.max(totalInsulation, 0.5)

            body.temperature = Lerp(math.Clamp((0.003 / totalInsulation) * dt, 0, 1), body.temperature, ambientTemp)

            local metabolicHeat = 1
            if actualOpiateReception > 0 then
                metabolicHeat = metabolicHeat - (actualOpiateReception * 0.005)
            end
            body.temperature = body.temperature + (0.04 * metabolicHeat * dt)

            if body.temperature > 37.2 then
                local sweatTarget = (body.temperature - 37.2) * 25
                if (body.wetness or 0) < sweatTarget then
                    body.wetness = math.min(100, (body.wetness or 0) + (2 * dt))
                end
                local excessTemp = body.temperature - 37.0
                body.temperature = body.temperature - (excessTemp * 0.03 * dt)
            end
            local wetDecay = ((body.wetness or 0) > 75) and 0.35 or 0.2
            body.wetness = math.max(0, (body.wetness or 0) - (wetDecay * dt))
            body.temperature = body.temperature - ((body.wetness or 0) * 0.0015 * dt)

            if body.temperature < 36.5 then
                body.temperature = body.temperature + (math.max((body.hunger or 100) * 0.01, 0.3) * 0.03 * metabolicHeat * dt)
            end

            if body.temperature < 32 then
                if not WoundSystem.Health.FreezeHungerConVar:GetBool() then
                    body.hunger = math.Clamp((body.hunger or 100) - (0.035 * dt), -50, 125)
                end
                body.temperature = body.temperature + (0.01 * dt)
            end

            if totalInfection > 10 and body.temperature < 40.5 then
                body.temperature = body.temperature + (0.02 * dt)
            end

            if body.temperature > 41 then body.bloodVolume = body.bloodVolume - (0.15 * dt) end
        else
            body.temperature = 37.0
        end

        HandleRadiationSicknessTick(ply, body, limbs, dt)
        WoundSystem.Health.ApplyFrozenNeeds(body)

        local tempDiff = body.temperature - 37
        local hungerImm = (body.hunger or 100) - 70
        local thirstImm = (body.thirst or 100) - 60
        local energyImm = (body.energy or 100) - 60
        local dirtyPenalty = math.max(0, (body.dirtyness or 0) - 50)
        local antibioticBonus = ((body.antibioticImmunityTime or 0) > 0) and 70 or 0
        body.immunity = math.Clamp(
            100
                + (hungerImm * 0.75)
                + (thirstImm * 0.3)
                + (energyImm * 0.2)
                + (tempDiff * 8)
                + ((body.bloodVolume or 100) - 100) * 0.2
                + antibioticBonus
                - dirtyPenalty
                - ((body.sicknessAmount or 0) * 0.8)
                - ((body.radiationSickness or 0) * 0.5),
            0, 200
        )
        body.immunityMult = WoundSystem.Health.Config.EvaluateImmunityInfectionSpeed(body.immunity)

        local clampedInternalBleed = 0
        if body.internalBleeding > 0 then
            clampedInternalBleed = math.Clamp(body.internalBleeding, 0, 25)

            body.bloodVomitTime = (body.bloodVomitTime or 0) + (body.internalBleeding * dt * 0.01)
            if body.bloodVomitTime > WoundSystem.Health.Constants.BloodVomitThreshold and not body.bloodVomiting then
                BeginBloodVomit(ply, body)
            end

            if body.internalBleeding > 5 then
                body.hemothorax = body.hemothorax + (clampedInternalBleed * 0.0088 * dt)
            else
                body.hemothorax = math.max(0, body.hemothorax - (0.036 * dt))
            end

            local thorax = limbs["thorax"]
            if thorax and thorax.pain < (body.hemothorax * 0.25) then
                thorax.pain = math.min(100, thorax.pain + (3.5 * dt))
                SendLimbUpdate(ply, "thorax", true)
            end

            body.internalBleeding = math.max(0, body.internalBleeding - (0.045 * dt))
        else
            body.hemothorax = math.max(0, body.hemothorax - (0.036 * dt))
        end

        body.bloodVolume = math.Approach(body.bloodVolume or 100, 100, WoundSystem.Health.Config.BloodRegenSpeed(body) * dt)

        local bloodLossThisTick = clampedInternalBleed * 0.0057 * dt
        if bloodLossThisTick > 0 then
            body.bloodVolume = math.max(-100, body.bloodVolume - bloodLossThisTick)
        end

        body.bloodVolume = math.Clamp(body.bloodVolume, -100, 200)

        if body.bloodPressure > 180 and math.random() < (0.02 * dt) then
            body.strokeAmount = math.max(body.strokeAmount or 0, 0.1)
        end
        if (body.strokeAmount or 0) > 0 then
            local strokesEnabled = WoundSystem.Health.Config.CVars.StrokesEnabled:GetBool()
            local strokeDir = strokesEnabled and 1 or -1
            body.strokeAmount = math.Clamp((body.strokeAmount or 0) + (0.1333 * strokeDir * dt), 0, 100)
            if strokesEnabled then
                body.bloodVolume = math.max(-100, body.bloodVolume - (0.1 * dt))
                body.brainHealth = math.Clamp((body.brainHealth or 100) - (0.025 * dt), 0, 100)
                if body.strokeAmount > 90 and body.fibrillationProgress <= 0 then
                    body.fibrillationProgress = 0.1
                end
            end
        end

        body.adrenaline = math.max(0, (body.adrenaline or 0) - (dt * 1.5))

        if body.thirst < 30 then
            local thoraxThirst = limbs["thorax"]
            if thoraxThirst and thoraxThirst.pain < 25 then
                thoraxThirst.pain = math.Approach(thoraxThirst.pain, 25, dt)
            end
        end
        if body.thirst > 175 then
            local headStateThirst = limbs["head"]
            if headStateThirst and headStateThirst.pain < 50 then
                headStateThirst.pain = math.Approach(headStateThirst.pain, 50, 2.5 * dt)
            end
            body.brainHealth = math.Clamp((body.brainHealth or 100) - (0.05 * dt), 0, 100)
        end

        if (body.bloodViscosity or 0) > 90 and math.random() < (0.0166 * dt) then
            body.hasPulmonaryEmbolism = true
            Fn.AddBodyShock(body, 25)
            body.adrenaline = math.Clamp((body.adrenaline or 0) + 35, 0, 100)
        end
        if (body.bloodViscosity or 0) < 50 and body.hasPulmonaryEmbolism then
            body.hasPulmonaryEmbolism = false
        end
        if body.hasPulmonaryEmbolism then
            local thoraxEmb = limbs["thorax"]
            if thoraxEmb then
                thoraxEmb.muscle = math.max(0, (thoraxEmb.muscle or 100) - (0.6 * dt))
                thoraxEmb.pain = math.Approach(thoraxEmb.pain or 0, 45, 2 * dt)
            end
            body.bloodOxygen = math.max(0, (body.bloodOxygen or 100) - (1.4 * dt))
            body.bloodPressure = math.max(0, (body.bloodPressure or 120) - (0.75 * dt))
            if (body.bloodOxygen or 100) < 65 and body.fibrillationProgress <= 0 then
                body.fibrillationProgress = 0.1
            end
        end

        local avgPainSys = body.avgPain
        body.thirstBloodPressure = WoundSystem.Health.Circulation.ThirstBloodPressure(body.thirst)

        local refPressure = WoundSystem.Health.Circulation.ReferencePressure(body, actualOpiateReception, tempDiff)
        body.heartRatePressureOffset = body.heartRatePressureOffset or 0
        if (body.bloodPressure or 120) < refPressure - 5 then
            body.heartRatePressureOffset = body.heartRatePressureOffset + dt * 1.5
        elseif (body.bloodPressure or 120) > refPressure + 5 then
            body.heartRatePressureOffset = body.heartRatePressureOffset - dt * 1.5
        end
        body.heartRatePressureOffset = math.Clamp(body.heartRatePressureOffset, -30, 80)

        local positiveViscosity = math.max(0, body.bloodViscosity or 0)
        local targetHeartRate = 70
            + avgPainSys
            + ((100 - (body.stamina or 100)) * 0.6)
            + ((body.curAdrenaline or 0) * 0.55)
            - (positiveViscosity * 0.3)
            + (tempDiff * 0.5)
            - (actualOpiateReception / 5)
            + body.heartRatePressureOffset
            + (body.fibrillationProgress or 0)
        if body.fibrillationProgress > 75 then
            targetHeartRate = targetHeartRate + (body.fibrillationProgress - 75) * 4
        end
        if body.fibrillationProgress > 95 then
            targetHeartRate = targetHeartRate + (body.fibrillationProgress - 95) * 30
        end

        if (body.fibrillationProgress or 0) >= 100 then
            body.heartRate = 0
        else
            body.heartRate = Lerp(math.Clamp(dt * 0.15, 0, 1), body.heartRate or 70, targetHeartRate)
        end

        -- Blood vessel size adjustment
        local bvs = body.bloodVesselSize or 1.0
        if body.bloodPressure > refPressure + 10 then
            bvs = bvs + dt * 0.0036
        elseif body.bloodPressure < refPressure - 10 then
            bvs = bvs - dt * 0.0036
        else
            bvs = math.Approach(bvs, 1.0, dt * 0.0036)
        end
        if body.stamina < 50 or (body.curAdrenaline or 0) > 30 then
            bvs = bvs - dt * 0.005
        end
        body.bloodVesselSize = math.Clamp(bvs, 0.85, 1.15)

        -- Blood pressure multipliers
        local heartRateOffset = body.heartRate - 70
        if heartRateOffset > 0 then
            heartRateOffset = heartRateOffset / 200
        else
            heartRateOffset = heartRateOffset / 70
        end

        local bloodVolPctForPressure = math.Clamp(0.5 + (body.bloodVolume / 200), 0, 1.5)
        local volumePressureMult = 1.0 + (bloodVolPctForPressure - 1.0) * 1.1

        local visBpMult = 1.0 + (body.bloodViscosity or 0) / 200
        local tempBpMult = 1.0 - tempDiff / 40
        local weightBpMult = 1.0 + (body.weightOffset or 0) / 180
        local fibBpMult = 1.0 - (body.fibrillationProgress / 260)
        local septicBpMult = 1.0 - (body.septicShock or 0) * 0.00525
        local thirstBpMult = body.thirstBloodPressure or 1.0
        local opiateBpMult = math.Clamp(1 - (actualOpiateReception / 400), 0.75, 1.25)

        local targetPressure = 120 * (1.0 + heartRateOffset) * volumePressureMult * fibBpMult * visBpMult * thirstBpMult * septicBpMult * opiateBpMult * tempBpMult * weightBpMult / body.bloodVesselSize

        if (body.bloodPressureChangeFromMedicine or 0) > 0 then
            targetPressure = targetPressure * 0.75
        end
        if (body.bloodPressureChangeFromMedicine or 0) < 0 then
            targetPressure = targetPressure * 1.25
        end

        if body.fibrillationProgress >= 100 or body.heartRate <= 5 then
            targetPressure = 0
        end

        body.bloodPressure = math.Clamp(Lerp(math.Clamp(dt * 0.25, 0, 1), body.bloodPressure or 120, targetPressure), 0, 250)
        
        -- Respiratory simulation
        local targetResp = 100
        if body.bloodPressure > 145 then targetResp = targetResp - (body.bloodPressure - 145) end
        if body.bloodPressure < 20 then targetResp = 0 end
        targetResp = targetResp - (body.fibrillationProgress * 0.35)
        targetResp = targetResp - (body.hemothorax * 0.5)
        targetResp = targetResp - actualOpiateReception
        targetResp = targetResp + (tempDiff * 3)
        targetResp = targetResp + ((body.curAdrenaline or 0) * 0.2)
        targetResp = targetResp + (avgPainSys * 0.25)
        if (body.strokeAmount or 0) > 50 then
            targetResp = targetResp - math.max(0, (body.strokeAmount - 50) * 2)
        end
        if body.hasPulmonaryEmbolism then
            targetResp = targetResp - 35
        end
        if body.temperature < 28 and (body.consciousness or 100) < 30 then
            targetResp = 0
        end
        
        local thoraxState = limbs["thorax"]
        local abdomenState = limbs["abdomen"]
        if (thoraxState and thoraxState.muscle <= 5) or (abdomenState and abdomenState.muscle <= 5) then
            targetResp = 0
        end

        local respSpeed = (body.respiratoryRate > 10) and 8 or 1
        body.respiratoryRate = math.Approach(body.respiratoryRate, math.Clamp(targetResp, 0, 100), respSpeed * dt)

        local bloodVolPct = 0.5 + (body.bloodVolume / 200)
        
        local isSubmerged = waterLevelEnt:WaterLevel() >= 3
        local isBreathing = (body.respiratoryRate > 10) and (not isSubmerged or body.hasScubaGear)
        local breathingMultiplier = isBreathing and 1 or 0

        body.bloodOxygen = body.bloodOxygen + ((body.respiratoryRate * 0.01 * breathingMultiplier) - 0.5) * dt
        -- Low stamina drains blood oxygen heavily (C# Ref: - (100-stamina)/100 * 0.35 * dt)
        body.bloodOxygen = body.bloodOxygen - (((100 - body.stamina) / 100) * 0.35 * dt)

        if bloodVolPct < 0.6 and body.bloodOxygen > (bloodVolPct * 100) then
            local cap = (bloodVolPct / 0.6) * 100
            body.bloodOxygen = math.Approach(body.bloodOxygen, cap, 0.75 * dt)
        end

        local o2ViscCap = Fn.ViscosityOxygenCap(body.bloodViscosity)
        if body.bloodOxygen > o2ViscCap then
            body.bloodOxygen = math.Approach(body.bloodOxygen, o2ViscCap, 0.75 * dt)
        end

        if body.hemothorax and body.hemothorax > 0 then
            local hemCap = 100 - body.hemothorax * 0.3
            if body.bloodOxygen > hemCap then
                body.bloodOxygen = math.Approach(body.bloodOxygen, hemCap, 0.8 * dt)
            end
        end

        body.bloodOxygen = math.Clamp(body.bloodOxygen, 0, 100)

        local brainDying = body.bloodPressure < 10 and (body.consciousness or 100) < 5
        if brainDying then
            body.brainHealth = (body.brainHealth or 100) - (dt * 1.5)
        elseif body.bloodOxygen < 80 then
            body.brainHealth = (body.brainHealth or 100) - (dt * (80 - body.bloodOxygen) / 600)
        end

        if body.temperature > 42 then
            body.brainHealth = (body.brainHealth or 100) - (dt * 0.5)
        end

        if (body.brainHealth or 100) > 0 then
            body.brainHealth = (body.brainHealth or 100) + (dt * 0.003)
        end
        body.brainHealth = math.Clamp(body.brainHealth or 100, 0, 100)

        local headState = limbs["head"]
        local headConsciousness = headState and ((headState.muscle or 0) * 2.1) or 100
        local pressureLow = RemapClamped(body.bloodPressure, 60, 110, 30, 100)
        local pressureHigh = RemapClamped(body.bloodPressure, 140, 200, 100, 30)
        local temperatureFactor = 100
        if body.temperature < 29 then
            temperatureFactor = RemapClamped(body.temperature, 24, 29, 0, 100)
        elseif body.temperature > 41 then
            temperatureFactor = RemapClamped(body.temperature, 45, 41, 0, 100)
        end
        local opiateConsciousness = 100 - math.max(0, actualOpiateReception) * 0.7
        local sicknessConsciousness = 150 - (body.sicknessAmount or 0)
        local sleepConsciousness = body.sleeping and 10 or 100
        local radiationConsciousness = 100 - ((body.radiationSickness or 0) * 0.7)
        local badSleepConsciousness = ((body.badSleepAmount or 0) > 0) and 70 or 100
        local pressureCollapseConsciousness = ((body.bloodPressure or 120) < 60) and 0 or 100

        local targetConsciousness = math.min(
            100,
            headConsciousness,
            body.bloodOxygen * 1.2,
            pressureLow,
            pressureHigh,
            body.brainHealth,
            150 - body.avgPain,
            opiateConsciousness,
            temperatureFactor,
            sicknessConsciousness,
            sleepConsciousness,
            radiationConsciousness,
            badSleepConsciousness,
            pressureCollapseConsciousness
        )
        targetConsciousness = math.Clamp(targetConsciousness, 0, 100)

        local consciousnessRate = ((body.consciousness or 100) > targetConsciousness) and 12 or 3
        body.consciousness = math.Approach(body.consciousness or 100, targetConsciousness, consciousnessRate * dt)
        body.consciousness = math.Clamp(body.consciousness, 0, 100)
        if WoundSystem.Health.CAS3BodyFeel and WoundSystem.Health.CAS3BodyFeel.ApplyConsciousnessEffects then
            WoundSystem.Health.CAS3BodyFeel.ApplyConsciousnessEffects(ply, body, dt)
        end
        body.unconscious = body.consciousness < 20

        local fibRise = WoundSystem.Health.Config.CvFloat(WoundSystem.Health.Config.CVars.FibrillationRise, 1)
        local fibDecay = WoundSystem.Health.Config.CvFloat(WoundSystem.Health.Config.CVars.FibrillationDecay, 0.75)

        local fibrillationRising = body.bloodOxygen < 60
            or body.bloodPressure < 88
            or body.heartRate > 200
            or (body.bloodViscosity or 0) > 80
            or body.temperature < 28.5

        if body.bloodOxygen < 50 or body.bloodPressure < 78 or body.heartRate > 200 or (body.bloodViscosity or 0) > 95 or body.temperature < 28 then
            if body.fibrillationProgress <= 0 then
                body.fibrillationProgress = 0.1
            end
        end

        if body.fibrillationProgress > 0 then
            if fibrillationRising then
                local rise = fibRise * dt
                if body.heartRate > 280 then
                    rise = rise + (3 * fibRise * dt)
                end
                body.fibrillationProgress = math.Clamp(body.fibrillationProgress + rise, 0, 100)
            else
                body.fibrillationProgress = math.max(0, body.fibrillationProgress - (fibDecay * dt))
            end
        end

        if body.fibrillationProgress >= 100 then body.heartRate = 0 end

        body.shock = math.Clamp((body.shock or 0) - (dt * (((body.consciousness or 100) > 20) and 10 or 0)), 0, 100)
        body.cardioShock = math.Clamp(math.max(body.shock or 0, (avgPainSys * 2) + ((body.fibrillationProgress or 0) * 0.5)), 0, 100)
        body.cardioDamageBuffer = 0
        body.brainDamageBuffer = math.max(0, (body.brainDamageBuffer or 0) - (dt * 0.1))

        local wasUnconscious = body.wasUnconscious == true
        body.unconscious = body.consciousness < 20

        if (body.shock or 0) > 10 and not body.unconscious and not body.fallingRagdoll and ply:IsOnGround() and CurTime() > (body.suppressShockRagdollUntil or 0) then
            body.fallingRagdoll = true
            body.fallingRagdollWakeTime = CurTime() + math.Clamp(((body.shock or 20) - 10) / 10, 1.0, 5.0)
            body.fallingRagdollReason = "shock"
            TryCreateUnconsciousRagdoll(ply, body)
        end

        if body.unconscious and (not wasUnconscious or not IsValid(body.unconsciousRagdoll)) then
            if not wasUnconscious then
                body.fallingRagdoll = nil
                body.fallingRagdollWakeTime = nil
                body.fallingRagdollReason = nil
            end

            if CurTime() > (body.nextUnconsciousRagdollRetry or 0) then
                if TryCreateUnconsciousRagdoll(ply, body) then
                    body.nextUnconsciousRagdollRetry = nil
                else
                    body.nextUnconsciousRagdollRetry = CurTime() + 0.5
                end
            end
        elseif (not body.unconscious) and wasUnconscious then
            body.fallingRagdoll = true
            body.fallingRagdollWakeTime = CurTime()
            body.fallingRagdollReason = "recovery"
            body.nextUnconsciousRagdollRetry = nil
        end

        body.wasUnconscious = body.unconscious

        if body.fallingRagdoll and not body.unconscious and (body.brainHealth or 100) > 0 then
            local now = CurTime()
            local isMoving = body.ragdollMoving == true

            if now >= (body.nextRagdollMotionCheck or 0) then
                isMoving = false
                local ragdoll = body.unconsciousRagdoll
                if not IsValid(ragdoll) and WoundSystemBridgeActive() then ragdoll = ply.FakeRagdoll end
                if IsValid(ragdoll) then
                    local physCount = ragdoll.WoundSystemPhysObjectCount
                    if not physCount then
                        physCount = ragdoll:GetPhysicsObjectCount()
                        ragdoll.WoundSystemPhysObjectCount = physCount
                    end

                    for i = 0, physCount - 1, 2 do
                        local phys = ragdoll:GetPhysicsObjectNum(i)
                        if IsValid(phys) and phys:GetVelocity():LengthSqr() > 2500 then
                            isMoving = true
                            break
                        end
                    end
                end

                body.ragdollMoving = isMoving
                body.nextRagdollMotionCheck = now + 0.18 + ((ply:EntIndex() % 5) * 0.015)
            end

            local wakeTime = body.fallingRagdollWakeTime or 0
            if isMoving and body.fallingRagdollReason == "fall" then
                body.fallingRagdollWakeTime = now + 3.0
            elseif isMoving and body.fallingRagdollReason ~= "recovery" and now > wakeTime then
                body.fallingRagdollWakeTime = now + 0.15
            end

            if now > (body.fallingRagdollWakeTime or 0) then
                body.ragdollMoving = nil
                body.nextRagdollMotionCheck = nil
                RestorePlayerFromUnconsciousRagdoll(ply, body, false)
            end
        end

        if body.brainHealth <= 0 and not body.brainDead and ply:Alive() then
            body.brainDead = true
            body.unconscious = true
            body.wasUnconscious = true
            if IsValid(body.unconsciousRagdoll) then
                PreserveUnconsciousRagdollForDeath(ply, body)
            else
                RestorePlayerFromUnconsciousRagdoll(ply, body, false)
            end
            WoundSystem.Health.KillWithAttribution(ply, body, "brain_death")
        end

        ply:SetNWFloat("BloodAmount", body.bloodVolume)
        ply:SetNWFloat("BrainHealth", body.brainHealth)
        ply:SetNWFloat("Consciousness", body.consciousness)
        ply:SetNWBool("WoundSystemUnconscious", body.unconscious)
        WoundSystem.Health.UpdateFacialExpressionState(ply, body, limbs)
        SendCardioUpdate(ply)
    end
end

-- NEW HOOK: Drains stamina and generates heat when players jump
function WoundSystem.Health.LimbForce.LimbMissing(ply, limbName)
    local limbs = PlayerLimbs[ply]
    local state = limbs and limbs[limbName]
    return state and state.dismembered == true
end

function WoundSystem.Health.LimbForce.LimbStrength(ply, limbName)
    local limbs = PlayerLimbs[ply]
    local state = limbs and limbs[limbName]
    if not state or state.dismembered then return 0 end
    return math.Clamp(state.muscleStrength or ((state.muscle or 0) / 100), 0, 1)
end

function WoundSystem.Health.LimbForce.AverageGroupStrength(ply, names)
    local total = 0
    local count = 0

    for _, limbName in ipairs(names or {}) do
        total = total + WoundSystem.Health.LimbForce.LimbStrength(ply, limbName)
        count = count + 1
    end

    if count <= 0 then return 0 end
    return math.Clamp(total / count, 0, 1)
end

function WoundSystem.Health.LimbForce.LegSideStrength(ply, side)
    return WoundSystem.Health.LimbForce.AverageGroupStrength(ply, WoundSystem.Health.LimbForce.LegLimbs[side])
end

function WoundSystem.Health.LimbForce.ArmSideStrength(ply, side)
    return WoundSystem.Health.LimbForce.AverageGroupStrength(ply, WoundSystem.Health.LimbForce.ArmLimbs[side])
end

function WoundSystem.Health.LimbForce.CoreStrength(ply)
    return WoundSystem.Health.LimbForce.AverageGroupStrength(ply, WoundSystem.Health.LimbForce.CoreLimbs)
end

function WoundSystem.Health.LimbForce.GetLegMovementMultiplier(ply)
    local rightMissing = WoundSystem.Health.LimbForce.LimbMissing(ply, "thigh_R") or WoundSystem.Health.LimbForce.LimbMissing(ply, "crus_R")
    local leftMissing = WoundSystem.Health.LimbForce.LimbMissing(ply, "thigh_L") or WoundSystem.Health.LimbForce.LimbMissing(ply, "crus_L")

    if rightMissing and leftMissing then
        return 0.18
    end
    if rightMissing or leftMissing then
        return 0.38
    end

    if not WoundSystem.Health.LimbForce.EnabledCVar:GetBool() then return 1 end

    local right = WoundSystem.Health.LimbForce.LegSideStrength(ply, "R")
    local left = WoundSystem.Health.LimbForce.LegSideStrength(ply, "L")
    local strongest = math.max(right, left)
    local average = (right + left) * 0.5
    local core = math.max(WoundSystem.Health.LimbForce.CoreStrength(ply), 0.25)
    local scale = WoundSystem.Health.Config.CvFloat(WoundSystem.Health.LimbForce.MovementScaleCVar, 1)

    if right <= 0 and left <= 0 then return 0.15 end
    if right <= 0 or left <= 0 then
        local oneLeg = math.Clamp(strongest * 0.45, 0.2, 0.4)
        return math.Clamp(Lerp(scale, 1, oneLeg * core), 0.15, 0.4)
    end

    return math.Clamp(Lerp(scale, 1, average * core), 0.2, 1)
end

function WoundSystem.Health.LimbForce.GetWeaponHandlingForce(ply)
    if not WoundSystem.Health.LimbForce.EnabledCVar:GetBool() then return 1 end

    local right = WoundSystem.Health.LimbForce.ArmSideStrength(ply, "R")
    local left = WoundSystem.Health.LimbForce.ArmSideStrength(ply, "L")
    local strongest = math.max(right, left)
    local support = math.min(right, left)

    return math.Clamp(strongest * 0.75 + support * 0.25, 0, 1)
end

function WoundSystem.Health.LimbForce.HandsTooWeakForWeapons(ply)
    return WoundSystem.Health.LimbForce.GetWeaponHandlingForce(ply) <= WoundSystem.Health.Config.CvFloat(WoundSystem.Health.LimbForce.WeaponThresholdCVar, 0.16)
end

function WoundSystem.Health.LimbForce.DropWeaponForUselessHands(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local body = BodyState[ply]
    if body and body.fallingRagdoll and not body.unconscious then return end
    if WoundSystem.Health.LimbForce.GetWeaponHandlingForce(ply) > 0.035 then return end

    local wep = ply:GetActiveWeapon()
    if IsValid(wep) then
        DropRecoverableWeapon(ply, wep)
    end
end

hook.Add("StartTouch", "WoundSystem_RecoverDroppedWeaponOnTouch", function(ent1, ent2)
    if not WoundSystemHealthEnabled() then return end

    local ply, wep

    if IsValid(ent1) and ent1:IsPlayer() and IsValid(ent2) and ent2:IsWeapon() then
        ply, wep = ent1, ent2
    elseif IsValid(ent2) and ent2:IsPlayer() and IsValid(ent1) and ent1:IsWeapon() then
        ply, wep = ent2, ent1
    else
        return
    end

    TryRecoverDroppedWeapon(ply, wep)
end)

hook.Add("KeyPress", "WoundSystem_StaminaJump", function(ply, key)
    if not WoundSystemHealthEnabled() then return end

    if key == IN_JUMP and ply:IsOnGround() and ply:GetMoveType() ~= MOVETYPE_NOCLIP then
        local legMult = WoundSystem.Health.LimbForce.GetLegMovementMultiplier(ply)
        if legMult <= 0.25 then return end

        local body = BodyState[ply]
        if body then
            body.stamina = math.max(0, body.stamina - (5 / math.max(legMult, 0.35)))
            body.temperature = body.temperature + 0.045 -- Heat from jumping
        end
    end
end)

-- NEW HOOK: Emulates "legSpeedMult", reducing run/walk speed if stamina is heavily drained.
hook.Add("SetupMove", "WoundSystem_StaminaSlowdown", function(ply, mvd, cmd)
    if not WoundSystemHealthEnabled() then return end

    local body = BodyState[ply]
    if not body then return end

    if (body.unconscious or body.fallingRagdoll) and IsValid(body.unconsciousRagdoll) then
        local bodyAnchor = GetUnconsciousRagdollBodyAnchor(body.unconsciousRagdoll) or body.ragdollWakePos
        if bodyAnchor then
            body.ragdollWakePos = bodyAnchor
        end

        mvd:SetVelocity(Vector(0, 0, 0))
        cmd:SetForwardMove(0)
        cmd:SetSideMove(0)
        cmd:SetUpMove(0)
        return
    end

    local limbForce = WoundSystem.Health.LimbForce
    local limbForceEnabled = limbForce.EnabledCVar:GetBool()

    if limbForceEnabled then
        limbForce.RecomputeAll(PlayerLimbs[ply], body)
    end

    local movementMult = 1
    local moveForceMult = 1
    local ballisticMoveMult = nil
    local now = CurTime()

    if (body.ballisticStaggerUntil or 0) > now then
        local tier = math.Clamp(tonumber(body.ballisticStaggerTier) or 1, 1, 3)
        local staggerMoveMult = tier == 1 and 0.42 or tier == 2 and 0.28 or 0.22

        if now < (body.ballisticControlDelayUntil or 0) then
            cmd:SetForwardMove(0)
            cmd:SetSideMove(0)
            cmd:SetUpMove(0)
        elseif tier >= 2 and now < (body.ballisticHeldMoveUntil or 0) then
            if (body.ballisticHeldForward or 0) ~= 0 then
                cmd:SetForwardMove(body.ballisticHeldForward)
            end
            if (body.ballisticHeldSide or 0) ~= 0 then
                cmd:SetSideMove(body.ballisticHeldSide)
            end
        end

        cmd:RemoveKey(IN_SPEED)
        ballisticMoveMult = staggerMoveMult
    else
        body.ballisticStaggerUntil = nil
        body.ballisticControlDelayUntil = nil
        body.ballisticStaggerTier = nil
        body.ballisticHeldForward = nil
        body.ballisticHeldSide = nil
        body.ballisticHeldMoveUntil = nil
        body.ballisticWasDucking = nil
    end

    local cas3BodyFeel = WoundSystem.Health.CAS3BodyFeel
    if cas3BodyFeel and cas3BodyFeel.GetMovementMultipliers then
        movementMult, moveForceMult = cas3BodyFeel.GetMovementMultipliers(ply, body, PlayerLimbs[ply], limbForceEnabled)
    else
        movementMult = limbForceEnabled and limbForce.GetLegMovementMultiplier(ply) or 1
    end

    if ballisticMoveMult then
        movementMult = math.min(movementMult, ballisticMoveMult)
        moveForceMult = math.min(moveForceMult, ballisticMoveMult)
    end

    local speedMult = math.Clamp(movementMult, 0.02, 1.25)
    local cmdMult = math.Clamp(movementMult * moveForceMult, 0.02, 1.25)

    if WoundSystemBridgeActive() then
        -- Z-City's inertia movement multiplies the same value in shared code (org.wsmovemult),
        -- applying it here as well would slow the player down twice.
        speedMult, cmdMult = 1, 1
    end

    if speedMult ~= 1 or cmdMult ~= 1 then
        mvd:SetMaxClientSpeed(mvd:GetMaxClientSpeed() * speedMult)
        mvd:SetMaxSpeed(mvd:GetMaxSpeed() * speedMult)
        if mvd.SetForwardSpeed and mvd.GetForwardSpeed then
            mvd:SetForwardSpeed(mvd:GetForwardSpeed() * speedMult)
        end
        if mvd.SetSideSpeed and mvd.GetSideSpeed then
            mvd:SetSideSpeed(mvd:GetSideSpeed() * speedMult)
        end
        cmd:SetForwardMove(cmd:GetForwardMove() * cmdMult)
        cmd:SetSideMove(cmd:GetSideMove() * cmdMult)
    end

    if movementMult <= 0.25 then
        cmd:RemoveKey(IN_JUMP)
        cmd:RemoveKey(IN_SPEED)
    elseif movementMult < 0.75 and cmd:KeyDown(IN_JUMP) then
        if math.Rand(0, 1) > movementMult then
            cmd:RemoveKey(IN_JUMP)
        end
        cmd:SetUpMove(cmd:GetUpMove() * movementMult)
    end

    local collapseThreshold = WoundSystem.Health.Config.CvFloat(limbForce.RagdollThresholdCVar, 0.18)
    if movementMult <= collapseThreshold and not body.fallingRagdoll and not body.unconscious and ply:IsOnGround() then
        local moving = math.abs(cmd:GetForwardMove()) > 10 or math.abs(cmd:GetSideMove()) > 10 or ply:GetVelocity():Length2D() > 90
        if moving and CurTime() > (body.nextLimbForceCollapseTime or 0) then
            body.nextLimbForceCollapseTime = CurTime() + 1.25
            body.fallingRagdoll = true
            body.fallingRagdollWakeTime = CurTime() + 1.8
            body.fallingRagdollReason = "limb_force"
            TryCreateUnconsciousRagdoll(ply, body)
            return
        end
    end

end)

local function RebuildWoundTimers()
    local limbDelay = WoundSystem.Health.Config.LimbTickInterval()
    local cardioDelay = WoundSystem.Health.Config.CardioTickInterval()

    if timer.Exists(WoundSystem.Health.Constants.LimbTimerName) then
        timer.Adjust(WoundSystem.Health.Constants.LimbTimerName, limbDelay, 0, function() LimbPhysiologyTick(limbDelay) end)
    else
        timer.Create(WoundSystem.Health.Constants.LimbTimerName, limbDelay, 0, function() LimbPhysiologyTick(limbDelay) end)
    end

    timer.Remove(WoundSystem.Health.Constants.CardioTimerName)
    timer.Remove(WoundSystem.Health.Constants.CardioTimerName .. "_Start")
    timer.Create(WoundSystem.Health.Constants.CardioTimerName .. "_Start", math.min(0.075, cardioDelay * 0.45), 1, function()
        timer.Create(WoundSystem.Health.Constants.CardioTimerName, cardioDelay, 0, function() CardioLiteTick(cardioDelay) end)
    end)
end

RebuildWoundTimers()

local function HasActiveMedicalSessions()
    return next(Sessions.Shrapnel) ~= nil
        or next(Sessions.Dislocation) ~= nil
        or next(Sessions.Syringe) ~= nil
        or next(Sessions.Bandage) ~= nil
        or next(Sessions.Aed) ~= nil
end

function WoundSystem.Health.CancelActiveMedicalSessions(ply, reason)
    if not IsValid(ply) then return end

    reason = reason or "interrupted"
    CloseShrapnelSession(ply, reason)
    CloseDislocationSession(ply, reason)
    CloseSyringeSession(ply, reason)
    CloseBandageSession(ply, reason)
    CloseAedSession(ply, reason)
end

local function ShrapnelSessionSafetyTick()
    if not WoundSystemHealthEnabled() then
        for ply in pairs(Sessions.Shrapnel) do CloseShrapnelSession(ply, "disabled") end
        for ply in pairs(Sessions.Dislocation) do CloseDislocationSession(ply, "disabled") end
        for ply in pairs(Sessions.Syringe) do CloseSyringeSession(ply, "disabled") end
        for ply in pairs(Sessions.Bandage) do CloseBandageSession(ply, "disabled") end
        for ply in pairs(Sessions.Aed) do CloseAedSession(ply, "disabled") end
        return
    end

    if not HasActiveMedicalSessions() then return end

    local now = CurTime()
    for ply, session in pairs(Sessions.Shrapnel) do
        if not IsValid(ply) then
            Sessions.Shrapnel[ply] = nil
            continue
        end

        if not ply:Alive() then
            CloseShrapnelSession(ply, "dead")
            continue
        end

        local state = GetLimbState(ply, session.limbId)
        if not state then
            CloseShrapnelSession(ply, "invalid_limb")
            continue
        end

        if now - (session.lastInputAt or now) > MinigameTimeoutLimit(ply, WoundSystem.Health.Constants.ShrapnelInputTimeout) then
            CloseShrapnelSession(ply, "timeout")
            continue
        end
    end

    for ply, session in pairs(Sessions.Dislocation) do
        if not IsValid(ply) then
            Sessions.Dislocation[ply] = nil
            continue
        end

        if not ply:Alive() then
            CloseDislocationSession(ply, "dead")
            continue
        end

        local state = GetLimbState(ply, session.limbId)
        if not state or not state.dislocated then
            CloseDislocationSession(ply, "invalid_limb")
            continue
        end

        if now - (session.lastInputAt or now) > MinigameTimeoutLimit(ply, WoundSystem.Health.Constants.DislocationInputTimeout) then
            CloseDislocationSession(ply, "timeout")
            continue
        end
    end

    for ply, session in pairs(Sessions.Syringe) do
        if not IsValid(ply) then
            Sessions.Syringe[ply] = nil
            continue
        end

        if not ply:Alive() then
            CloseSyringeSession(ply, "dead")
            continue
        end

        local state = GetLimbState(ply, session.limbId)
        if not state then
            CloseSyringeSession(ply, "invalid_limb")
            continue
        end

        if now - (session.lastInputAt or now) > MinigameTimeoutLimit(ply, WoundSystem.Health.Constants.SyringeInputTimeout) then
            CloseSyringeSession(ply, "timeout")
            continue
        end
    end

    for ply, session in pairs(Sessions.Bandage) do
        if not IsValid(ply) then
            Sessions.Bandage[ply] = nil
            continue
        end

        if not ply:Alive() then
            CloseBandageSession(ply, "dead")
            continue
        end

        local state = GetLimbState(ply, session.limbId)
        if not state then
            CloseBandageSession(ply, "invalid_limb")
            continue
        end

        if now - (session.lastInputAt or now) > MinigameTimeoutLimit(ply, WoundSystem.Health.Constants.BandageInputTimeout) then
            CloseBandageSession(ply, "timeout")
            continue
        end
    end

    for ply, session in pairs(Sessions.Aed) do
        if not IsValid(ply) then
            Sessions.Aed[ply] = nil
            continue
        end

        if not ply:Alive() then
            CloseAedSession(ply, "dead")
            continue
        end

        local state = GetLimbState(ply, session.limbId)
        if not state then
            CloseAedSession(ply, "invalid_limb")
            continue
        end

        if now - (session.lastInputAt or now) > MinigameTimeoutLimit(ply, WoundSystem.Health.Constants.AedSessionTimeout) then
            CloseAedSession(ply, "timeout")
            continue
        end
    end
end

if timer.Exists(WoundSystem.Health.Constants.ShrapnelTimerName) then
    timer.Adjust(WoundSystem.Health.Constants.ShrapnelTimerName, 0.1, 0, ShrapnelSessionSafetyTick)
else
    timer.Create(WoundSystem.Health.Constants.ShrapnelTimerName, 0.1, 0, ShrapnelSessionSafetyTick)
end

function WoundSystemCloseAllMedicalSessions(ply, reason)
    CloseShrapnelSession(ply, reason)
    CloseDislocationSession(ply, reason)
    CloseBandageSession(ply, reason)
    CloseSyringeSession(ply, reason)
    CloseAedSession(ply, reason)
end

function WoundSystemApplyEnabledState()
    local enabled = WoundSystemHealthEnabled()

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) then continue end

        WoundSystem.Health.BumpLifecycleSeq(ply)
        WoundSystemCloseAllMedicalSessions(ply, enabled and "enabled" or "disabled")
        ply:SetNWFloat("WoundSystemBrainReverseUntil", 0)
        ply:SetNWFloat("WoundSystemBrainShakeUntil", 0)

        if enabled then
            WoundSystemForceClearUnconsciousRagdollState(ply, BodyState[ply])
            WoundSystem.Health.Config.ApplyVanillaBloodMode(ply)
            if ply:Alive() and not BodyState[ply] then
                InitPlayer(ply)
                ResetPlayerInventory(ply)
                ResetClientLimbs(ply)
                SendCardioUpdate(ply)
                SendDismembermentVisualReset(ply)
                SendDismembermentVisuals(ply)
            end
        else
            WoundSystemForceClearUnconsciousRagdollState(ply, BodyState[ply])
            ResetClientLimbs(ply)
            SendDismembermentVisualReset(ply)
            ply:SetNWBool("WoundSystemUnconscious", false)
            ply:SetNWEntity("WoundSystemUnconsciousRagdoll", NULL)
            ply:SetNWEntity("WoundSystemDeathRagdoll", NULL)
            WoundSystem.Health.Config.ApplyVanillaBloodMode(ply)
            PlayerLimbs[ply] = nil
            BodyState[ply] = nil
            PlayerInventory[ply] = nil
            LastSentLimbState[ply] = nil
            ply.WoundSystemGodMode = nil
        end
    end
end

if cvars and cvars.AddChangeCallback then
    cvars.AddChangeCallback("woundsys_enabled", function()
        timer.Simple(0, WoundSystemApplyEnabledState)
    end, "WoundSystem_EnabledState")

    cvars.AddChangeCallback("woundsys_limb_tick_interval", function() RebuildWoundTimers() end, "WoundSystem_LimbTickRebuild")
    cvars.AddChangeCallback("woundsys_cardio_tick_interval", function() RebuildWoundTimers() end, "WoundSystem_CardioTickRebuild")
    cvars.AddChangeCallback("woundsys_replace_vanilla_blood", function()
        for _, ply in ipairs(player.GetAll()) do
            WoundSystem.Health.Config.ApplyVanillaBloodMode(ply)

            local body = BodyState and BodyState[ply]
            if body and IsValid(body.unconsciousRagdoll) then
                WoundSystem.Health.Config.ApplyVanillaBloodMode(body.unconsciousRagdoll)
            end
        end
    end, "WoundSystem_ReplaceVanillaBlood")
end

hook.Add("PlayerDisconnected", "WoundSystem_Cleanup", function(ply)
    timer.Remove("WoundSystem_DeathRagdollCleanup_" .. ply:EntIndex())
    if BodyState[ply] then
        RestorePlayerFromUnconsciousRagdoll(ply, BodyState[ply], false)
    end
    Sessions.Shrapnel[ply] = nil
    Sessions.Dislocation[ply] = nil
    Sessions.Bandage[ply] = nil
    Sessions.Syringe[ply] = nil
    Sessions.Aed[ply] = nil
    PlayerLimbs[ply] = nil
    BodyState[ply] = nil
    PlayerInventory[ply] = nil
    LastSentLimbState[ply] = nil
    ply.WoundSystemGodMode = nil
end)

hook.Add("PlayerDeath", "WoundSystem_ShrapnelEndOnDeath", function(victim)
    if not WoundSystemHealthEnabled() then return end

    CloseShrapnelSession(victim, "dead")
    CloseDislocationSession(victim, "dead")
    CloseBandageSession(victim, "dead")
    CloseSyringeSession(victim, "dead")
    CloseAedSession(victim, "dead")
    if BodyState[victim] then
        local body = BodyState[victim]
        WoundSystem.Health.SetFacialExpressionNW(victim, "dead", 1, WoundSystem.Health.GetFacialExpressionEyes(body, PlayerLimbs[victim]))
        if not PreserveUnconsciousRagdollForDeath(victim, body) then
            RestorePlayerFromUnconsciousRagdoll(victim, body, false)
        else
            WoundSystem.Health.ScheduleDuplicateDeathRagdollCleanup(victim, body)
        end
    end
end)

hook.Add("DoPlayerDeath", "WoundSystem_PreserveUnconsciousRagdollPreDeath", function(victim)
    if not WoundSystemHealthEnabled() then return end

    local body = BodyState[victim]
    if body and IsValid(body.unconsciousRagdoll) and (body.unconscious or body.fallingRagdoll or body.diedWhileUnconscious) then
        body.diedWhileUnconscious = true
        body.deathRagdollOverride = body.unconsciousRagdoll
        PreserveUnconsciousRagdollForDeath(victim, body)
        WoundSystem.Health.ScheduleDuplicateDeathRagdollCleanup(victim, body)
    end
end)

hook.Add("PhysgunPickup", "WoundSystem_WakeSettledUnconsciousRagdoll", function(_, ent)
    if not WoundSystemHealthEnabled() then return end
    if IsValid(ent) and ent.WoundSystemUnconsciousRagdoll then
        WoundSystem.Health.WakeUnconsciousRagdollPhysics(ent)
    end
end)

hook.Add("GravGunOnPickedUp", "WoundSystem_WakeSettledUnconsciousRagdoll", function(_, ent)
    if not WoundSystemHealthEnabled() then return end
    if IsValid(ent) and ent.WoundSystemUnconsciousRagdoll then
        WoundSystem.Health.WakeUnconsciousRagdollPhysics(ent)
    end
end)

local function WoundSystemCommandAddKey(cmd, key)
    if cmd.AddKey then
        cmd:AddKey(key)
    elseif cmd.GetButtons and cmd.SetButtons then
        cmd:SetButtons(bit.bor(cmd:GetButtons(), key))
    end
end

local function WoundSystemCommandRemoveKey(cmd, key)
    if cmd.RemoveKey then
        cmd:RemoveKey(key)
    elseif cmd.GetButtons and cmd.SetButtons then
        cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(key)))
    end
end

hook.Add("StartCommand", "WoundSystem_BlockUnconsciousInput", function(ply, cmd)
    if not WoundSystemHealthEnabled() then return end

    local body = BodyState[ply]
    if not IsValid(ply) or not ply:Alive() then return end

    if body and (body.unconscious or body.fallingRagdoll) then
        if cmd.ClearButtons then
            cmd:ClearButtons()
        else
            cmd:RemoveKey(IN_ATTACK)
            cmd:RemoveKey(IN_ATTACK2)
            cmd:RemoveKey(IN_JUMP)
            cmd:RemoveKey(IN_USE)
            cmd:RemoveKey(IN_RELOAD)
            cmd:RemoveKey(IN_DUCK)
            cmd:RemoveKey(IN_SPEED)
        end

        if cmd.ClearMovement then
            cmd:ClearMovement()
        else
            cmd:SetForwardMove(0)
            cmd:SetSideMove(0)
            cmd:SetUpMove(0)
        end

        if cmd.SetImpulse then
            cmd:SetImpulse(0)
        end

        return
    end

    local limbForce = WoundSystem.Health.LimbForce
    if limbForce.EnabledCVar:GetBool() then
        if limbForce.HandsTooWeakForWeapons(ply) then
            cmd:RemoveKey(IN_ATTACK)
            cmd:RemoveKey(IN_ATTACK2)
            cmd:RemoveKey(IN_RELOAD)
        else
            local handlingForce = limbForce.GetWeaponHandlingForce(ply)
            if handlingForce < 0.6 and (cmd:KeyDown(IN_ATTACK) or cmd:KeyDown(IN_ATTACK2)) then
                local fumbleChance = math.Clamp((0.6 - handlingForce) / 0.6, 0, 0.75)
                if math.Rand(0, 1) < fumbleChance then
                    cmd:RemoveKey(IN_ATTACK)
                    cmd:RemoveKey(IN_ATTACK2)
                end
            end
        end
    end

    if body and not body.ballisticWasDucking then
        local now = CurTime()
        if now < (body.ballisticForceDuckUntil or 0) then
            WoundSystemCommandAddKey(cmd, IN_DUCK)
        elseif now < (body.ballisticForceUnduckUntil or 0) then
            WoundSystemCommandRemoveKey(cmd, IN_DUCK)
        elseif body.ballisticForceDuckUntil or body.ballisticForceUnduckUntil then
            body.ballisticForceDuckUntil = nil
            body.ballisticForceUnduckUntil = nil
            body.ballisticWasDucking = nil
        end
    end

end)

timer.Create("WoundSystem_MissingHandWeaponDrop", 0.35, 0, function()
    if not WoundSystemHealthEnabled() then return end

    local limbForce = WoundSystem.Health and WoundSystem.Health.LimbForce
    if not limbForce or not limbForce.EnabledCVar or not limbForce.EnabledCVar:GetBool() then return end

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            limbForce.DropWeaponForUselessHands(ply)
        end
    end
end)

net.Receive("WoundSystem_RequestRagdoll", function(_, ply)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) then return end

    local body = BodyState[ply]
    local ragdoll = body and body.unconsciousRagdoll
    SendUnconsciousRagdoll(ply, IsValid(ragdoll) and ragdoll or nil)
end)

net.Receive("WoundSystem_RemoveLimbStatus", function(_, ply)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local limbId = net.ReadString()
    local statusId = WoundSystem.NormalizeItemId(net.ReadString())
    if statusId ~= "SPLINTED" and statusId ~= "TOURNIQUET" then return end

    local state = GetLimbState(ply, limbId)
    if not state or not WoundSystem.Statuses then return end

    if statusId == "SPLINTED" and state.hevBrace then return end

    local returnedItemId = statusId == "SPLINTED" and (state.splintItemId or "SPLINT") or "TOURNIQUET"
    local returnedDurability = 0
    local sourceSlot = nil

    if statusId == "SPLINTED" then
        returnedDurability = WoundSystem.Statuses.GetValue(state, "SPLINTED") or state.splintDurability or 100
        sourceSlot = state.splintSourceSlot
    elseif statusId == "TOURNIQUET" then
        local maxTourniquet = WoundSystem.Items and WoundSystem.Items.GetMax and WoundSystem.Items.GetMax("TOURNIQUET") or 100
        returnedDurability = state.tourniquetDurability or maxTourniquet
        sourceSlot = state.tourniquetSourceSlot
    end

    WoundSystem.Statuses.Clear(state, statusId)
    if statusId == "SPLINTED" then
        state.splinted = false
        state.splintDurability = nil
        state.splintSourceSlot = nil
        state.splintItemId = nil
    elseif statusId == "TOURNIQUET" then
        local lower = {
            ["thigh_R"] = {"thigh_R", "crus_R", "foot_R"},
            ["crus_R"] = {"crus_R", "foot_R"},
            ["foot_R"] = {"foot_R"},
            ["thigh_L"] = {"thigh_L", "crus_L", "foot_L"},
            ["crus_L"] = {"crus_L", "foot_L"},
            ["foot_L"] = {"foot_L"},
            ["arm_R"] = {"arm_R", "forearm_R", "hand_R"},
            ["forearm_R"] = {"forearm_R", "hand_R"},
            ["hand_R"] = {"hand_R"},
            ["arm_L"] = {"arm_L", "forearm_L", "hand_L"},
            ["forearm_L"] = {"forearm_L", "hand_L"},
            ["hand_L"] = {"hand_L"}
        }

        local limbs = PlayerLimbs[ply] or {}
        for _, affectedId in ipairs(lower[limbId] or {limbId}) do
            local affected = limbs[affectedId]
            if affected then
                affected.tourniqueted = false
                affected.tourniquetPain = 0
                affected.tourniquetDurability = nil
                affected.tourniquetSourceSlot = nil
                if not affected.isBandaged then
                    affected.blockedBleeding = false
                end
                SendLimbUpdate(ply, affectedId, true)
            end
        end
    end

    WoundSystem.Health.ReturnAttachedMedicalItem(ply, returnedItemId, returnedDurability, sourceSlot)
    SendLimbUpdate(ply, limbId, true)
end)


WoundSystem = WoundSystem or {}

function WoundSystem.GetPlayerPhysiology(ply)
    if not WoundSystemHealthEnabled() then return 0, 0, 100 end
    if not IsValid(ply) then return 0, 0, 100 end

    local body = BodyState and BodyState[ply]
    local painValue = (body and body.avgPain) or 0
    local bloodVol = (body and body.bloodVolume) or 100
    local totalBleedSpeed = (body and body.totalBleedSpeed) or 0

    return painValue, totalBleedSpeed, bloodVol
end

WoundSystem.Health.GetLimbState = GetLimbState
WoundSystem.Health.GetBody = GetBody
WoundSystem.Health.InitPlayer = InitPlayer
WoundSystem.Health.SendLimbUpdate = SendLimbUpdate
WoundSystem.Health.UseMedicalItem = TryUseInventoryMedicalItem
WoundSystem.Health.RegisterServerMedicalItem = WoundSystem.RegisterServerMedicalItem
WoundSystem.Health.SyncInventoryToClient = SyncInventoryToClient
WoundSystem.Health.GetInventory = GetInventory
WoundSystem.Health.TryCreateUnconsciousRagdoll = TryCreateUnconsciousRagdoll
WoundSystem.Health.RestorePlayerFromUnconsciousRagdoll = RestorePlayerFromUnconsciousRagdoll
WoundSystem.Health.Fn = Fn
WoundSystem.Health.Const = Const
WoundSystem.Health.RagdollBoneNameToLimb = RagdollBoneNameToLimb
WoundSystem.Health.SendCardioUpdate = function(ply, ...) if SendCardioUpdate then return SendCardioUpdate(ply, ...) end end

-- Brand new body and limbs, like after a respawn (used by the Z-City "Reset organism" tool). Inventory is kept.
function WoundSystem.Health.ResetPlayer(ply)
    if not WoundSystemHealthEnabled() or not IsValid(ply) or not ply:IsPlayer() then return false end

    CloseShrapnelSession(ply, "respawn")
    CloseDislocationSession(ply, "respawn")
    CloseBandageSession(ply, "respawn")
    CloseSyringeSession(ply, "respawn")
    CloseAedSession(ply, "respawn")

    InitPlayer(ply)

    ResetClientLimbs(ply)
    SendCardioUpdate(ply, true)
    SendDismembermentVisualReset(ply)
    SendDismembermentVisuals(ply)
    timer.Simple(1, function()
        if IsValid(ply) then SendAllDismembermentVisuals(ply) end
    end)

    return true
end

-----------------------------------------------------------
-- Z-City integration API: apply a medical item (used by Z-City SWEPs) directly to a player's limb,
-- without the inventory / minigame UI.
--
--   amount  = durability units (0..item.max) spent by this application for "bandage" and "syringe"
--             items. Because a full item is worth 100 durability, `amount / 100` of the whole
--             profile effect is applied (exactly what the minigames do). For one-shot items
--             (use.apply) it is ignored: the item is applied once with a full slot, unless
--             opts.partial is set (then the slot holds exactly `amount` durability).
--   returns ok, usedDurability
-----------------------------------------------------------
function WoundSystem.Health.ApplyItemToBody(target, itemId, limbId, amount, opts)
    if not WoundSystemHealthEnabled() then return false end
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() then return false end

    itemId = NormalizeToolId(itemId)
    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    if not item then return false end

    if not PlayerLimbs[target] then InitPlayer(target) end
    if not GetLimbState(target, limbId) then return false end

    local use = item.use or {}
    if WoundSystem.Items.LimbAllowed and not WoundSystem.Items.LimbAllowed(use, limbId) then return false end

    local minigame = use.minigame
    if minigame == "aed" or minigame == "dislocation" or minigame == "shrapnel" then
        return false -- these need the interactive WoundSystem minigame
    end

    amount = math.max(tonumber(amount) or 0, 0)

    if minigame == "bandage" or minigame == "syringe" then
        if amount <= 0 then return false end

        local slot = WoundSystem.Items.CreateSlot(itemId, amount)
        local ctx = BuildMedicalItemContext(target, item, nil, slot, limbId)
        if type(use.canUse) == "function" and use.canUse(ctx) == false then return false end

        local ok
        if minigame == "bandage" then
            local profile = Fn.GetBandageProfile(itemId)
            if not profile then return false end
            ctx.wrapFraction = amount / math.max(profile.durabilityPerWrap or 1, 0.001)
            ctx.profile = profile
            ok = ApplyBandageProfile(ctx, profile) ~= false
            if ok and type(profile.applyWrap) == "function" then
                ok = profile.applyWrap(ctx) ~= false
            end
        else
            local profile = GetSyringeProfile(itemId)
            if not profile then return false end
            ctx.syringeFraction = amount / math.max(item.max or 100, 1)
            ctx.durabilityCost = amount
            ctx.profile = profile
            ok = ApplySyringeProfile(ctx, profile) ~= false
        end

        if not ok then return false end
        SendLimbUpdate(target, limbId, true)
        if SendCardioUpdate then SendCardioUpdate(target) end
        return true, amount
    end

    -- opts.partial: the item is applied with exactly `amount` durability in its slot (continuous use, e.g. a blood bag
    -- running for a few ticks); otherwise it is applied once with a full slot.
    local partial = type(opts) == "table" and opts.partial == true
    if partial and amount <= 0 then return false end
    local slotDurability = partial and amount or math.max(amount, item.max or 100)

    local slot = WoundSystem.Items.CreateSlot(itemId, slotDurability)
    local ok = UseRegisteredMedicalItem(target, itemId, limbId, nil, slot)
    if not ok then return false end

    SendLimbUpdate(target, limbId, true)
    if SendCardioUpdate then SendCardioUpdate(target) end
    return true, partial and amount or (tonumber(use.consumeDurability) or (item.max or 100))
end

-----------------------------------------------------------
-- Z-City integration API: run the real WoundSystem bandage / syringe minigame for something that is not in the
-- WoundSystem inventory (a Z-City SWEP).
--
--   spec.kind     "bandage" | "syringe"
--   spec.itemId   WoundSystem item that defines the minigame (look, speed, durability per wrap / second)
--   spec.limbId   limb shown in the minigame
--   spec.amount   durability (0..item.max) the player can work with
--   spec.onClose  function(ply, session, reason): session.deferredUsed / session.deferredWrap / session.startAmount
--                 describe what the player did. NOTHING was applied to anybody - the caller decides (pass / fail).
-- The item sits in a temporary slot (index 6) while the minigame is open. Returns true when the minigame was opened.
-----------------------------------------------------------
function WoundSystem.Health.StartExternalMinigame(ply, spec)
    if not WoundSystemHealthEnabled() or not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false end
    if type(spec) ~= "table" then return false end

    local kind = spec.kind
    local itemId = NormalizeToolId(spec.itemId)
    local limbId = tostring(spec.limbId or "")
    if kind ~= "bandage" and kind ~= "syringe" then return false end

    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    if not item or not item.use or item.use.minigame ~= kind then return false end

    local profile
    if kind == "bandage" then profile = Fn.GetBandageProfile(itemId) else profile = GetSyringeProfile(itemId) end
    if not profile then return false end

    if not PlayerLimbs[ply] then InitPlayer(ply) end
    if not GetLimbState(ply, limbId) then return false end

    -- one minigame at a time
    if Sessions.Bandage[ply] and Sessions.Bandage[ply].external then return false end
    if Sessions.Syringe[ply] and Sessions.Syringe[ply].external then return false end
    CloseBandageSession(ply, "replaced")
    CloseSyringeSession(ply, "replaced")

    local maxDur = WoundSystem.Items.GetMax and WoundSystem.Items.GetMax(itemId) or item.max or 100
    local amount = math.Clamp(tonumber(spec.amount) or maxDur, 0.5, maxDur)

    local inv = GetInventory(ply)
    inv[6] = WoundSystem.Items.CreateSlot(itemId, amount)

    local session = {
        limbId = limbId,
        slotIdx = 6,
        itemId = itemId,
        lastInputAt = CurTime(),
        external = true,
        deferred = true,
        deferredUsed = 0,
        deferredWrap = 0,
        startAmount = amount,
        onClose = spec.onClose,
        onProgress = spec.onProgress,
    }

    SyncInventoryToClient(ply) -- the client minigame reads the item from its inventory mirror

    if kind == "bandage" then
        session.id = Sessions.NextBandageId
        session.mode = profile.mode or "gauze"
        Sessions.NextBandageId = Sessions.NextBandageId + 1
        if Sessions.NextBandageId > 16000000 then Sessions.NextBandageId = 1 end

        Sessions.Bandage[ply] = session
        SendBandageOpen(ply, session)
    else
        session.id = Sessions.NextSyringeId
        Sessions.NextSyringeId = Sessions.NextSyringeId + 1
        if Sessions.NextSyringeId > 16000000 then Sessions.NextSyringeId = 1 end

        Sessions.Syringe[ply] = session
        SendSyringeOpen(ply, session)
    end

    return true
end

function WoundSystem.Health.StopExternalMinigame(ply, reason)
    local b, s = Sessions.Bandage[ply], Sessions.Syringe[ply]
    if b and b.external then CloseBandageSession(ply, reason or "stopped") end
    if s and s.external then CloseSyringeSession(ply, reason or "stopped") end
end

function WoundSystem.Health.HasExternalMinigame(ply)
    local b, s = Sessions.Bandage[ply], Sessions.Syringe[ply]
    return (b and b.external) or (s and s.external) or false
end

-- The player is busy with the minigame: no walking, jumping, shooting or weapon switching.
-- After it closes, attack stays blocked until the mouse button is released (otherwise the SWEP would start it again).
hook.Add("StartCommand", "WoundSystem_ExternalMinigameControls", function(ply, cmd)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    if WoundSystem.Health.HasExternalMinigame(ply) then
        cmd:ClearMovement()
        cmd:RemoveKey(bit.bor(IN_ATTACK, IN_ATTACK2, IN_JUMP, IN_DUCK, IN_USE, IN_RELOAD, IN_SPEED, IN_WALK, IN_ZOOM))
        cmd:SetImpulse(0)
        cmd:SetWeaponSelect(0)
        return
    end

    if ply.WoundSystemExtMinigameAttackLock then
        if cmd:KeyDown(IN_ATTACK) then
            cmd:RemoveKey(IN_ATTACK)
        else
            ply.WoundSystemExtMinigameAttackLock = nil
        end
    end
end)

if util and util.AddNetworkString then
    util.AddNetworkString("WoundSystem_BloodVomit")
    util.AddNetworkString("WoundSystem_VomitWarning")
    util.AddNetworkString("WoundSystem_SetServerConVar")
end

net.Receive("WoundSystem_SetServerConVar", function(_, ply)
    if IsValid(ply) and not ply:IsAdmin() then return end

    local name = net.ReadString()
    local value = net.ReadString()
    if not WoundSystem.Health.Config.CanSetServerConVar(name) then return end

    local cvar = GetConVar(name)
    if not cvar then return end

    RunConsoleCommand(name, value)
end)
WoundSystem.Health.GetLimbs = function(ply)
    return PlayerLimbs[ply]
end

function WoundSystem.Health.SetLimbDislocated(ply, limbId, dislocated, timerValue, forceSync)
    local state = GetLimbState(ply, limbId)
    if not state then return false end

    if dislocated then
        state.dislocated = true
        state.dislocationTimer = math.Clamp(tonumber(timerValue) or 100, 0, 100)
        hook.Run("WoundSystem_OnDislocate", ply, limbId, state)
    else
        state.dislocated = false
        state.dislocationTimer = 0
    end

    if forceSync ~= false then
        SendLimbUpdate(ply, limbId, true)
    end

    return true
end

function WoundSystem.Health.SetLimbStatus(ply, limbId, statusId, value, forceSync)
    local state = GetLimbState(ply, limbId)
    if not state or not WoundSystem.Statuses then return false end

    local ok = WoundSystem.Statuses.Set(state, statusId, value)
    if ok and forceSync ~= false then
        SendLimbUpdate(ply, limbId, true)
    end

    return ok
end

function WoundSystem.Health.ClearLimbStatus(ply, limbId, statusId, forceSync)
    local state = GetLimbState(ply, limbId)
    if not state or not WoundSystem.Statuses then return false end

    local ok = WoundSystem.Statuses.Clear(state, statusId)
    if ok and forceSync ~= false then
        SendLimbUpdate(ply, limbId, true)
    end

    return ok
end

function WoundSystem.Health.GetMuscleHealth(ply, limbId)
    local state = GetLimbState(ply, limbId)
    return state and state.muscle or nil
end

function WoundSystem.Health.GetAllMuscleHealth(ply)
    local limbs = PlayerLimbs[ply]
    if not limbs then return {} end
    if WoundSystem.LimbMuscle and WoundSystem.LimbMuscle.GetAllMuscleHealth then
        return WoundSystem.LimbMuscle.GetAllMuscleHealth(limbs)
    end
    local out = {}
    for limbId, state in pairs(limbs) do
        out[limbId] = state.muscle or 0
    end
    return out
end

-- ============================================================
-- LIMB LOSS: helper to count how many sides still have a leg/arm
-- ============================================================
local function CountLivingLegs(ply)
    local LM = WoundSystem.Health.LimbForce.LimbMissing
    local rightGone = LM(ply, "thigh_R") or LM(ply, "crus_R")
    local leftGone  = LM(ply, "thigh_L") or LM(ply, "crus_L")
    if rightGone and leftGone then return 0 end
    if rightGone or leftGone  then return 1 end
    return 2
end

local function CountLivingArms(ply)
    local LM = WoundSystem.Health.LimbForce.LimbMissing
    local rightGone = LM(ply, "arm_R") or LM(ply, "forearm_R")
    local leftGone  = LM(ply, "arm_L") or LM(ply, "forearm_L")
    if rightGone and leftGone then return 0 end
    if rightGone or leftGone  then return 1 end
    return 2
end

-- ============================================================
-- LIMB LOSS: movement enforcement (0-leg forced crouch/no jump, 1-leg no run)
-- ============================================================
hook.Add("SetupMove", "WoundSystem_LimbLossMovement", function(ply, mvd, cmd)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end
    if ply:GetMoveType() == MOVETYPE_NOCLIP then return end

    local legs = CountLivingLegs(ply)

    if legs == 0 then
        -- No legs: permanent crouch, very slow, no jump
        cmd:AddKey(IN_DUCK)
        cmd:RemoveKey(IN_JUMP)
        cmd:RemoveKey(IN_SPEED)
        -- Speed is already severely throttled via GetLegMovementMultiplier (returns 0.18)
    elseif legs == 1 then
        -- One leg: no running
        cmd:RemoveKey(IN_SPEED)
        -- Speed capped at 0.38 via GetLegMovementMultiplier
    end
end)

-- ============================================================
-- LIMB LOSS: block vehicle entry with 0 legs or 0 arms
-- ============================================================
hook.Add("CanPlayerEnterVehicle", "WoundSystem_LimbLossVehicle", function(ply, vehicle, role)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    if CountLivingLegs(ply) == 0 then
        return false
    end
    if CountLivingArms(ply) == 0 then
        return false
    end
end)

-- ============================================================
-- LIMB LOSS: block weapon pickup with 0 arms
-- ============================================================
hook.Add("PlayerCanPickupWeapon", "WoundSystem_LimbLossWeaponPickup", function(ply, wep)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    if CountLivingArms(ply) == 0 then
        return false
    end
end)

-- ============================================================
-- LIMB LOSS: block prop pickup (physgun / gravgun / pickup) with 0 arms
-- ============================================================
hook.Add("PhysgunPickup", "WoundSystem_LimbLossPhysgun", function(ply, ent)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    if CountLivingArms(ply) == 0 then
        return false
    end
end)

hook.Add("GravGunPickupAllowed", "WoundSystem_LimbLossGravGun", function(ply, ent)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    if CountLivingArms(ply) == 0 then
        return false
    end
end)

hook.Add("AllowPlayerPickup", "WoundSystem_LimbLossAllowPickup", function(ply, ent)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    if CountLivingArms(ply) == 0 then
        return false
    end
end)

-- ============================================================
-- LIMB LOSS: drop weapon when losing both arms mid-game
-- ============================================================
timer.Create("WoundSystem_LimbLossDropWeapon", 0.5, 0, function()
    if not WoundSystemHealthEnabled() then return end

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end
        if CountLivingArms(ply) == 0 then
            local wep = ply:GetActiveWeapon()
            if IsValid(wep) then
                DropRecoverableWeapon(ply, wep)
            end
        end
    end
end)

-- ============================================================
-- UNCONSCIOUS TIMESCALE: auto-speedup when all players are unconscious
-- ============================================================
local UnconsciousTimescale_WasActive = false

timer.Create("WoundSystem_UnconsciousTimescaleCheck", 0.5, 0, function()
    if not WoundSystemHealthEnabled() then
        if UnconsciousTimescale_WasActive then
            game.SetTimeScale(1.0)
            UnconsciousTimescale_WasActive = false
        end
        return
    end

    local cvEnabled = WoundSystem.Health.Config.CVars.UnconsciousTimescaleEnabled
    if not cvEnabled or not cvEnabled:GetBool() then
        if UnconsciousTimescale_WasActive then
            game.SetTimeScale(1.0)
            UnconsciousTimescale_WasActive = false
        end
        return
    end

    local cvScale = WoundSystem.Health.Config.CVars.UnconsciousTimescale
    local targetScale = cvScale and math.Clamp(cvScale:GetFloat(), 1.0, 10.0) or 3.0

    local players = player.GetAll()
    if #players == 0 then
        if UnconsciousTimescale_WasActive then
            game.SetTimeScale(1.0)
            UnconsciousTimescale_WasActive = false
        end
        return
    end

    local allUnconscious = true
    for _, ply in ipairs(players) do
        if not IsValid(ply) then continue end
        -- A dead player doesn't count as conscious; a conscious alive player blocks speedup
        if ply:Alive() then
            local body = BodyState[ply]
            if body and not body.unconscious then
                allUnconscious = false
                break
            end
        end
    end

    if allUnconscious then
        if not UnconsciousTimescale_WasActive then
            game.SetTimeScale(targetScale)
            UnconsciousTimescale_WasActive = true
        end
    else
        if UnconsciousTimescale_WasActive then
            game.SetTimeScale(1.0)
            UnconsciousTimescale_WasActive = false
        end
    end
end)

-- Reset timescale when map ends to be safe
hook.Add("ShutDown", "WoundSystem_ResetTimescaleOnShutdown", function()
    game.SetTimeScale(1.0)
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            SavePlayerPersistData(ply)
        end
    end
end)


-- ============================================================
-- ADMIN DEBUG: handle WoundSystem_AdminDebugAction net messages
-- ============================================================
net.Receive("WoundSystem_AdminDebugAction", function(len, ply)
    if not IsValid(ply) then return end
    if not ply:IsAdmin() then
        ply:PrintMessage(HUD_PRINTTALK, "[C:U] Admin only.")
        return
    end

    local action = net.ReadString()
    local param1 = net.ReadString()  -- limb name, or general param
    local param2 = net.ReadFloat()   -- numeric value

    if action == "damage_limb" then
        -- param1 = limbName, param2 = damage amount
        local limbs = PlayerLimbs[ply]
        if limbs then
            local state = limbs[param1]
            if state then
                state.skin    = math.max(0, (state.skin or 100) - param2)
                state.muscle  = math.max(0, (state.muscle or 100) - param2)
                state.bleed   = math.min(200, (state.bleed or 0) + param2 * 0.5)
                state.pain    = math.min(100, (state.pain or 0) + param2 * 0.3)
                SendLimbUpdate(ply, param1, true)
            end
        end

    elseif action == "heal_limb" then
        -- param1 = limbName
        local limbs = PlayerLimbs[ply]
        if limbs then
            local state = limbs[param1]
            if state then
                state.skin           = 100
                state.muscle         = 100
                state.muscleStrength = 1
                state.pain           = 0
                state.bleed          = 0
                state.infection      = 0
                state.infectionSpeed = 0
                state.shrapnel       = 0
                state.broken         = false
                state.dislocated     = false
                state.isBandaged     = false
                state.blockedBleeding = false
                state.hasInjection   = false
                SendLimbUpdate(ply, param1, true)
            end
        end

    elseif action == "add_shrapnel" then
        -- param1 = limbName, param2 = amount (default 1)
        local limbs = PlayerLimbs[ply]
        if limbs and limbs[param1] then
            limbs[param1].shrapnel = math.Clamp((limbs[param1].shrapnel or 0) + math.max(1, param2), 0, 20)
            SendLimbUpdate(ply, param1, true)
        end

    elseif action == "remove_shrapnel" then
        -- param1 = limbName
        local limbs = PlayerLimbs[ply]
        if limbs and limbs[param1] then
            limbs[param1].shrapnel = 0
            SendLimbUpdate(ply, param1, true)
        end

    elseif action == "set_fracture" then
        -- param1 = limbName, param2 = 1 (add) or 0 (remove)
        local limbs = PlayerLimbs[ply]
        if limbs and limbs[param1] then
            limbs[param1].broken = param2 ~= 0
            SendLimbUpdate(ply, param1, true)
        end

    elseif action == "set_dislocation" then
        -- param1 = limbName, param2 = 1 (add) or 0 (remove)
        local limbs = PlayerLimbs[ply]
        if limbs and limbs[param1] then
            limbs[param1].dislocated = param2 ~= 0
            SendLimbUpdate(ply, param1, true)
        end

    elseif action == "set_dismember" then
        -- param1 = limbName, param2 = 1 (dismember) or 0 (restore)
        local limbs = PlayerLimbs[ply]
        if limbs and limbs[param1] then
            limbs[param1].dismembered = param2 ~= 0
            if param2 == 0 then
                limbs[param1].skin   = 100
                limbs[param1].muscle = 100
            end
            SendLimbUpdate(ply, param1, true)
        end

    elseif action == "add_blood" then
        -- param2 = blood volume to add (positive)
        local body = BodyState[ply]
        if body then
            body.bloodVolume = math.Clamp((body.bloodVolume or 100) + param2, -100, 200)
        end

    elseif action == "remove_blood" then
        -- param2 = blood volume to remove (positive)
        local body = BodyState[ply]
        if body then
            body.bloodVolume = math.Clamp((body.bloodVolume or 100) - param2, -100, 200)
        end

    elseif action == "set_blood" then
        -- param2 = exact blood volume value
        local body = BodyState[ply]
        if body then
            body.bloodVolume = math.Clamp(param2, -100, 200)
        end

    elseif action == "set_temperature" then
        -- param2 = body temperature in Celsius (e.g. 37.0)
        local body = BodyState[ply]
        if body then
            body.temperature = math.Clamp(param2, 20.0, 45.0)
        end

    elseif action == "set_stamina" then
        -- param2 = stamina value 0..100
        local body = BodyState[ply]
        if body then
            body.stamina = math.Clamp(param2, 0, 100)
        end

    elseif action == "set_pain" then
        -- param2 = pain value 0..100 (sets avgPain on body; limbs stay)
        local body = BodyState[ply]
        if body then
            body.pain    = math.Clamp(param2, 0, 100)
            body.avgPain = math.Clamp(param2, 0, 100)
        end

    elseif action == "set_consciousness" then
        -- param2 = consciousness value 0..100
        local body = BodyState[ply]
        if body then
            body.consciousness = math.Clamp(param2, 0, 100)
            if body.consciousness > 20 and body.unconscious then
                RestorePlayerFromUnconsciousRagdoll(ply, body, false)
            end
        end

    elseif action == "set_oxygen" then
        -- param2 = blood oxygen 0..100
        local body = BodyState[ply]
        if body then
            body.bloodOxygen = math.Clamp(param2, 0, 100)
        end

    elseif action == "set_heartrate" then
        -- param2 = heart rate BPM
        local body = BodyState[ply]
        if body then
            body.heartRate = math.Clamp(param2, 0, 300)
        end

    elseif action == "add_limb_bleed" then
        -- param1 = limbName, param2 = bleed rate to add
        local limbs = PlayerLimbs[ply]
        if limbs and limbs[param1] then
            limbs[param1].bleed = math.Clamp((limbs[param1].bleed or 0) + param2, 0, 200)
            SendLimbUpdate(ply, param1, true)
        end

    elseif action == "stop_limb_bleed" then
        -- param1 = limbName (or "all")
        local limbs = PlayerLimbs[ply]
        if limbs then
            if param1 == "all" then
                for limbId, state in pairs(limbs) do
                    state.bleed = 0
                    SendLimbUpdate(ply, limbId, true)
                end
            elseif limbs[param1] then
                limbs[param1].bleed = 0
                SendLimbUpdate(ply, param1, true)
            end
        end

    elseif action == "full_heal" then
        -- Full reset of body and all limbs
        local body = BodyState[ply]
        if body then
            body.pain            = 0
            body.avgPain         = 0
            body.bloodVolume     = 100
            body.temperature     = 37.0
            body.internalBleeding = 0
            body.consciousness   = 100
            body.brainHealth     = 100
            body.heartRate       = 70
            body.bloodPressure   = 120
            body.bloodOxygen     = 98
            body.stamina         = 100
            body.shock           = 0
            body.cardioShock     = 0
            body.adrenaline      = 0
            body.hemothorax      = 0
            body.fibrillationProgress = 0
			body.happiness 		 = 0

            if body.unconscious or IsValid(body.unconsciousRagdoll) then
                RestorePlayerFromUnconsciousRagdoll(ply, body, false)
            end
        end

        local limbs = PlayerLimbs[ply]
        if limbs then
            for limbId, state in pairs(limbs) do
                state.skin           = 100
                state.muscle         = 100
                state.muscleStrength = 1
                state.pain           = 0
                state.bleed          = 0
                state.infection      = 0
                state.infectionSpeed = 0
                state.shrapnel       = 0
                state.broken         = false
                state.dislocated     = false
                state.dismembered    = false
                state.isBandaged     = false
                state.blockedBleeding = false
                state.hasInjection   = false
                state.furBloodAmount = 0
                SendLimbUpdate(ply, limbId, true)
            end
        end

        ply:SetHealth(ply:GetMaxHealth())
        ply:PrintMessage(HUD_PRINTTALK, "[C:U Admin Debug] Full heal applied.")
    end
end)

hook.Add("PlayerSwitchWeapon", "WoundSystem_BlockUnconsciousTools", function(ply, oldWeapon, newWeapon)
    local body = BodyState[ply]
    if not body then return end

    if body.unconscious or not ply:Alive() then
        return true -- bblck weapon switch
    end
end)


hook.Add("CanTool", "WoundSystem_BlockUnconsciousTools", function(ply, tr, toolmode)
    local body = BodyState[ply]
    if not body then return end

    if body.unconscious or not ply:Alive() then
        return false
    end
end)

-- fix the symptom, not the problem >:3