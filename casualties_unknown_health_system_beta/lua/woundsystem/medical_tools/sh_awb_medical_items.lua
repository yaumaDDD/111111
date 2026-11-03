WoundSystem = WoundSystem or {}

local function ClampAdd(target, key, amount, minValue, maxValue, fallback)
    if not target then return end
    target[key] = math.Clamp((target[key] or fallback or 0) + amount, minValue, maxValue)
end

local function DoseFromSlot(ctx, perUse)
    return math.Clamp(math.min((ctx.slot and ctx.slot.durability) or 0, perUse) / perUse, 0, 1)
end

local function SyncBody(ctx)
    if SERVER and ctx and ctx.ply and SendCardioUpdate then
        SendCardioUpdate(ctx.ply)
    end
end

local function QueueTimedBodyEffect(ctx, id, duration, data)
    if not SERVER or not ctx or not ctx.body then return false end
    if WoundSystem.Health and WoundSystem.Health.QueueTimedBodyEffect then
        return WoundSystem.Health.QueueTimedBodyEffect(ctx.ply, ctx.body, id, duration, data)
    end
    return false
end

local function AddSyringeIV(ctx, bloodVolume, viscosity, thirst)
    if not ctx or not ctx.body then return false end

    local dose = math.Clamp(tonumber(ctx.syringeFraction) or 0, 0, 1)
    ClampAdd(ctx.body, "bloodVolume", bloodVolume * dose, -100, 200, 100)
    ClampAdd(ctx.body, "bloodViscosity", viscosity * dose, -100, 150, 0)
    ClampAdd(ctx.body, "thirst", thirst * dose, -50, 250, 80)
    SyncBody(ctx)
    return true
end

local function splintLimbs()
    return {
        "abdomen",
        "arm_R", "forearm_R", "hand_R",
        "arm_L", "forearm_L", "hand_L",
        "thigh_R", "crus_R", "foot_R",
        "thigh_L", "crus_L", "foot_L"
    }
end

WoundSystem.Items.Register("RIPPEDDRESSING", {
    max = 100,
    title = "Ripped dressing",
    desc = "A small pile of ripped clothing. Can be used as a \nmakeshift bandage for bleeding wounds.",
    icon = "casunknown-images/items/rippeddressing.png",
    pw = 16,
    ph = 16,
    use = {
        minDurability = 0.01,
        minigame = "bandage",
        bandage = {
            mode = "rippeddressing",
            color = {230, 230, 230, 255},
            durabilityPerWrap = 100 / 8,
            effectDivisor = 8,
            effects = {
                skinHealAmount = 8,
                bandageSlowAmount = 18,
                pain = -40,
                boneHealTimer = -5,
                dislocationTimer = -5
            },
            bandagedAtBleed = 1,
            bandagedAtSlow = 10
        }
    }
})

WoundSystem.Items.Register("RAG", {
    max = 100,
    title = "Old rag",
    desc = "A worn, crumpled up rag. Can be used as decent \nmakeshift dressing. Use in the inventory to dry yourself.",
    icon = "casunknown-images/items/rag.png",
    pw = 20,
    ph = 14,
    use = {
        minDurability = 0.01,
        minigame = "bandage",
        bandage = {
            mode = "rag",
            color = {143, 126, 139, 255},
            durabilityPerWrap = 100 / 8,
            effectDivisor = 8,
            effects = {
                skinHealAmount = 8,
                bandageSlowAmount = 10,
                pain = -25,
                boneHealTimer = -5,
                dislocationTimer = -5
            },
            bandagedAtBleed = 1,
            bandagedAtSlow = 10
        }
    }
})

WoundSystem.Items.Register("ANALGESICGAUZE", {
    max = 100,
    title = "Medical gauze",
    desc = "Woven gauze made of cotton, containing analgesic drugs. \nDecent at slowing bleeding and reducing pain from injuries.",
    icon = "casunknown-images/items/analgesicgauze.png",
    pw = 20,
    ph = 14,
    use = {
        minDurability = 0.01,
        minigame = "bandage",
        bandage = {
            mode = "analgesicgauze",
            color = {158, 167, 194, 255},
            durabilityPerWrap = 100 / 15,
            effectDivisor = 15,
            effects = {
                skinHealAmount = 20,
                bandageSlowAmount = 50,
                pain = -300
            },
            applyWrap = SERVER and function(ctx)
                if not ctx or not ctx.body then return end
                local dose = math.Clamp((tonumber(ctx.wrapFraction) or 0) / 15, 0, 1)
                ClampAdd(ctx.body, "opiateAmount", 28 * dose, 0, 1000, 0)
                SyncBody(ctx)
            end or nil,
            bandagedAtBleed = 1,
            bandagedAtSlow = 10
        }
    }
})

WoundSystem.Items.Register("ADHESIVEBANDAGE", {
    max = 100,
    title = "Adhesive bandages",
    desc = "A pack of small medical dressings, made to treat small \ninjuries. Lowers bleeding.",
    icon = "casunknown-images/items/adhesivebandage.png",
    pw = 14,
    ph = 14,
    use = {
        minDurability = 16,
        consumeDurability = 16,
        validLimbs = "any",
        apply = SERVER and function(ctx)
            if not ctx or not ctx.limb then return false end
            local dose = DoseFromSlot(ctx, 16)
            ClampAdd(ctx.limb, "skinHealAmount", 3 * dose, 0, 100, 0)
            ClampAdd(ctx.limb, "bandageSlowAmount", 6 * dose, 0, 100, 0)
            ctx.limb.pain = math.Clamp((ctx.limb.pain or 0) * Lerp(dose, 1, 0.9), 0, 100)
            ctx.syncLimb(true)
            return true
        end or nil
    }
})

WoundSystem.Items.Register("PAINCREAM", {
    max = 100,
    title = "Relief cream bottle",
    desc = "A small 100ml bottle used to hold relief cream. Dosage \nis 10ml.",
    icon = "casunknown-images/items/paincream.png",
    pw = 12,
    ph = 20,
    removeOnDepleted = false,
    use = {
        minDurability = 10,
        consumeDurability = 10,
        validLimbs = "any",
        apply = SERVER and function(ctx)
            if not ctx or not ctx.limb then return false end
            local dose = DoseFromSlot(ctx, 10)
            ClampAdd(ctx.limb, "skinHealAmount", 3 * dose, 0, 100, 0)
            QueueTimedBodyEffect(ctx, "reliefcream:" .. tostring(ctx.limbId or ""), 15 * dose, {
                kind = "reliefcream",
                limbId = ctx.limbId
            })
            ctx.limb.disinfectTime = math.max(ctx.limb.disinfectTime or 0, 300 * dose)
            ctx.syncLimb(true)
            return true
        end or nil
    }
})

WoundSystem.Items.Register("WOUNDGLUE", {
    max = 80,
    title = "Wound glue",
    desc = "A 80ml tube, usually filled with wound glue. Applies \n20ml of liquid per use.",
    icon = "casunknown-images/items/woundglue.png",
    pw = 8,
    ph = 24,
    removeOnDepleted = false,
    use = {
        minDurability = 20,
        consumeDurability = 20,
        validLimbs = "any",
        apply = SERVER and function(ctx)
            if not ctx or not ctx.limb or not ctx.body then return false end
            local dose = DoseFromSlot(ctx, 20)
            ClampAdd(ctx.limb, "skinHealAmount", 10 * dose, 0, 100, 0)
            ClampAdd(ctx.limb, "muscle", 5 * dose, 0, 100, 100)
            ClampAdd(ctx.limb, "bandageSlowAmount", 30 * dose, 0, 100, 0)
            ClampAdd(ctx.limb, "infection", -5 * dose, 0, 100, 0)
            ctx.limb.disinfectTime = math.max(ctx.limb.disinfectTime or 0, 300 * dose)
            ctx.limb.pain = math.Clamp((ctx.limb.pain or 0) * (0.9 * math.Clamp(dose, 0, 1)), 0, 100)
            ClampAdd(ctx.body, "bloodViscosity", 15 * dose, -100, 150, 0)
            ClampAdd(ctx.body, "sicknessAmount", 2.5 * dose, 0, 100, 0)
            ctx.syncLimb(true)
            SyncBody(ctx)
            return true
        end or nil
    }
})

WoundSystem.Items.Register("CARCASSSPLINT", {
    max = 100,
    title = "Carcass splint",
    desc = "A hard, long tube made from multiple joined carcasses. \nFunctions as a decent makeshift splint for treating fractures.",
    icon = "casunknown-images/items/carcasssplint.png",
    pw = 20,
    ph = 32,
    use = {
        minDurability = 1,
        validLimbs = splintLimbs(),
        canUse = SERVER and function(ctx)
            return ctx and ctx.limb ~= nil and not ctx.limb.splinted
        end or nil,
        apply = SERVER and function(ctx)
            if not ctx or not ctx.limb then return false end
            ctx.limb.splinted = true
            ctx.limb.splintSourceSlot = ctx.slotIdx
            ctx.limb.splintItemId = "CARCASSSPLINT"
            ctx.setStatus("SPLINTED", (ctx.slot and ctx.slot.durability or 100) * (0.015 / 0.036))
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

WoundSystem.Items.Register("SALINE", {
    max = 750,
    title = "IV bag",
    desc = "A 0.75L bag with a needle at the end, for injecting \nfluids intravenously.",
    icon = "casunknown-images/items/saline.png",
    pw = 16,
    ph = 32,
    removeOnDepleted = false,
    use = {
        minDurability = 0.01,
        minigame = "syringe",
        validLimbs = "any",
        syringe = {
            color = {196, 196, 196, 255},
            durabilityPerSecond = 80,
            woundStatus = "SYRINGE_WOUND",
            applyUse = SERVER and function(ctx)
                return AddSyringeIV(ctx, 40, -50, 70)
            end or nil
        }
    }
})

WoundSystem.Items.Register("RINGERSOLUTION", {
    max = 700,
    title = "Small IV bag",
    desc = "A 0.7L bag with a needle at the end, for injecting \nfluids intravenously.",
    icon = "casunknown-images/items/ringersolution.png",
    pw = 16,
    ph = 32,
    removeOnDepleted = false,
    use = {
        minDurability = 0.01,
        minigame = "syringe",
        validLimbs = "any",
        syringe = {
            color = {237, 237, 237, 255},
            durabilityPerSecond = 80,
            woundStatus = "SYRINGE_WOUND",
            applyUse = SERVER and function(ctx)
                return AddSyringeIV(ctx, 35, -40, 60)
            end or nil
        }
    }
})

WoundSystem.Items.Register("BLOODCOAGULANT", {
    max = 100,
    title = "Procoagulant syringe",
    desc = "A 100ml syringe with an auto-injector at the end. \nDosage is ~34mL.",
    icon = "casunknown-images/items/bloodcoagulant.png",
    pw = 12,
    ph = 16,
    removeOnDepleted = false,
    use = {
        minDurability = 33.334,
        consumeDurability = 33.334,
        validLimbs = "any",
        apply = SERVER and function(ctx)
            if not ctx or not ctx.body then return false end
            local dose = DoseFromSlot(ctx, 33.334)
            if not QueueTimedBodyEffect(ctx, "procoagulant", 20 * dose, {kind = "procoagulant"}) then
                ctx.body.internalBleeding = math.Clamp((ctx.body.internalBleeding or 0) * Lerp(dose, 1, 0.95), 0, 100)
                ClampAdd(ctx.body, "bloodViscosity", 1.75 * dose, -100, 150, 0)
                ClampAdd(ctx.body, "strokeAmount", -10 * dose, 0, 100, 0)
                for _, limb in pairs(ctx.limbs or {}) do
                    if type(limb) == "table" then
                        limb.bleed = math.Clamp((limb.bleed or 0) * Lerp(dose, 1, 0.96), 0, 100)
                    end
                end
            end
            SyncBody(ctx)
            return true
        end or nil
    }
})

WoundSystem.Items.Register("STREPTOKINASE", {
    max = 100,
    title = "Streptokinase syringe",
    desc = "A 100ml syringe with an auto-injector at the end. \nDosage is ~34mL.",
    icon = "casunknown-images/items/streptokinase.png",
    pw = 12,
    ph = 16,
    removeOnDepleted = false,
    use = {
        minDurability = 33.334,
        consumeDurability = 33.334,
        validLimbs = "any",
        apply = SERVER and function(ctx)
            if not ctx or not ctx.body then return false end
            local dose = DoseFromSlot(ctx, 33.334)
            ClampAdd(ctx.body, "bloodViscosity", -50 * dose, -100, 150, 0)
            ClampAdd(ctx.body, "sicknessAmount", 5 * dose, 0, 100, 0)
            SyncBody(ctx)
            return true
        end or nil
    }
})

WoundSystem.Items.Register("CEFTRIAXONE", {
    max = 100,
    title = "Ceftriaxone syringe",
    desc = "A 100ml syringe that can inject fluid intravenously. \nThis one has a small bottle next to it to draw from.",
    icon = "casunknown-images/items/ceftriaxone.png",
    pw = 12,
    ph = 16,
    removeOnDepleted = false,
    use = {
        minDurability = 0.01,
        minigame = "syringe",
        validLimbs = "any",
        syringe = {
            color = {70, 207, 48, 255},
            durabilityPerSecond = 18,
            woundStatus = "SYRINGE_WOUND",
            effects = {
                pain = 80
            },
            applyUse = SERVER and function(ctx)
                if not ctx or not ctx.body then return false end
                local dose = math.Clamp(tonumber(ctx.syringeFraction) or 0, 0, 1)
                ctx.body.antibioticImmunityTime = math.max((ctx.body.antibioticImmunityTime or 0) + (1125 * dose), 0)
                SyncBody(ctx)
                return true
            end or nil
        }
    }
})

WoundSystem.Items.Register("ANTIBIOTICS", {
    max = 100,
    title = "Antibiotics bottle",
    desc = "A 100ml pill bottle of antibiotic pills. Dosage is 20ml.",
    icon = "casunknown-images/items/antibiotics.png",
    pw = 8,
    ph = 14,
    removeOnDepleted = false,
    use = {
        minDurability = 20,
        consumeDurability = 20,
        validLimbs = "body",
        bodyOnly = true,
        apply = SERVER and function(ctx)
            if not ctx or not ctx.body then return false end
            local dose = math.Clamp(math.min((ctx.slot and ctx.slot.durability) or 0, 20) * 0.1, 0, 2)
            ClampAdd(ctx.body, "happiness", -0.5 * dose, -100, 100, 0)
            ClampAdd(ctx.body, "septicShock", -2.5 * dose, 0, 100, 0)
            ctx.body.antibioticImmunityTime = math.max((ctx.body.antibioticImmunityTime or 0) + (250 * dose), 0)
            SyncBody(ctx)
            return true
        end or nil
    }
})

WoundSystem.Items.Register("OPIUM", {
    max = 100,
    title = "Opium syringe",
    desc = "A 100ml syringe that can inject fluid intravenously. \nThe overdose label says 200ml.",
    icon = "casunknown-images/items/opium.png",
    pw = 10,
    ph = 16,
    removeOnDepleted = false,
    use = {
        minDurability = 0.01,
        minigame = "syringe",
        validLimbs = "any",
        syringe = {
            color = {255, 235, 81, 255},
            durabilityPerSecond = 18,
            woundStatus = "SYRINGE_WOUND",
            drugEffects = {
                opiateAmount = 40
            }
        }
    }
})

WoundSystem.Items.Register("HEROIN", {
    max = 150,
    title = "Heroin syringe",
    desc = "A 150ml syringe that can inject fluid intravenously. \nThis one is missing the graduation marks and dosage guides.",
    icon = "casunknown-images/items/heroin.png",
    pw = 8,
    ph = 24,
    removeOnDepleted = false,
    use = {
        minDurability = 0.01,
        minigame = "syringe",
        validLimbs = "any",
        syringe = {
            color = {235, 235, 235, 255},
            durabilityPerSecond = 18,
            woundStatus = "SYRINGE_WOUND",
            drugEffects = {
                opiateAmount = 130
            },
            bodyEffects = {
                sicknessAmount = 50
            }
        }
    }
})

WoundSystem.Items.Register("WRENCH", {
    max = 100,
    title = "Wrench",
    desc = "A tool used to provide grip and mechanical advantage in \napplying torque to turn objects. Can be used on dislocated limbs.",
    icon = "casunknown-images/items/wrench.png",
    pw = 10,
    ph = 24,
    use = {
        minDurability = 0.01,
        minigame = "dislocation",
        validLimbs = "any",
        wrench = true
    }
})

WoundSystem.Items.Register("TWEEZERS", {
    max = 100,
    title = "Tweezers",
    desc = "A simple pair of metal tweezers. Can cleanly and \npainlessly remove shrapnel from limbs.",
    icon = "casunknown-images/items/tweezers.png",
    pw = 16,
    ph = 10,
    use = {
        minDurability = 1,
        minigame = "shrapnel",
        validLimbs = "any",
        tweezers = true
    }
})
