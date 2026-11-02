WoundSystem = WoundSystem or {}
WoundSystem.Health = WoundSystem.Health or {}

-- Server-side glass minigame orchestration
-- RU: мини-игра с осколками стекла - только вручную через круговой селектор, боль растёт только при неудачных попытках до бессознанки

-- pooled via sh_core.lua: WoundSystem_GlassStart etc already pooled; keep pcall for safety
pcall(function() util.AddNetworkString("WoundSystem_GlassStart") end)
pcall(function() util.AddNetworkString("WoundSystem_GlassRequest") end)
pcall(function() util.AddNetworkString("WoundSystem_GlassSuccess") end)
pcall(function() util.AddNetworkString("WoundSystem_GlassPain") end)
pcall(function() util.AddNetworkString("WoundSystem_GlassFaint") end)

-- Helper to check if player has glass in limb
local function HasGlass(ply, limbId)
    if WoundSystem.GlassShard and WoundSystem.GlassShard.HasShard then
        return WoundSystem.GlassShard.HasShard(ply, limbId)
    end
    return false
end

-- Player requests to start extraction for chosen limb via radial menu
net.Receive("WoundSystem_GlassRequest", function(_, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local limbId = net.ReadString()
    if not limbId or limbId == "" then return end
    -- validate limb belongs to player
    local H = WoundSystem.Health
    local PlayerLimbs = H and (H.PlayerLimbs or _G.PlayerLimbs)
    if not PlayerLimbs or not PlayerLimbs[ply] or not PlayerLimbs[ply][limbId] then return end
    if not HasGlass(ply, limbId) then
        if ply.Notify then ply:Notify("No glass shard in "..limbId, 1, "glass_no", 1, nil, Color(255,180,120,255)) end
        return
    end
    -- pain block check like dislocation: if pain too high need analgesia
    local body = H.BodyState and H.BodyState[ply] or nil
    local painBlocked = false
    if body then
        local opiate = (body.opiateAmount or 0) + (body.analgesia or 0)
        if ply.organism then opiate = opiate + (ply.organism.painkiller or 0) + (ply.organism.analgesia or 0) end
        if opiate < 1.0 and (body.avgPain or 0) > 75 then painBlocked = true end
        if (PlayerLimbs[ply][limbId].pain or 0) > 78 and opiate < 0.6 then painBlocked = true end
    end
    if painBlocked then
        ply:Notify("Too much pain to focus - take Z-City painkiller first", 1, "glass_painblock", 2, nil, Color(255,120,120,255))
        return
    end

    -- start minigame
    net.Start("WoundSystem_GlassStart")
        net.WriteString(limbId)
    net.Send(ply)
    ply._woundSystemGlassLimb = limbId
    ply._woundSystemGlassFailCount = 0
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
        -- push avgPain via pain contribution; also consciousness drop if high pain
        if state.pain >= 85 then
            body.shock = math.Clamp((body.shock or 0) + 1.2, 0, 100)
        end
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
    -- if too many fails (6+) faint уже handled via GlassFaint, but also trigger if pain spike high
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
    -- RU: частые ошибки при извлечении ведут к обмороку
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

-- Client reports success
net.Receive("WoundSystem_GlassSuccess", function(_, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local limbId = net.ReadString()
    if not HasGlass(ply, limbId) then return end
    if WoundSystem.GlassShard and WoundSystem.GlassShard.RemoveOne then
        WoundSystem.GlassShard.RemoveOne(ply, limbId)
        ply:EmitSound("physics/flesh/flesh_impact_hard6.wav", 58)
        -- success reduces overall pain a bit
        local H = WoundSystem.Health
        local PlayerLimbs = H and (H.PlayerLimbs or _G.PlayerLimbs)
        if PlayerLimbs and PlayerLimbs[ply] and PlayerLimbs[ply][limbId] then
            PlayerLimbs[ply][limbId].pain = math.Clamp((PlayerLimbs[ply][limbId].pain or 0) - 10, 0, 100)
            if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end
        end
        if HasGlass(ply, limbId) then
            ply:Notify("Another shard remains in "..limbId.." - extract again via radial menu", 1, "glass_more", 2, nil, Color(180,220,255,255))
        else
            ply:Notify("Glass shard removed from "..limbId, 1, "glass_done", 2, nil, Color(120,255,120,255))
        end
    end
    ply._woundSystemGlassLimb = nil
    ply._woundSystemGlassFailCount = 0
end)

-- Helper for other code to embed glass (used by woundbridge)
WoundSystem.Health.AddGlassShard = function(ply, limbId, count, fromZCity)
    if WoundSystem.GlassShard and WoundSystem.GlassShard.AddShard then
        return WoundSystem.GlassShard.AddShard(ply, limbId, count, 9)
    end
    return false
end
