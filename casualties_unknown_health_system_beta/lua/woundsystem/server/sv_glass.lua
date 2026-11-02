WoundSystem = WoundSystem or {}
WoundSystem.Health = WoundSystem.Health or {}

-- Server-side glass/shrapnel handling: shrapnel embedded only on glass (including ragdoll)
-- RU: shrapnel state.shrapnel 0-5, hand extraction via Examine Body, infection persists, bandage allowed

pcall(function() util.AddNetworkString("WoundSystem_GlassStart") end)
pcall(function() util.AddNetworkString("WoundSystem_GlassRequest") end)
pcall(function() util.AddNetworkString("WoundSystem_GlassSuccess") end)
pcall(function() util.AddNetworkString("WoundSystem_GlassPain") end)
pcall(function() util.AddNetworkString("WoundSystem_GlassFaint") end)
pcall(function() util.AddNetworkString("WoundSystem_GlassHandExtract") end)

local function HasShrapnel(ply, limbId)
    local H = WoundSystem.Health
    local PlayerLimbs = H and (H.PlayerLimbs or _G.PlayerLimbs)
    if not PlayerLimbs or not PlayerLimbs[ply] then return false end
    local st = PlayerLimbs[ply][limbId]
    if not st or st.dismembered then return false end
    if (tonumber(st.shrapnel) or 0) > 0 then return true end
    -- legacy compat: old GLASS_SHARD
    if st.customStatuses and st.customStatuses["GLASS_SHARD"] and tonumber(st.customStatuses["GLASS_SHARD"]) > 0 then return true end
    if (st.glassShards or 0) > 0 then return true end
    return false
end

local function DoHandExtract(ply, limbId)
    if not IsValid(ply) or not ply:Alive() then return false end
    if not limbId or limbId == "" then return false end
    local H = WoundSystem.Health
    local PlayerLimbs = H and (H.PlayerLimbs or _G.PlayerLimbs)
    if not PlayerLimbs or not PlayerLimbs[ply] or not PlayerLimbs[ply][limbId] then return false end
    local st = PlayerLimbs[ply][limbId]
    if not HasShrapnel(ply, limbId) then
        if ply.Notify then ply:Notify("No shard in "..limbId, 1, "glass_no", 1, nil, Color(255,180,120,255)) end
        return false
    end
    local body = H.BodyState and H.BodyState[ply] or nil
    local painBlocked = false
    if body then
        local opiate = (body.opiateAmount or 0) + (body.analgesia or 0)
        if ply.organism then opiate = opiate + (ply.organism.painkiller or 0) + (ply.organism.analgesia or 0) end
        if opiate < 1.0 and (body.avgPain or 0) > 75 then painBlocked = true end
        if (st.pain or 0) > 78 and opiate < 0.6 then painBlocked = true end
    end
    if painBlocked then
        ply:Notify("Too much pain - take Z-City painkiller first", 1, "glass_painblock", 2, nil, Color(255,120,120,255))
        return false
    end
    -- decrement shrapnel (native) + SHRAPNEL status sync
    if (tonumber(st.shrapnel) or 0) > 0 then
        st.shrapnel = math.Clamp((tonumber(st.shrapnel) or 1) - 1, 0, 5)
        if st.shrapnel == 0 then st.shrapnel = nil end
        -- keep customStatuses SHRAPNEL in sync for client (via statusSnapshot)
        if WoundSystem.Statuses then
            if st.shrapnel and st.shrapnel > 0 then WoundSystem.Statuses.Set(st, "SHRAPNEL", st.shrapnel)
            else WoundSystem.Statuses.Clear(st, "SHRAPNEL") end
        end
    elseif st.customStatuses and st.customStatuses["SHRAPNEL"] then
        local cur = tonumber(st.customStatuses["SHRAPNEL"]) or 1
        cur = cur - 1
        if cur <= 0 then WoundSystem.Statuses.Clear(st, "SHRAPNEL") else WoundSystem.Statuses.Set(st, "SHRAPNEL", cur) end
        -- also keep field in sync
        if cur <= 0 then st.shrapnel = nil else st.shrapnel = cur end
    elseif st.customStatuses and st.customStatuses["GLASS_SHARD"] then
        -- migrate legacy
        if WoundSystem.GlassShard and WoundSystem.GlassShard.RemoveOne then
            WoundSystem.GlassShard.RemoveOne(ply, limbId)
        else
            local cur = tonumber(st.customStatuses["GLASS_SHARD"]) or 1
            cur = cur - 1
            if cur <= 0 then WoundSystem.Statuses.Clear(st, "GLASS_SHARD") else WoundSystem.Statuses.Set(st, "GLASS_SHARD", cur) end
        end
    elseif (st.glassShards or 0) > 0 then
        st.glassShards = (st.glassShards or 1) - 1
        if st.glassShards <= 0 then st.glassShards = nil end
    end
    ply:EmitSound("physics/flesh/flesh_impact_hard6.wav", 58)
    -- hand pull causes moderate extra pain/bleed, mirrors Fn.AddGunshotShrapnel pattern
    st.pain = math.Clamp((st.pain or 0) + 6, 0, 100)
    st.bleed = math.Clamp((st.bleed or 0) + 6, 0, 100)
    st.skin = math.Clamp((st.skin or 100) - 2, 0, 100)
    if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end
    if H.SendCardioUpdate then H.SendCardioUpdate(ply, true) end
    if HasShrapnel(ply, limbId) then
        ply:Notify("Another shard remains in "..limbId.." - pull again", 1, "glass_more", 2, nil, Color(180,220,255,255))
    else
        ply:Notify("Shard pulled out from "..limbId.." by hands", 1, "glass_done", 2, nil, Color(120,255,120,255))
    end
    return true
end

net.Receive("WoundSystem_GlassRequest", function(_, ply)
    local limbId = net.ReadString()
    DoHandExtract(ply, limbId)
end)

net.Receive("WoundSystem_GlassHandExtract", function(_, ply)
    local limbId = net.ReadString()
    DoHandExtract(ply, limbId)
end)

-- Client reports pain increment on miss
net.Receive("WoundSystem_GlassPain", function(_, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local amount = net.ReadFloat() or 8
    local limbId = net.ReadString()
    local H = WoundSystem.Health
    local PlayerLimbs = H and (H.PlayerLimbs or _G.PlayerLimbs)
    local BodyState = H and (H.BodyState or _G.BodyState)
    if not PlayerLimbs or not PlayerLimbs[ply] then return end
    local state = PlayerLimbs[ply][limbId]
    if not state then return end
    local body = BodyState and BodyState[ply] or nil
    amount = math.Clamp(tonumber(amount) or 8, 4, 15)
    state.pain = math.Clamp((state.pain or 0) + amount, 0, 100)
    if body then
        if state.pain >= 85 then body.shock = math.Clamp((body.shock or 0) + 1.2, 0, 100) end
        if state.pain >= 92 and math.random(3)==1 then
            body.consciousness = math.Clamp((body.consciousness or 100) - amount*0.6, 0, 100)
            if (body.consciousness or 100) < 22 then
                body.unconscious = true
                body.wasUnconscious = true
                if H.TryCreateUnconsciousRagdoll then H.TryCreateUnconsciousRagdoll(ply, body) end
            end
        end
    end
    ply._woundSystemGlassFailCount = (ply._woundSystemGlassFailCount or 0) + 1
    if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end
    if H.SendCardioUpdate then H.SendCardioUpdate(ply, true) end
    if ply._woundSystemGlassFailCount >= 6 and body then
        if (body.avgPain or 0) > 72 or (state.pain or 0) > 88 then
            body.consciousness = math.Clamp((body.consciousness or 100) - 14, 0, 100)
            if body.consciousness <= 15 then
                body.unconscious = true
                body.wasUnconscious = true
                if H.TryCreateUnconsciousRagdoll then H.TryCreateUnconsciousRagdoll(ply, body) end
            end
            if H.SendCardioUpdate then H.SendCardioUpdate(ply, true) end
        end
    end
end)

net.Receive("WoundSystem_GlassFaint", function(_, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local limbId = net.ReadString()
    local H = WoundSystem.Health
    local PlayerLimbs = H and (H.PlayerLimbs or _G.PlayerLimbs)
    local BodyState = H and (H.BodyState or _G.BodyState)
    if not PlayerLimbs or not PlayerLimbs[ply] then return end
    local state = PlayerLimbs[ply][limbId]
    local body = BodyState and BodyState[ply]
    if not state or not body then return end
    state.pain = math.Clamp((state.pain or 0) + 14, 0, 100)
    body.consciousness = math.Clamp((body.consciousness or 100) - 22, 0, 100)
    body.shock = math.Clamp((body.shock or 0) + 18, 0, 100)
    if (body.consciousness or 100) < 30 then
        body.unconscious = true
        body.wasUnconscious = true
        if H.TryCreateUnconsciousRagdoll then H.TryCreateUnconsciousRagdoll(ply, body) end
    end
    if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end
    if H.SendCardioUpdate then H.SendCardioUpdate(ply, true) end
end)

-- Client reports success (legacy minigame path - treat as hand extract)
net.Receive("WoundSystem_GlassSuccess", function(_, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local limbId = net.ReadString()
    DoHandExtract(ply, limbId)
    ply._woundSystemGlassLimb = nil
    ply._woundSystemGlassFailCount = 0
end)

-- Helper for other code to embed shard (used by woundbridge) - now shrapnel (SHRAPNEL status for sync)
WoundSystem.Health.AddGlassShard = function(ply, limbId, count, fromZCity)
    if not IsValid(ply) then return false end
    local H = WoundSystem.Health
    local PlayerLimbs = H and (H.PlayerLimbs or _G.PlayerLimbs)
    if not PlayerLimbs or not PlayerLimbs[ply] then return false end
    local st = PlayerLimbs[ply][limbId]
    if not st or st.dismembered then return false end
    count = math.Clamp(tonumber(count) or 1, 1, 5)
    st.shrapnel = math.Clamp((tonumber(st.shrapnel) or 0) + count, 0, 5)
    if WoundSystem.Statuses and WoundSystem.Statuses.Set then
        WoundSystem.Statuses.Set(st, "SHRAPNEL", st.shrapnel)
    end
    st.bleed = math.Clamp((st.bleed or 0) + 9, 0, 100)
    st.pain = math.Clamp((st.pain or 0) + 14, 0, 100)
    st.skin = math.Clamp((st.skin or 100) - 7, 0, 100)
    if H.Fn and H.Fn.ClearLimbBandage then H.Fn.ClearLimbBandage(st) end
    if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end
    if H.SendCardioUpdate then H.SendCardioUpdate(ply, true) end
    return true
end

-- Direct shrapnel helper for new code
WoundSystem.Health.AddShrapnel = WoundSystem.Health.AddGlassShard
