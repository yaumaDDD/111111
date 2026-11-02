-- Sync glass limbs to client for radial menu
WoundSystem = WoundSystem or {}

if SERVER then
    pcall(function() util.AddNetworkString("WoundSystem_GlassSync") end)

    local function SyncGlassToPlayer(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        local H = WoundSystem.Health
        local PlayerLimbs = H and (H.PlayerLimbs or _G.PlayerLimbs)
        if not PlayerLimbs or not PlayerLimbs[ply] then return end
        local limbs = PlayerLimbs[ply]
        local glassLimbs = {}
        for limbId, state in pairs(limbs) do
            if state and state.customStatuses and state.customStatuses["GLASS_SHARD"] and (tonumber(state.customStatuses["GLASS_SHARD"]) or 0) > 0 then
                table.insert(glassLimbs, limbId)
            elseif state and (state.glassShards or 0) > 0 then
                table.insert(glassLimbs, limbId)
            end
        end
        net.Start("WoundSystem_GlassSync")
            net.WriteUInt(#glassLimbs, 4)
            for _, limbId in ipairs(glassLimbs) do
                net.WriteString(limbId)
            end
        net.Send(ply)
    end

    hook.Add("WoundSystem_GlassShardEmbedded", "WoundSystem_GlassSyncEmbedded", function(ply, limbId, count)
        timer.Simple(0.1, function() SyncGlassToPlayer(ply) end)
    end)
    hook.Add("WoundSystem_GlassShardRemoved", "WoundSystem_GlassSyncRemoved", function(ply, limbId)
        timer.Simple(0.1, function() SyncGlassToPlayer(ply) end)
    end)

    -- periodic sync every 5s
    timer.Create("WoundSystem_GlassSyncTimer", 4, 0, function()
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:Alive() then
                SyncGlassToPlayer(ply)
            end
        end
    end)

    -- on spawn sync
    hook.Add("PlayerSpawn", "WoundSystem_GlassSyncSpawn", function(ply)
        timer.Simple(1, function() SyncGlassToPlayer(ply) end)
    end)
end
