WoundSystem = WoundSystem or {}

if WoundSystem.Statuses then
    WoundSystem.Statuses.Register("INJECTION", {
        title = "Chest drain",
        desc = "A chest drain has been applied to this limb.",
        icon = "casunknown-images/icons/injectionwound.png",
        type = "bool",
        order = 30
    })
end

WoundSystem.Items.Register("INJECTION", {
    max = 10,
    title = "Chest drain",
    desc = "Used to drain fluid from the thorax. Reduces \nhemothorax, reusable after some time. Only usable \non the chest.",
    icon = "casunknown-images/items/chestdrain.png",
    pw = 16,
    ph = 24,
    removeOnDepleted = false,
    use = {
        requireFull = true,
        durabilityCost = 10,
        validLimbs = {"thorax"},
        canUse = SERVER and function(ctx)
            return ctx.limbId == "thorax"
        end or nil,
        apply = SERVER and function(ctx)
            if not ctx.limb then return false end

            ctx.limb.hasInjection = true
            ctx.limb.injectionCharge = 1

            if WoundSystem.Statuses then
                WoundSystem.Statuses.Set(ctx.limb, "INJECTION", true)
            end

            if ctx.body then
                ctx.body.hemothorax = math.Clamp((ctx.body.hemothorax or 0) - 35, 0, 100)
            end

            ctx.limb.bleed = math.Clamp((ctx.limb.bleed or 0) + 2, 0, 100)
            ctx.syncLimb(true)
        end or nil
    }
})

if SERVER then
    local REGEN_SYNC_INTERVAL = 5
    local NextInjectionSync = {}

    timer.Create("WoundSystem_InjectionRegen", 1, 0, function()
        local health = WoundSystem.Health
        if not health or not health.GetInventory then return end

        local syncInventory = health.SyncInventoryToClient
        local maxDur = WoundSystem.Items and WoundSystem.Items.GetMax and WoundSystem.Items.GetMax("INJECTION") or 10
        local now = CurTime()
        for _, ply in ipairs(player.GetAll()) do
            if not IsValid(ply) or not ply:Alive() then continue end

            local inv = health.GetInventory(ply)
            if not inv then continue end

            local changed = false
            local reachedMax = false

            for i = 1, 5 do
                local item = inv[i]
                if item and item.type == "tool" and WoundSystem.NormalizeItemId(item.toolName) == "INJECTION" then
                    local durability = item.durability or maxDur
                    if durability < maxDur then
                        item.durability = math.min(durability + 0.04, maxDur)
                        changed = true
                        reachedMax = reachedMax or item.durability >= maxDur
                    end
                end
            end

            if changed and syncInventory and (reachedMax or (NextInjectionSync[ply] or 0) <= now) then
                syncInventory(ply)
                NextInjectionSync[ply] = now + REGEN_SYNC_INTERVAL
            end
        end
    end)

    hook.Add("PlayerDisconnected", "WoundSystem_InjectionRegenCleanup", function(ply)
        NextInjectionSync[ply] = nil
    end)
end
