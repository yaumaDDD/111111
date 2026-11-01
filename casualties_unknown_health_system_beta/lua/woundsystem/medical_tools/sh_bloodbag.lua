WoundSystem = WoundSystem or {}

WoundSystem.Items.Register("BLOOD BAG", {
    max = 100,
    title = "Blood bag",
    desc = "Sterile donor blood for emergency transfusion. Restores \nblood volume and slightly improves circulation. Best \nused before pressure collapse becomes fatal.",
    icon = "casunknown-images/items/bloodbag.png",
    pw = 24,
    ph = 32,
    removeOnDepleted = true,
    use = {
        minDurability = 1,
        durabilityCost = 0,
        consumeDurability = 50,
        validLimbs = "any",
        canUse = function(ctx)
            return ctx and ctx.body ~= nil and ctx.slot and (ctx.slot.durability or 0) > 0
        end,
        apply = function(ctx)
            if not ctx or not ctx.body then return false end

            if SERVER then
                local maxDur = WoundSystem.Items and WoundSystem.Items.GetMax and WoundSystem.Items.GetMax("BLOOD BAG") or 100
                local consumedDurability = math.min((ctx.slot and ctx.slot.durability) or 0, 50)
                local liters = math.Clamp(consumedDurability / math.max(maxDur, 1), 0, 1)

                -- 100 durability = 1 liter, so the effect scales by the amount transfused.
                ctx.body.bloodVolume = math.Clamp((ctx.body.bloodVolume or 100) + (45 * liters), -100, 200)
                ctx.body.bloodPressure = math.Clamp((ctx.body.bloodPressure or 120) + (8 * liters), 0, 250)
                ctx.body.cardioShock = math.Clamp((ctx.body.cardioShock or 0) - (12 * liters), 0, 100)
                ctx.body.shock = math.Clamp((ctx.body.shock or 0) - (12 * liters), 0, 100)
                ctx.body.bloodViscosity = math.Clamp((ctx.body.bloodViscosity or 0) + (4 * liters), -100, 150)

                -- Keep clients informed of blood amount if supported
                if IsValid(ctx.ply) and ctx.ply.SetNWFloat then
                    ctx.ply:SetNWFloat("BloodAmount", ctx.body.bloodVolume)
                end

                -- Small safety: if transfusion brings volume above a healthy threshold, slightly boost oxygen
                if ctx.body.bloodVolume and ctx.body.bloodVolume > 120 then
                    ctx.body.bloodOxygen = math.Clamp((ctx.body.bloodOxygen or 90) + (5 * liters), 0, 100)
                end

                if SendCardioUpdate then
                    SendCardioUpdate(ctx.ply)
                end
            end

            return true
        end
    }
})
