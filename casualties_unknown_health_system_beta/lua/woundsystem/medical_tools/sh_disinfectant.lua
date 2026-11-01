WoundSystem = WoundSystem or {}

WoundSystem.Items.Register("DISINFECTANT", {
    max = 200,
    slot = 2,
    title = "Disinfectant",
    desc = "A 0.2L plastic bottle with a spray nozzle on it. Can \nspray up to 10ml of liquid at a time.",
    icon = "casunknown-images/items/disinfectant.png",
    pw = 12,
    ph = 24,
    use = {
        minDurability = 10,
        durabilityCost = 10,
        apply = SERVER and function(ctx)
            if not ctx.limb then return false end

            ctx.limb.disinfectTime = (ctx.limb.disinfectTime or 0) + 240
            ctx.limb.pain = math.Clamp((ctx.limb.pain or 0) + 10, 0, 100)
            ctx.syncLimb(true)
        end or nil
    }
})
