WoundSystem = WoundSystem or {}

-- RU: legacy GLASS_SHARD kept for saves, but active shards use SHRAPNEL (state.shrapnel / SHRAPNEL status)
if WoundSystem.Statuses then
    -- native shrapnel for glass: infection persists, bandage allowed but shrapnelClotMult 0 / canSkinHeal false handled in sv_health
    WoundSystem.Statuses.Register("SHRAPNEL", {
        title = "Shrapnel",
        desc = "Embedded glass/metal fragment. Must be pulled by hands via Examine Body. Bandage slows but does not stop bleed; infection persists.",
        icon = "casunknown-images/icons/bleeding.png",
        type = "number",
        order = 28,
        color = {180, 220, 255},
        tick = function(ctx, value, dt)
            if not ctx or not ctx.limb then return value end
            local limb = ctx.limb
            local body = ctx.body
            -- shrapnel bleed trickle - close to Z-City coagulate/bleed rhythm but visible
            limb.bleed = math.Clamp((limb.bleed or 0) + 0.04 * (dt or 0) * math.max(0.6, (value or 1)), 0, 100)
            local opiate = (body and body.opiateAmount or 0) + (body and body.analgesia or 0) * 0.5
            if ctx.ply and IsValid(ctx.ply) and ctx.ply.organism then
                opiate = opiate + (ctx.ply.organism.painkiller or 0) * 0.5 + (ctx.ply.organism.analgesia or 0) * 0.5
            end
            if opiate < 1.5 then
                limb.pain = math.max(limb.pain or 0, 30)
                if (limb.pain or 0) < 36 then limb.pain = math.Clamp((limb.pain or 0) + 0.10 * (dt or 0), 0, 100) end
            end
            -- shrapnel drives infection: seed infectionSpeed if skin broken
            if (limb.skin or 100) < 85 and (limb.infectionSpeed or 0) <= 0 then
                if math.random() < 0.004 * (dt or 0) * 60 then limb.infectionSpeed = math.max(limb.infectionSpeed or 0, 0.9) end
            end
            return value
        end,
        onExpire = function(ctx) end
    })
    WoundSystem.Statuses.Register("GLASS_SHARD", {
        title = "Glass Shard",
        desc = "A glass shard is embedded in the limb. Extraction requires tweezers. Pain persists until removed.",
        icon = "casunknown-images/icons/bleeding.png",
        -- icon intentionally reuses existing png per RU: keep all standard png
        type = "number",
        order = 28,
        color = {180, 220, 255},
        tick = function(ctx, value, dt)
            if not ctx or not ctx.limb then return value end
            local limb = ctx.limb
            local body = ctx.body
            -- glass shard: persistent bleed small, pain anchored
            -- pain does NOT passively heal while shard present (RU: glass does not disappear until extraction)
            -- bleed trickle
            limb.bleed = math.Clamp((limb.bleed or 0) + 0.02 * (dt or 0), 0, 100)
            -- pain floor: at least 25 while shard embedded, unless analgesia/painkiller suppresses
            -- painkiller check via body.opiateAmount (C:U) and Z-City organism.painkiller via NW? Use body.opiateAmount + body.analgesia
            -- If player has painkiller, allow pain to be lower
            local opiate = (body and body.opiateAmount or 0) + (body and body.analgesia or 0) * 0.5
            -- Also check Z-City organism painkiller via ply.organism if bridged
            if ctx.ply and IsValid(ctx.ply) and ctx.ply.organism then
                opiate = opiate + (ctx.ply.organism.painkiller or 0) * 0.5 + (ctx.ply.organism.analgesia or 0) * 0.5
            end
            if opiate < 1.5 then
                limb.pain = math.max(limb.pain or 0, 28)
                -- gently push pain up if too low (simulates persistent ache)
                if (limb.pain or 0) < 35 then
                    limb.pain = math.Clamp((limb.pain or 0) + 0.08 * (dt or 0), 0, 100)
                end
            end
            -- glass does not decay automatically; value is shard count (1 per embedding)
            -- return same value to keep it
            return value
        end,
        onExpire = function(ctx)
            -- cleared on successful extraction
        end
    })
end

-- Helper: server-side glass shard embedding via WoundSystem.GlassShard
if SERVER then
    WoundSystem = WoundSystem or {}
    WoundSystem.GlassShard = WoundSystem.GlassShard or {}

    function WoundSystem.GlassShard.AddShard(ply, limbId, count, forceBleed)
        if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false end
        local H = WoundSystem.Health
        if not H then return false end
        local BodyState = H.BodyState or _G.BodyState
        local PlayerLimbs = H.PlayerLimbs or _G.PlayerLimbs
        if not BodyState or not PlayerLimbs then return false end
        local body = BodyState[ply]
        local limbs = PlayerLimbs[ply]
        if not body or not limbs then return false end

        limbId = limbId or "hand_R"
        -- resolve living limb (e.g., if dismembered, go parent)
        if H.Fn and H.Fn.ResolveLivingLimb then
            limbId = H.Fn.ResolveLivingLimb(ply, limbId) or limbId
        end

        local state = limbs[limbId]
        if not state or state.dismembered then return false end

        count = math.Clamp(tonumber(count) or 1, 1, 6)

        if WoundSystem.Statuses and WoundSystem.Statuses.Set then
            local cur = (state.customStatuses and state.customStatuses["GLASS_SHARD"]) or 0
            WoundSystem.Statuses.Set(state, "GLASS_SHARD", cur + count)
        else
            state.glassShards = (state.glassShards or 0) + count
        end

        -- expand damage perception range: make limb more sensitive after glass
        -- bleed and pain per RU: bind to Z-City standard damage
        state.bleed = math.Clamp((state.bleed or 0) + (forceBleed or (8 + count * 4)), 0, 100)
        state.pain = math.Clamp((state.pain or 0) + (18 + count * 12), 0, 100)
        state.skin = math.Clamp((state.skin or 100) - (5 + count * 4), 0, 100)
        if H.Fn and H.Fn.ClearLimbBandage then H.Fn.ClearLimbBandage(state) end

        if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end
        if H.SendCardioUpdate then H.SendCardioUpdate(ply, true) end

        -- notify player
        if ply.Notify then
            ply:Notify(string.format("Glass shard embedded in %s! Use radial menu to extract.", limbId), 1, "glass_shard", 1, nil, Color(180,220,255,255))
        end

        hook.Run("WoundSystem_GlassShardEmbedded", ply, limbId, count)
        return true
    end

    function WoundSystem.GlassShard.HasShard(ply, limbId)
        if not IsValid(ply) then return false end
        local H = WoundSystem.Health
        local PlayerLimbs = H and (H.PlayerLimbs or _G.PlayerLimbs)
        if not PlayerLimbs or not PlayerLimbs[ply] then return false end
        local state = PlayerLimbs[ply][limbId]
        if not state then return false end
        if state.customStatuses and state.customStatuses["GLASS_SHARD"] then
            return (tonumber(state.customStatuses["GLASS_SHARD"]) or 0) > 0
        end
        return (tonumber(state.glassShards) or 0) > 0
    end

    function WoundSystem.GlassShard.RemoveOne(ply, limbId)
        if not IsValid(ply) then return false end
        local H = WoundSystem.Health
        local PlayerLimbs = H and (H.PlayerLimbs or _G.PlayerLimbs)
        if not PlayerLimbs or not PlayerLimbs[ply] then return false end
        local state = PlayerLimbs[ply][limbId]
        if not state then return false end
        local cur = 0
        if state.customStatuses and state.customStatuses["GLASS_SHARD"] then
            cur = tonumber(state.customStatuses["GLASS_SHARD"]) or 0
            cur = cur - 1
            if cur <= 0 then
                WoundSystem.Statuses.Clear(state, "GLASS_SHARD")
                state.glassShards = nil
            else
                WoundSystem.Statuses.Set(state, "GLASS_SHARD", cur)
            end
        else
            cur = (tonumber(state.glassShards) or 1) - 1
            if cur <= 0 then state.glassShards = nil else state.glassShards = cur end
        end
        -- on success, reduce pain a bit but leave wound
        state.pain = math.Clamp((state.pain or 0) - 18, 0, 100)
        state.bleed = math.Clamp((state.bleed or 0) + 6, 0, 100) -- extraction causes brief bleed
        if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end
        hook.Run("WoundSystem_GlassShardRemoved", ply, limbId)
        return true
    end
end
