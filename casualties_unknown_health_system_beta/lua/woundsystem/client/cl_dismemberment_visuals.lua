if WoundSystem and WoundSystem.DismembermentVisuals and WoundSystem.DismembermentVisuals._Loaded then
    hook.Remove("Think", "WoundSystem_DismembermentVisualsThink")
end

WoundSystem = WoundSystem or {}
WoundSystem.DismembermentVisuals = WoundSystem.DismembermentVisuals or {}
WoundSystem.DismembermentVisuals._Loaded = true

local Visuals = WoundSystem.DismembermentVisuals
Visuals.States = Visuals.States or {}
Visuals.BodygroupDefaults = Visuals.BodygroupDefaults or {}
Visuals.AppliedSignatures = Visuals.AppliedSignatures or {}

local function WoundSystemClientEnabled()
    local client = WoundSystem and WoundSystem.Client
    if client and client.IsEnabled then
        return client.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

local LimbOrder = {
    "foot_R", "foot_L",
    "crus_R", "crus_L",
    "thigh_R", "thigh_L",
    "arm_R", "arm_L",
    "forearm_R", "forearm_L",
    "hand_R", "hand_L",
    "head"
}

local LimbToBones = {
    head      = {"ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Neck1", "Bip01 Head", "Bip01 Neck"},
    arm_L     = {"ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_Hand", "Bip01 L Arm", "Bip01 L Arm1", "Bip01 L Arm2", "Bip01 L Hand"},
    forearm_L = {"ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_Hand", "Bip01 L Arm1", "Bip01 L Arm2", "Bip01 L Hand"},
    hand_L    = {"ValveBiped.Bip01_L_Hand", "Bip01 L Hand"},
    arm_R     = {"ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Hand", "Bip01 R Arm", "Bip01 R Arm1", "Bip01 R Arm2", "Bip01 R Hand"},
    forearm_R = {"ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Hand", "Bip01 R Arm1", "Bip01 R Arm2", "Bip01 R Hand"},
    hand_R    = {"ValveBiped.Bip01_R_Hand", "Bip01 R Hand"},
    thigh_L   = {"ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_L_Foot", "Bip01 L Leg", "Bip01 L Leg1", "Bip01 L Foot"},
    crus_L    = {"ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_L_Foot", "Bip01 L Leg1", "Bip01 L Foot"},
    foot_L    = {"ValveBiped.Bip01_L_Foot", "Bip01 L Foot"},
    thigh_R   = {"ValveBiped.Bip01_R_Thigh", "ValveBiped.Bip01_R_Calf", "ValveBiped.Bip01_R_Foot", "Bip01 R Leg", "Bip01 R Leg1", "Bip01 R Foot"},
    crus_R    = {"ValveBiped.Bip01_R_Calf", "ValveBiped.Bip01_R_Foot", "Bip01 R Leg1", "Bip01 R Foot"},
    foot_R    = {"ValveBiped.Bip01_R_Foot", "Bip01 R Foot"}
}

local LimbBoneNamePatterns = {
    head = {"head", "neck", "eye", "eyeball", "face", "jaw", "hair", "hat", "helmet"},
    arm_L = {"l_upperarm", "left_upperarm", "l upperarm", "left upperarm", "l_arm", "left_arm", "leftarm"},
    arm_R = {"r_upperarm", "right_upperarm", "r upperarm", "right upperarm", "r_arm", "right_arm", "rightarm"},
    forearm_L = {"l_forearm", "left_forearm", "l forearm", "left forearm", "l_lowerarm", "left_lowerarm"},
    forearm_R = {"r_forearm", "right_forearm", "r forearm", "right forearm", "r_lowerarm", "right_lowerarm"},
    hand_L = {"l_hand", "left_hand", "lefthand", "l finger", "l_finger", "left finger", "left_finger"},
    hand_R = {"r_hand", "right_hand", "righthand", "r finger", "r_finger", "right finger", "right_finger"},
    thigh_L = {"l_thigh", "left_thigh", "l thigh", "left thigh", "l_upperleg", "left_upperleg", "l_leg", "left_leg"},
    thigh_R = {"r_thigh", "right_thigh", "r thigh", "right thigh", "r_upperleg", "right_upperleg", "r_leg", "right_leg"},
    crus_L = {"l_calf", "left_calf", "l calf", "left calf", "l_lowerleg", "left_lowerleg", "l_shin", "left_shin"},
    crus_R = {"r_calf", "right_calf", "r calf", "right calf", "r_lowerleg", "right_lowerleg", "r_shin", "right_shin"},
    foot_L = {"l_foot", "left_foot", "leftfoot", "l toe", "l_toe", "left toe", "left_toe"},
    foot_R = {"r_foot", "right_foot", "rightfoot", "r toe", "r_toe", "right toe", "right_toe"}
}

local BodygroupMatches = {
    head = {"head", "neck", "face", "hair", "hat", "helmet"},
    arm_L = {"arm_l", "l_arm", "left_arm", "leftarm"},
    arm_R = {"arm_r", "r_arm", "right_arm", "rightarm"},
    forearm_L = {"forearm_l", "l_forearm", "left_forearm", "leftforearm"},
    forearm_R = {"forearm_r", "r_forearm", "right_forearm", "rightforearm"},
    hand_L = {"hand_l", "l_hand", "left_hand", "lefthand"},
    hand_R = {"hand_r", "r_hand", "right_hand", "righthand"},
    thigh_L = {"thigh_l", "l_thigh", "left_thigh", "leftthigh", "leg_l", "left_leg"},
    thigh_R = {"thigh_r", "r_thigh", "right_thigh", "rightthigh", "leg_r", "right_leg"},
    crus_L = {"crus_l", "l_crus", "left_crus", "leftcrus", "shin_l", "left_shin"},
    crus_R = {"crus_r", "r_crus", "right_crus", "rightcrus", "shin_r", "right_shin"},
    foot_L = {"foot_l", "l_foot", "left_foot", "leftfoot"},
    foot_R = {"foot_r", "r_foot", "right_foot", "rightfoot"}
}

local function ForEachDismembermentBone(ent, limbName, callback)
    if not IsValid(ent) or not isfunction(callback) then return end

    local visited = {}
    local bones = LimbToBones[limbName]
    if bones then
        for _, boneName in ipairs(bones) do
            local boneIndex = ent:LookupBone(boneName)
            if boneIndex and boneIndex >= 0 and not visited[boneIndex] then
                visited[boneIndex] = true
                callback(boneIndex)
            end
        end
    end

    local patterns = LimbBoneNamePatterns[limbName]
    if not patterns or not ent.GetBoneCount or not ent.GetBoneName then return end

    for boneIndex = 0, ent:GetBoneCount() - 1 do
        if not visited[boneIndex] then
            local lowerName = string.lower(tostring(ent:GetBoneName(boneIndex) or ""))
            for _, pattern in ipairs(patterns) do
                if string.find(lowerName, pattern, 1, true) then
                    visited[boneIndex] = true
                    callback(boneIndex)
                    break
                end
            end
        end
    end
end

local function SetLimbBodygroupState(ent, limbName, hide)
    if not IsValid(ent) or not ent.GetNumBodyGroups then return end

    local patterns = BodygroupMatches[limbName]
    if not patterns then return end

    local entIndex = ent:EntIndex()
    Visuals.BodygroupDefaults[entIndex] = Visuals.BodygroupDefaults[entIndex] or {}
    local defaults = Visuals.BodygroupDefaults[entIndex]

    for i = 0, ent:GetNumBodyGroups() - 1 do
        local name = string.lower(ent:GetBodygroupName(i) or "")
        for _, pattern in ipairs(patterns) do
            if string.find(name, pattern, 1, true) then
                if defaults[i] == nil and not hide then
                    defaults[i] = ent:GetBodygroup(i)
                end

                if hide then
                    if defaults[i] == nil then
                        defaults[i] = ent:GetBodygroup(i)
                    end
                    ent:SetBodygroup(i, 1)
                else
                    ent:SetBodygroup(i, defaults[i] or ent:GetBodygroup(i))
                end
                break
            end
        end
    end
end

local function ApplyToEntity(ent, state)
    if not IsValid(ent) or not state then return end

    local entIndex = ent:EntIndex()
    local signatureParts = {}
    for _, limbName in ipairs(LimbOrder) do
        if state[limbName] then
            signatureParts[#signatureParts + 1] = limbName
        end
    end

    local signature = table.concat(signatureParts, "|")
    if signature == "" then
        if not Visuals.AppliedSignatures[entIndex] then return end
        Visuals.AppliedSignatures[entIndex] = nil
    elseif Visuals.AppliedSignatures[entIndex] == signature then
        return
    else
        Visuals.AppliedSignatures[entIndex] = signature
    end

    for limbName in pairs(LimbToBones) do
        ForEachDismembermentBone(ent, limbName, function(boneIndex)
            ent:ManipulateBoneScale(boneIndex, Vector(1, 1, 1))
        end)
        SetLimbBodygroupState(ent, limbName, false)
    end

    for limbName, dismembered in pairs(state) do
        if dismembered then
            ForEachDismembermentBone(ent, limbName, function(boneIndex)
                ent:ManipulateBoneScale(boneIndex, Vector(0, 0, 0))
            end)
            SetLimbBodygroupState(ent, limbName, true)
        end
    end
end

local function RestoreEntityVisuals(ent)
    if not IsValid(ent) then return end

    for limbName in pairs(LimbToBones) do
        ForEachDismembermentBone(ent, limbName, function(boneIndex)
            ent:ManipulateBoneScale(boneIndex, Vector(1, 1, 1))
        end)
        SetLimbBodygroupState(ent, limbName, false)
    end

    Visuals.BodygroupDefaults[ent:EntIndex()] = nil
    Visuals.AppliedSignatures[ent:EntIndex()] = nil
end

local function ResetPlayerVisuals(ply)
    if not IsValid(ply) then return end

    Visuals.States[ply:EntIndex()] = nil
    RestoreEntityVisuals(ply)
    RestoreEntityVisuals(ply:GetNWEntity("WoundSystemUnconsciousRagdoll"))
    RestoreEntityVisuals(ply:GetNWEntity("WoundSystemDeathRagdoll"))
end

local function ApplyPlayerVisuals(ply)
    if not IsValid(ply) then return end

    local state = Visuals.States[ply:EntIndex()]
    if not state then return end

    ApplyToEntity(ply, state)
    ApplyToEntity(ply:GetNWEntity("WoundSystemUnconsciousRagdoll"), state)
    ApplyToEntity(ply:GetNWEntity("WoundSystemDeathRagdoll"), state)
end

local function ReadCorpseVisualState(ragdoll)
    if not IsValid(ragdoll) then return nil end
    if not ragdoll:GetNWBool("WoundSystemDeadUnconsciousBody", false) and not ragdoll:GetNWBool("WoundSystemDeathRagdoll", false) then return nil end

    local state = {}
    local hasDismemberedLimb = false
    for _, limbName in ipairs(LimbOrder) do
        local dismembered = ragdoll:GetNWBool("WoundSystemDismembered_" .. limbName, false)
        state[limbName] = dismembered
        hasDismemberedLimb = hasDismemberedLimb or dismembered
    end

    return hasDismemberedLimb and state or nil
end

net.Receive("WoundSystem_DismemberVisuals", function()
    if not WoundSystemClientEnabled() then return end

    local ply = net.ReadEntity()
    local count = net.ReadUInt(5)
    if not IsValid(ply) then
        for _ = 1, count do
            net.ReadString()
            net.ReadBool()
        end
        return
    end

    local state = {}
    for _ = 1, count do
        state[net.ReadString()] = net.ReadBool()
    end

    Visuals.States[ply:EntIndex()] = state
    ApplyPlayerVisuals(ply)
end)

net.Receive("WoundSystem_ResetDismemberVisuals", function()
    ResetPlayerVisuals(net.ReadEntity())
end)

hook.Add("Think", "WoundSystem_DismembermentVisualsThink", function()
    if not WoundSystemClientEnabled() then
        for entIndex in pairs(Visuals.BodygroupDefaults) do
            RestoreEntityVisuals(Entity(entIndex))
        end

        table.Empty(Visuals.States)
        table.Empty(Visuals.BodygroupDefaults)
        table.Empty(Visuals.AppliedSignatures)
        return
    end

    if (Visuals.NextApplyAt or 0) > CurTime() then return end
    Visuals.NextApplyAt = CurTime() + 0.25

    for entIndex in pairs(Visuals.BodygroupDefaults) do
        if not IsValid(Entity(entIndex)) then
            Visuals.BodygroupDefaults[entIndex] = nil
            Visuals.AppliedSignatures[entIndex] = nil
        end
    end

    for entIndex in pairs(Visuals.States) do
        if not IsValid(Entity(entIndex)) then
            Visuals.States[entIndex] = nil
            Visuals.AppliedSignatures[entIndex] = nil
        end
    end

    for entIndex in pairs(Visuals.AppliedSignatures) do
        if not IsValid(Entity(entIndex)) then
            Visuals.AppliedSignatures[entIndex] = nil
        end
    end

    for _, ply in ipairs(player.GetAll()) do
        ApplyPlayerVisuals(ply)
    end

    for _, className in ipairs({"prop_ragdoll", "hl2mp_ragdoll"}) do
        for _, ragdoll in ipairs(ents.FindByClass(className)) do
            local owner = ragdoll:GetNWEntity("WoundSystemOwner")
            local state = ReadCorpseVisualState(ragdoll) or (IsValid(owner) and Visuals.States[owner:EntIndex()] or nil)
            if state then
                ApplyToEntity(ragdoll, state)
            end
        end
    end
end)
