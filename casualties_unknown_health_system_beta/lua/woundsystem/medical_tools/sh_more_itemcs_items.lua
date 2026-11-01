WoundSystem = WoundSystem or {}

local function BodyDoseFromSlot(ctx, perUse)
    return math.Clamp(math.min((ctx.slot and ctx.slot.durability) or 0, perUse) / perUse, 0, 1)
end

local function ApplyCAS3BodyItem(ctx, methodName, perUse)
    if not SERVER or not ctx or not ctx.body then return false end

    local cas3BodyFeel = WoundSystem.Health and WoundSystem.Health.CAS3BodyFeel
    local method = cas3BodyFeel and cas3BodyFeel[methodName]
    if not method then return false end

    return method(ctx.ply, ctx.body, BodyDoseFromSlot(ctx, perUse)) == true
end

WoundSystem.Items.Register("STERILIZEDBANDAGE", {
    max = 100,
    title = "Sterilized dressing",
    desc = "A clean dressing that slows bleeding, supports healing, \nand disinfects the treated limb while wrapped.",
    icon = "casunknown-images/items/sterilizedbandage.png",
    pw = 16,
    ph = 16,
    use = {
        minDurability = 0.01,
        minigame = "bandage",
        bandageMode = "sterilizedbandage",
        durabilityPerWrap = 100 / 12,
        allowUnwounded = true,
        bandage = {
            mode = "sterilizedbandage",
            color = {128, 128, 128, 255},
            hint = "Press RMB/ESC to exit",
            durabilityPerWrap = 100 / 12,
            effectDivisor = 12,
            effects = {
                skinHealAmount = 30,
                bandageSlowAmount = 45,
                pain = -60,
                boneHealTimer = -20,
                dislocationTimer = -20,
                disinfectTime = 900
            },
            bandagedAtBleed = 1,
            bandagedAtSlow = 10
        }
    }
})

WoundSystem.Items.Register("MEDICALSUTURE", {
    max = 100,
    title = "Medical suture",
    desc = "A compact suture kit. Closing a wound hurts, but helps \nskin recovery and reduces bleeding shortly after use.",
    icon = "casunknown-images/items/medicalsuture.png",
    pw = 8,
    ph = 8,
    use = {
        minDurability = 1,
        consumeDurability = 51,
        validLimbs = "any",
        apply = SERVER and function(ctx)
            if not ctx or not ctx.limb then return false end

            ctx.limb.pain = math.Clamp((ctx.limb.pain or 0) + 12.5, 0, 100)
            ctx.limb.skinHealAmount = math.Clamp((ctx.limb.skinHealAmount or 0) + 25, 0, 100)
            timer.Simple(10, function()
                if not ctx or not IsValid(ctx.ply) then return end
                local limb = ctx.limbs and ctx.limbs[ctx.limbId]
                if not limb then return end
                limb.bleed = math.Clamp((limb.bleed or 0) - 4.5, 0, 100)
                if ctx.syncLimb then ctx.syncLimb(true) end
            end)
            ctx.syncLimb(true)
            return true
        end or nil
    }
})

WoundSystem.Items.Register("ALCOHOL", {
    max = 400,
    title = "Alcohol",
    desc = "A bottle of alcohol. It can be used as a rough \nantiseptic, but stings and is not as clean as disinfectant.",
    icon = "casunknown-images/items/alcohol.png",
    pw = 12,
    ph = 24,
    removeOnDepleted = false,
    use = {
        minDurability = 1,
        consumeDurability = 10,
        validLimbs = "any",
        apply = SERVER and function(ctx)
            if not ctx or not ctx.limb then return false end

            local dose = math.Clamp(math.min((ctx.slot and ctx.slot.durability) or 0, 10) / 10, 0, 1)
            ctx.limb.pain = math.Clamp((ctx.limb.pain or 0) + dose, 0, 100)
            ctx.limb.disinfectTime = math.max(ctx.limb.disinfectTime or 0, 35 * dose)
            ctx.syncLimb(true)
            return true
        end or nil
    }
})

WoundSystem.Items.Register("MORPHINE", {
    max = 100,
    title = "Morphine",
    desc = "Injectable opiate analgesic. Less extreme than fentanyl, \nbut still dangerous in high doses.",
    icon = "casunknown-images/items/morphine.png",
    pw = 12,
    ph = 16,
    removeOnDepleted = false,
    use = {
        minDurability = 0.01,
        minigame = "syringe",
        validLimbs = "any",
        syringe = {
            color = {150, 123, 95, 255},
            durabilityPerSecond = 18,
            woundStatus = "SYRINGE_WOUND",
            drugEffects = {
                opiateAmount = 90
            }
        }
    }
})

WoundSystem.Items.Register("NALOXONE", {
    max = 100,
    title = "Naloxone",
    desc = "Injectable opioid antagonist. Counters opiates quickly \nwithout directly treating the wound.",
    icon = "casunknown-images/items/naloxone.png",
    pw = 12,
    ph = 16,
    removeOnDepleted = false,
    use = {
        minDurability = 0.01,
        minigame = "syringe",
        validLimbs = "any",
        syringe = {
            color = {232, 216, 190, 255},
            durabilityPerSecond = 18,
            woundStatus = "SYRINGE_WOUND",
            drugEffects = {
                antagonistAmount = 50
            }
        }
    }
})

WoundSystem.Items.Register("NALTREXONE", {
    max = 100,
    title = "Naltrexone",
    desc = "Oral opioid antagonist. Reduces opioid tolerance and \nadds antagonist effect over time.",
    icon = "casunknown-images/items/naltrexone.png",
    pw = 8,
    ph = 14,
    use = {
        minDurability = 1,
        consumeDurability = 20,
        validLimbs = "body",
        bodyOnly = true,
        apply = SERVER and function(ctx)
            if not ctx or not ctx.body then return false end

            local dose = math.Clamp(math.min((ctx.slot and ctx.slot.durability) or 0, 20) / 20, 0, 1)
            ctx.body.happiness = math.Clamp((ctx.body.happiness or 0) - (2 * dose), -100, 100)
            ctx.body.sicknessAmount = math.Clamp((ctx.body.sicknessAmount or 0) - dose, 0, 100)
            ctx.body.antagonistAmount = math.Clamp((ctx.body.antagonistAmount or 0) + (15 * dose), 0, 1000)
            ctx.body.opiateTolerance = math.max((ctx.body.opiateTolerance or 0) - (15 * dose), 0)
            if SendCardioUpdate then SendCardioUpdate(ctx.ply) end
            return true
        end or nil
    }
})

WoundSystem.Items.Register("ANTIDEPRESSANTS", {
    max = 140,
    title = "Antidepressants",
    desc = "A 140ml pill bottle of antidepressants. Dosage is 20ml.",
    icon = "casunknown-images/items/antidepressants.png",
    pw = 8,
    ph = 14,
    removeOnDepleted = false,
    use = {
        minDurability = 20,
        consumeDurability = 20,
        validLimbs = "body",
        bodyOnly = true,
        apply = SERVER and function(ctx)
            return ApplyCAS3BodyItem(ctx, "ApplyAntidepressants", 20)
        end or nil
    }
})

WoundSystem.Items.Register("SLEEPINGPILLS", {
    max = 25,
    title = "Sleeping pills packet",
    desc = "A blister pack containing 25ml worth of pills. Dosage is 5ml. The brand name is missing.",
    icon = "casunknown-images/items/sleepingpills.png",
    pw = 8,
    ph = 14,
    removeOnDepleted = false,
    use = {
        minDurability = 5,
        consumeDurability = 5,
        validLimbs = "body",
        bodyOnly = true,
        apply = SERVER and function(ctx)
            return ApplyCAS3BodyItem(ctx, "ApplySleepingPills", 5)
        end or nil
    }
})

WoundSystem.Items.Register("ENERGYDRINK", {
    max = 250,
    title = "Energy drink can",
    desc = "A 0.25L soda can with bright markings on it.",
    icon = "casunknown-images/items/energydrink.png",
    pw = 10,
    ph = 16,
    removeOnDepleted = false,
    use = {
        minDurability = 100,
        consumeDurability = 100,
        validLimbs = "body",
        bodyOnly = true,
        apply = SERVER and function(ctx)
            return ApplyCAS3BodyItem(ctx, "ApplyEnergyDrink", 100)
        end or nil
    }
})
