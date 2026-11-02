-- Server: handle radial heal requests (bandage via menu with item in hands, extraction prerequisite)
if SERVER then

util.AddNetworkString("WoundSystem_RadialHeal")
util.AddNetworkString("WoundSystem_RadialHealOther")
util.AddNetworkString("WoundSystem_GlassRequestOther")

local BANDAGE_MAP = {
    weapon_bandage_sh = {item="GAUZE", durNeed=8},
    weapon_bigbandage_sh = {item="STERILIZEDBANDAGE", durNeed=8},
    weapon_medkit_sh = {item="GAUZE", durNeed=8}, -- medkit mode 1 is gauze
}

local function GetHealItemForSWEP(swep)
    if not IsValid(swep) then return nil end
    local c = swep:GetClass()
    return BANDAGE_MAP[c]
end

local function ConsumeSWEP(swep, amount)
    if not IsValid(swep) or not swep.modeValues then return end
    local idx = 1
    if swep:GetClass() == "weapon_medkit_sh" then idx = swep.mode or 1 end
    local cur = (swep.modeValues[idx] or 0)
    swep.modeValues[idx] = math.max(cur - (amount or 0), 0)
    -- if empty and should delete, let woundbridge handle deletion later, but we can notify
    if swep.modeValues[idx] <= 0 then
        -- don't immediately remove, allow woundbridge AfterUse to handle; just notify
        -- if all slots empty, remove
        local empty = true
        for i=1,5 do
            if swep:GetClass() ~= "weapon_medkit_sh" and i>1 then break end
            if (swep.modeValues[i] or 0) > 0 then empty = false break end
        end
        if empty and swep.ShouldDeleteOnFullUse ~= false then
            timer.Simple(0.1, function()
                if IsValid(swep) and IsValid(swep:GetOwner()) then
                    swep:GetOwner():SelectWeapon("weapon_hands_sh")
                    swep:Remove()
                end
            end)
        end
    end
end

local function TryBandage(ply, target, limbId)
    if not IsValid(ply) or not IsValid(target) then return false end
    if not ply:Alive() or not target:Alive() then return false end
    if ply:GetPos():DistToSqr(target:GetPos()) > (250*250) and ply ~= target then
        ply:Notify("Too far to bandage", 1, "heal_far", 1, nil, Color(255,180,120,255))
        return false
    end
    local swep = ply:GetActiveWeapon()
    local m = GetHealItemForSWEP(swep)
    if not m then
        ply:Notify("Hold bandage in hands to bandage", 1, "heal_noitem", 1, nil, Color(255,150,150,255))
        return false
    end
    local itemId = m.item
    -- Check glass block (also enforced in sv_health ApplyItemToBody, but we give early feedback)
    if WoundSystem and WoundSystem.GlassShard and WoundSystem.GlassShard.HasShard and WoundSystem.GlassShard.HasShard(target, limbId) then
        ply:Notify("Remove glass shard from "..limbId.." before bandaging!", 1, "glass_block", 1, nil, Color(255,170,120,255))
        return false
    end
    -- Check if limb needs bandage
    local H = WoundSystem and WoundSystem.Health
    local limbs = H and H.PlayerLimbs and H.PlayerLimbs[target]
    local st = limbs and limbs[limbId]
    if not st or st.dismembered then
        ply:Notify("Invalid limb "..(limbId or "?"), 1, "heal_invalid", 1, nil, Color(255,150,150,255))
        return false
    end
    if st.isBandaged then
        ply:Notify(limbId.." already bandaged", 1, "heal_bandaged", 1, nil, Color(180,220,255,255))
        return false
    end
    if (st.bleed or 0) < 0.05 then
        ply:Notify(limbId.." not bleeding (bleed="..math.Round(st.bleed or 0,2)..")", 1, "heal_nobleed", 1, nil, Color(180,220,255,255))
        return false
    end

    -- Try to trigger minigame if enabled, else direct apply
    local WB = hg and hg.WoundBridge
    if WB and WB.cvMinigame and WB.cvMinigame:GetBool() and WB.SwepSpecs then
        -- Try to start minigame via woundbridge StartMinigame logic: reuse SwepHeal path but force limb
        -- We can directly call ApplyItemToBody with minigame simulation: for bandage, we want minigame flow
        -- Instead we use H.StartExternalMinigame if available
        if H.StartExternalMinigame and H.HasExternalMinigame and not H.HasExternalMinigame(ply) then
            local spec = WB.SwepSpecs[swep:GetClass()] or {kind="bandage", item=itemId, rate=25, mg={kind="bandage"}}
            local maxDur = (WoundSystem.Items and WoundSystem.Items.GetMax and WoundSystem.Items.GetMax(itemId)) or 100
            local def = (swep.modeValuesdef and swep.modeValuesdef[1] and (istable(swep.modeValuesdef[1]) and swep.modeValuesdef[1][1] or swep.modeValuesdef[1])) or 40
            local remaining = (swep.modeValues and swep.modeValues[1]) or 0
            local amount = remaining / math.max(def,0.001) * maxDur
            if amount <= 0 then ply:Notify("Bandage empty",1,"heal_empty",1,nil,Color(255,150,150,255)) return false end
            local started = H.StartExternalMinigame(ply, {
                kind="bandage",
                itemId=itemId,
                limbId=limbId,
                amount=amount,
                onProgress = function(p, session, durCost)
                    if not IsValid(swep) or not IsValid(target) then return end
                    local ok = H.ApplyItemToBody(target, itemId, limbId, durCost)
                    if ok then ConsumeSWEP(swep, durCost / math.max(maxDur,1) * def) end
                end,
                onClose = function(p, session, reason)
                    -- woundbridge already handles consume via AfterUse, but we ensure
                end
            })
            if started then return true end
        end
    end

    -- Direct instant bandage (no minigame) fallback
    local ok, used = H.ApplyItemToBody(target, itemId, limbId, 25)
    if not ok then
        ply:Notify("Bandage failed",1,"heal_fail",1,nil,Color(255,150,150,255))
        return false
    end
    -- consume swep
    local def = (swep.modeValuesdef and swep.modeValuesdef[1] and (istable(swep.modeValuesdef[1]) and swep.modeValuesdef[1][1] or swep.modeValuesdef[1])) or 40
    ConsumeSWEP(swep, (used or 25)/100 * def)
    ply:Notify("Bandaged "..target:Nick().." "..limbId,1,"heal_ok",1,nil,Color(120,255,120,255))
    if target ~= ply then target:Notify(ply:Nick().." bandaged your "..limbId,1,"heal_target",1,nil,Color(120,255,120,255)) end
    return true
end

net.Receive("WoundSystem_RadialHeal", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local limbId = net.ReadString()
    if not limbId or limbId == "" then return end
    -- self or aimed: if ply is looking at someone, use that as target, otherwise self
    local target = ply
    -- check if ply is aiming at another player/ragdoll
    if hg and hg.eyeTrace then
        local tr = hg.eyeTrace(ply)
        if IsValid(tr.Entity) then
            local tp = hg.RagdollOwner and hg.RagdollOwner(tr.Entity) or (tr.Entity:IsPlayer() and tr.Entity or nil)
            if IsValid(tp) and tp ~= ply and tp:Alive() and ply:GetPos():DistToSqr(tp:GetPos()) < 250*250 then
                target = tp
            end
        end
    end
    TryBandage(ply, target, limbId)
end)

net.Receive("WoundSystem_RadialHealOther", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local target = net.ReadEntity()
    local limbId = net.ReadString()
    if not IsValid(target) or not limbId or limbId=="" then return end
    TryBandage(ply, target, limbId)
end)

-- Glass extraction for other player via radial
net.Receive("WoundSystem_GlassRequestOther", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local target = net.ReadEntity()
    local limbId = net.ReadString()
    if not IsValid(target) or not limbId or limbId=="" then return end
    if ply:GetPos():DistToSqr(target:GetPos()) > 250*250 then ply:Notify("Too far",1,"glass_far",1,nil,Color(255,180,120,255)) return end
    if not WoundSystem or not WoundSystem.GlassShard or not WoundSystem.GlassShard.HasShard then return end
    if not WoundSystem.GlassShard.HasShard(target, limbId) then ply:Notify("No glass in "..limbId.." of "..target:Nick(),1,"glass_no_other",1,nil,Color(255,180,120,255)) return end
    -- reuse existing glass request logic: send GlassStart to requestor? But extraction should be on target's limb, but minigame is per-player. 
    -- For other player, we allow the healer to extract: remove shard from target
    -- We will directly trigger extraction success path after minigame? For now, we start minigame for healer that will operate on target limb
    -- Store target for success
    ply._woundSystemGlassTarget = target
    ply._woundSystemGlassLimb = limbId
    net.Start("WoundSystem_GlassStart")
        net.WriteString(limbId)
    net.Send(ply)
end)

-- Intercept GlassSuccess to support other-player extraction
hook.Add("WoundSystem_GlassShardRemoved", "GlassRadial_OtherFix", function(ply, limbId)
    -- placeholder: if healer extracted from other, this is handled via modified success handler below
end)

-- Override GlassSuccess to check if it was for other player
local origGlassSuccess = nil
timer.Simple(0.5, function()
    -- patch net receiver for GlassSuccess after sv_glass.lua loaded
    local rec = net.Receivers and net.Receivers["WoundSystem_GlassSuccess"]
    if rec then
        origGlassSuccess = rec
        net.Receive("WoundSystem_GlassSuccess", function(len, ply)
            if not IsValid(ply) or not ply:Alive() then return end
            local limbId = net.ReadString()
            local target = ply._woundSystemGlassTarget or ply
            if WoundSystem and WoundSystem.GlassShard and WoundSystem.GlassShard.HasShard then
                if not WoundSystem.GlassShard.HasShard(target, limbId) then return end
                WoundSystem.GlassShard.RemoveOne(target, limbId)
                ply:EmitSound("physics/flesh/flesh_impact_hard6.wav",58)
                local H = WoundSystem.Health
                local PlayerLimbs = H and H.PlayerLimbs and H.PlayerLimbs[target]
                if PlayerLimbs and PlayerLimbs[limbId] then
                    PlayerLimbs[limbId].pain = math.Clamp((PlayerLimbs[limbId].pain or 0) -10,0,100)
                    if H.SendLimbUpdate then H.SendLimbUpdate(target, limbId, true) end
                end
                if target ~= ply then
                    ply:Notify("Removed glass from "..target:Nick().." "..limbId,1,"glass_done_other",1,nil,Color(120,255,120,255))
                    target:Notify(ply:Nick().." removed glass from "..limbId,1,"glass_done_target",1,nil,Color(120,255,120,255))
                else
                    if WoundSystem.GlassShard.HasShard(target, limbId) then
                        ply:Notify("Another shard remains in "..limbId,1,"glass_more",1,nil,Color(180,220,255,255))
                    else
                        ply:Notify("Glass shard removed from "..limbId,1,"glass_done",1,nil,Color(120,255,120,255))
                    end
                end
            end
            ply._woundSystemGlassLimb = nil
            ply._woundSystemGlassTarget = nil
            ply._woundSystemGlassFailCount = 0
        end)
    end
end)

end
