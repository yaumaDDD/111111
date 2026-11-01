WoundSystem = WoundSystem or {}

if WoundSystem.Statuses then
    WoundSystem.Statuses.Register("SPLINTED", {
        title = "Splinted",
        desc = "The limb is immobilized. Bone and joint recovery is faster, but limb force is disabled.",
        icon = "casunknown-images/icons/splinticon.png",
        type = "number",
        order = 35,
        tick = function(ctx, value, dt)
            if ctx and ctx.limb then
                ctx.limb.splinted = true
            end

            -- C# SplintLimb.conditionLossMinute = 0.015f; condition is 0..1, ours is 0..100.
            return math.max((tonumber(value) or 0) - ((dt or 0) * 0.025), 0)
        end,
        onExpire = function(ctx)
            if ctx and ctx.limb then
                ctx.limb.splinted = false
            end
        end
    })
end

WoundSystem.Items.Register("SPLINT", {
    max = 100,
    title = "Splint",
    desc = "A rigid brace for broken or dislocated limbs. It \nstabilizes the injury and greatly speeds recovery, but \nthe limb cannot produce force while splinted.",
    icon = "casunknown-images/items/splint.png",
    pw = 24,
    ph = 12,
    use = {
        minDurability = 1,
        validLimbs = {
            "abdomen",
            "arm_R", "forearm_R", "hand_R",
            "arm_L", "forearm_L", "hand_L",
            "thigh_R", "crus_R", "foot_R",
            "thigh_L", "crus_L", "foot_L"
        },
        canUse = SERVER and function(ctx)
            return ctx and ctx.limb ~= nil
        end or nil,
        apply = SERVER and function(ctx)
            if not ctx or not ctx.limb then return false end

            ctx.limb.splinted = true
            ctx.limb.splintSourceSlot = ctx.slotIdx
            ctx.setStatus("SPLINTED", ctx.slot and ctx.slot.durability or 100)
            if ctx.slot then
                ctx.slot.type = "empty"
                ctx.slot.toolName = nil
                ctx.slot.durability = 0
                ctx.slot.pw = nil
                ctx.slot.ph = nil
                ctx.slot.icon = nil
            end
            ctx.syncInventory()
            ctx.syncLimb(true)
            return true
        end or nil
    }
})
