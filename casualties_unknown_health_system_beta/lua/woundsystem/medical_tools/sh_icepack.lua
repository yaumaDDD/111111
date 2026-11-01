WoundSystem = WoundSystem or {}

if WoundSystem.Statuses then
    WoundSystem.Statuses.Register("CHILLED", {
        title = "Chilled",
        desc = "Cold dulls pain and doubles natural muscle recovery, but does not affect bleeding.",
        icon = "casunknown-images/icons/chilled.png",
        type = "timer",
        duration = 150,
        order = 45,
        tick = function(ctx, value, dt)
            if ctx and ctx.limb then
                ctx.limb.chilled = true
                -- C# ChilledLimb.Update: pain -= dt * 1.5f
                ctx.limb.pain = math.max((ctx.limb.pain or 0) - (1.5 * (dt or 0)), 0)
                -- Approximation of C# ChilledLimb.Update extra muscle recovery.
                ctx.limb.muscle = math.min((ctx.limb.muscle or 0) + (0.16 * (dt or 0)), 100)
            end
            return value
        end,
        onExpire = function(ctx)
            if ctx and ctx.limb then
                ctx.limb.chilled = false
            end
        end
    })
end

WoundSystem.Items.Register("ICE PACK", {
    max = 100,
    title = "Ice pack",
    desc = "A disposable cold pack. Chills a limb to dull pain and boost muscle \nrecovery. Does not stop bleeding. Slowly recharges over time.",
    icon = "casunknown-images/items/icepack.png",
    pw = 20,
    ph = 24,
    removeOnDepleted = false,
    use = {
        -- C#: if (item.condition >= 0.5f) { item.condition -= 0.5f; ... }
        -- durabilityCost 50 = half of 100 max, matching condition -= 0.5f on a 0-1 scale
        durabilityCost = 50,
        validLimbs = "any",
        canUse = function(ctx)
            if not ctx or not ctx.limb then return false end
            -- Must have at least 50 durability remaining (mirrors the >= 0.5f gate)
            local slot = ctx.slot
            return slot and (slot.durability or 0) >= 50
        end,
        apply = function(ctx)
            if not ctx or not ctx.limb then return false end

            if SERVER then
                -- C#: limb.body.temperature -= 1f
                if ctx.body then
                    ctx.body.temperature = (ctx.body.temperature or 37) - 1
                end
                -- C#: GetOrAddComponent<ChilledLimb>().timeLeft = 150f (refreshes if already applied)
                ctx.setStatus("CHILLED", 150)
                ctx.syncLimb(true)
            end
            return true
        end
    }
})

if SERVER then
    local REGEN_SYNC_INTERVAL = 5
    local NextIcePackSync = {}

    timer.Create("WoundSystem_IcePackRegen", 1, 0, function()
        local health = WoundSystem.Health
        if not health or not health.GetInventory then return end

        local syncInventory = health.SyncInventoryToClient
        local maxDur = WoundSystem.Items and WoundSystem.Items.GetMax and WoundSystem.Items.GetMax("ICE PACK") or 100
        local now = CurTime()
        for _, ply in ipairs(player.GetAll()) do
            if not IsValid(ply) or not ply:Alive() then continue end

            local inv = health.GetInventory(ply)
            local changed = false
            local reachedMax = false

            for i = 1, 5 do
                local item = inv and inv[i]
                if item and item.type == "tool" and WoundSystem.NormalizeItemId(item.toolName) == "ICE PACK" and (item.durability or 0) < maxDur then
                    item.durability = math.min((item.durability or 0) + 0.9, maxDur)
                    changed = true
                    reachedMax = reachedMax or item.durability >= maxDur
                end
            end

            if changed and syncInventory and (reachedMax or (NextIcePackSync[ply] or 0) <= now) then
                syncInventory(ply)
                NextIcePackSync[ply] = now + REGEN_SYNC_INTERVAL
            end
        end
    end)

    hook.Add("PlayerDisconnected", "WoundSystem_IcePackRegenCleanup", function(ply)
        NextIcePackSync[ply] = nil
    end)
end
