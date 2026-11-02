-- RU: лечение и перевязка через круговой селектор при наведении на конечность с предметом в руках
-- All minigames playable with item in hands via radial, bandage blocked until shards extracted
if CLIENT then

-- Map Z-City SWEP class -> WoundSystem itemId
local SWEPExtractMap = {
    weapon_bandage_sh = "GAUZE",
    weapon_bigbandage_sh = "STERILIZEDBANDAGE",
    weapon_tourniquet = "TOURNIQUET",
    weapon_medkit_sh = "GAUZE", -- mode 1 fallback
    weapon_needle = "INJECTION",
}
-- Which SWEPs count as "medical tool in hands" for generic extraction permission
local function IsMedicalInHands()
    local wep = LocalPlayer():GetActiveWeapon()
    if not IsValid(wep) then return false end
    local c = wep:GetClass()
    if c == "weapon_hands_sh" then return false end -- fists not medical, but allow for glass? RU says extract with tool, so require medical
    if SWEPExtractMap[c] then return true end
    -- also allow any wound medical via check
    if string.find(c, "bandage") or string.find(c, "tourniquet") or string.find(c, "needle") or string.find(c, "morphine") or string.find(c, "medkit") then return true end
    return false
end

local allLimbs = {"head","thorax","abdomen","arm_L","forearm_L","hand_L","arm_R","forearm_R","hand_R","thigh_L","crus_L","foot_L","thigh_R","crus_R","foot_R"}

local function GetClientLimbState(limbId)
    if WoundSystemClientState and WoundSystemClientState.PlayerLimbs then
        return WoundSystemClientState.PlayerLimbs[limbId]
    end
    return nil
end

local function LimbNeedsBandage(state)
    if not state or state.dismembered then return false end
    if state.isBandaged then return false end
    -- check glass block first
    if state.customStatuses and state.customStatuses["GLASS_SHARD"] and tonumber(state.customStatuses["GLASS_SHARD"]) > 0 then return false end
    if (state.glassShards or 0) > 0 then return false end
    if (state.bleed or 0) < 0.08 then return false end
    return true
end

local function HasGlass(state)
    if not state then return false end
    if state.customStatuses and state.customStatuses["GLASS_SHARD"] and tonumber(state.customStatuses["GLASS_SHARD"]) > 0 then return true end
    if (state.glassShards or 0) > 0 then return true end
    return false
end

-- Helper to resolve aimed limb via eye trace (for healing others)
local function GetAimedLimbInfo()
    if not hg or not hg.eyeTrace then return nil, nil end
    local tr = hg.eyeTrace(LocalPlayer())
    if not tr or not IsValid(tr.Entity) then return nil, nil end
    local ent = tr.Entity
    local targetPly = nil
    if ent:IsPlayer() then targetPly = ent
    elseif hg.RagdollOwner then targetPly = hg.RagdollOwner(ent) end
    if not IsValid(targetPly) then
        -- maybe looking at self ragdoll? fallback to self
        return nil, nil
    end
    -- Resolve limb from bone if ragdoll
    local limbId = nil
    if ent:IsRagdoll() and tr.PhysicsBone and WoundSystem and WoundSystem.Health and WoundSystem.Health.RagdollBoneNameToLimb then
        local bone = ent:TranslatePhysBoneToBone(tr.PhysicsBone)
        local bname = ent:GetBoneName(bone)
        limbId = WoundSystem.Health.RagdollBoneNameToLimb(bname)
    end
    -- fallback via hitgroup not available client side
    return targetPly, limbId
end

hook.Add("radialOptions", "WoundSystem_HealRadial", function()
    if not IsValid(LocalPlayer()) or not LocalPlayer():Alive() then return end
    if LocalPlayer().organism and LocalPlayer().organism.otrub then return end
    local wep = LocalPlayer():GetActiveWeapon()
    if not IsValid(wep) then return end
    local wepClass = wep:GetClass()
    local isMedical = IsMedicalInHands()
    -- we still allow glass extraction even without medical? per RU extraction needs tweezers/tool, but keep permissive: show extraction if any glass, regardless of tool, but prioritize medical
    -- BANDAGE logic: only if holding medical bandage-type
    local canBandage = (wepClass == "weapon_bandage_sh" or wepClass == "weapon_bigbandage_sh" or wepClass == "weapon_medkit_sh")

    -- 1. Self: use health GUI hover or all bleeding limbs
    local selfOptionsAdded = 0

    -- a) If health GUI has a hovered limb (WoundSystemSelectedLimbId), offer action for that single limb
    if WoundSystemSelectedLimbId then
        local limbId = WoundSystemSelectedLimbId
        local st = GetClientLimbState(limbId)
        if st and HasGlass(st) then
            -- extraction takes priority over bandage
            hg.radialOptions[#hg.radialOptions+1] = {function() RunConsoleCommand("woundsys_glass_extract", limbId) end, "Extract glass ("..limbId..")"}
            selfOptionsAdded = selfOptionsAdded + 1
        elseif st and canBandage and LimbNeedsBandage(st) then
            hg.radialOptions[#hg.radialOptions+1] = {function() RunConsoleCommand("woundsys_radial_heal", limbId) end, "Bandage "..limbId}
            selfOptionsAdded = selfOptionsAdded + 1
        elseif st and canBandage and st and st.customStatuses and st.customStatuses["GLASS_SHARD"] then
            hg.radialOptions[#hg.radialOptions+1] = {function() LocalPlayer():ChatPrint("Remove glass from "..limbId.." first!") end, "Blocked: glass in "..limbId}
            selfOptionsAdded = selfOptionsAdded + 1
        end
    end

    -- b) If no specific hover, offer per-limb options for all limbs that need care (self)
    if selfOptionsAdded == 0 then
        for _, limbId in ipairs(allLimbs) do
            local st = GetClientLimbState(limbId)
            if not st then continue end
            if HasGlass(st) then
                hg.radialOptions[#hg.radialOptions+1] = {function() RunConsoleCommand("woundsys_glass_extract", limbId) end, "Extract glass ("..limbId..")"}
            elseif canBandage and LimbNeedsBandage(st) then
                hg.radialOptions[#hg.radialOptions+1] = {function() RunConsoleCommand("woundsys_radial_heal", limbId) end, "Bandage "..limbId}
            end
        end
    end

    -- 2. Other player via eye trace: offer heal for aimed limb if valid
    local targetPly, aimedLimb = GetAimedLimbInfo()
    if IsValid(targetPly) and targetPly ~= LocalPlayer() and aimedLimb then
        -- For other player we don't have client limb state, so we just offer generic heal if holding medical
        if canBandage then
            hg.radialOptions[#hg.radialOptions+1] = {function() net.Start("WoundSystem_RadialHealOther") net.WriteEntity(targetPly) net.WriteString(aimedLimb) net.SendToServer() end, "Bandage "..targetPly:Nick().." "..aimedLimb}
        end
        -- glass extraction for other player: we need server to validate, but we can show option if we believe target has glass (we don't know). Offer if we hold medical and target is ragdoll?
        if isMedical then
            -- show extract option for aimed limb (server will reject if no glass)
            hg.radialOptions[#hg.radialOptions+1] = {function() net.Start("WoundSystem_GlassRequestOther") net.WriteEntity(targetPly) net.WriteString(aimedLimb) net.SendToServer() end, "Extract glass "..targetPly:Nick().." "..aimedLimb}
        end
    end
end)

-- console commands for healing via menu
concommand.Add("woundsys_radial_heal", function(ply, cmd, args)
    local limb = args[1]
    if not limb or limb == "" then return end
    net.Start("WoundSystem_RadialHeal")
        net.WriteString(limb)
    net.SendToServer()
end)

end
