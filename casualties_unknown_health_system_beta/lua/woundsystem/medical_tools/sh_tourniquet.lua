WoundSystem = WoundSystem or {}

if WoundSystem.Statuses then
    WoundSystem.Statuses.Register("TOURNIQUET", {
        title = "Tourniquet",
        desc = "Bleeding is fully blocked below a tight strap. Pain rises while it remains applied.",
        icon = "casunknown-images/icons/tourniquetIcon.png",
        type = "number",
        order = 30,
        color = {255, 255, 255},
        -- Propagate tourniquet effects to downstream (lower) limbs and increment pain on the applied limb
        tick = function(ctx, value, dt)
                value = (tonumber(value) or 0) + (dt or 0)

                -- Local lower-limb mapping (matches server-side LowerLimbs)
                local LowerLimbs = {
                    ["thigh_R"]   = {"thigh_R", "crus_R", "foot_R"},
                    ["crus_R"]    = {"crus_R", "foot_R"},
                    ["foot_R"]    = {"foot_R"},
                    ["thigh_L"]   = {"thigh_L", "crus_L", "foot_L"},
                    ["crus_L"]    = {"crus_L", "foot_L"},
                    ["foot_L"]    = {"foot_L"},
                    ["arm_R"]     = {"arm_R", "forearm_R", "hand_R"},
                    ["forearm_R"] = {"forearm_R", "hand_R"},
                    ["hand_R"]    = {"hand_R"},
                    ["arm_L"]     = {"arm_L", "forearm_L", "hand_L"},
                    ["forearm_L"] = {"forearm_L", "hand_L"},
                    ["hand_L"]    = {"hand_L"},
                }

                if ctx and (ctx.limb or ctx.limbId) then
                    local srcId = ctx.limbId or (ctx.limb and ctx.limb.id) or (ctx.limb and ctx.limb.limbId)
                    local names = LowerLimbs[srcId] or { srcId }

                    for _, nm in ipairs(names) do
                        local l = (ctx.limbs and ctx.limbs[nm]) or nil
                        if not l and ctx.limb and (ctx.limb.limbId == nm or ctx.limb.id == nm) then
                            l = ctx.limb
                        end
                        if l then
                            l.blockedBleeding = true
                            -- Mark tourniqueted flag only on the applied limb
                            if nm == srcId then
                                l.tourniqueted = true
                                l.tourniquetPain = math.Clamp((l.tourniquetPain or 0) + (2 * (dt or 0)), 0, 40)
                                l.pain = math.max(l.pain or 0, l.tourniquetPain)
                            end
                            if value >= 540 then
                                l.muscle = math.Clamp((l.muscle or 100) - (2 * (dt or 0)), 0, 100)
                                if (l.muscle or 100) < 5 then
                                    if (l.infection or 0) <= 0 and (l.infectionSpeed or 0) <= 0 then
                                        l.infection = 10
                                        l.infectionSpeed = 1
                                    end
                                end
                            end
                        end
                    end
                end

                return value
            end,
        onExpire = function(ctx)
            if not ctx then return end
            local srcId = ctx.limbId or (ctx.limb and ctx.limb.id) or (ctx.limb and ctx.limb.limbId)
            local names = {
                ["thigh_R"]   = {"thigh_R", "crus_R", "foot_R"},
                ["crus_R"]    = {"crus_R", "foot_R"},
                ["foot_R"]    = {"foot_R"},
                ["thigh_L"]   = {"thigh_L", "crus_L", "foot_L"},
                ["crus_L"]    = {"crus_L", "foot_L"},
                ["foot_L"]    = {"foot_L"},
                ["arm_R"]     = {"arm_R", "forearm_R", "hand_R"},
                ["forearm_R"] = {"forearm_R", "hand_R"},
                ["hand_R"]    = {"hand_R"},
                ["arm_L"]     = {"arm_L", "forearm_L", "hand_L"},
                ["forearm_L"] = {"forearm_L", "hand_L"},
                ["hand_L"]    = {"hand_L"},
            }
            local list = names[srcId] or { srcId }
            for _, nm in ipairs(list) do
                local l = (ctx.limbs and ctx.limbs[nm]) or nil
                if not l and ctx.limb and (ctx.limb.limbId == nm or ctx.limb.id == nm) then
                    l = ctx.limb
                end
                if l then
                    l.tourniqueted = false
                    l.tourniquetPain = 0
                    l.tourniquetDurability = nil
                    l.blockedBleeding = false
                end
            end
        end
    })
end

WoundSystem.Items.Register("TOURNIQUET", {
    max = 100,
    title = "Tourniquet",
    desc = "A tight strap for catastrophic limb bleeding. It blocks \nbleeding completely for a while, but causes mounting \npain and should not be used on the head or torso.",
    icon = "casunknown-images/items/tourniquet.png",
    pw = 16,
    ph = 16,
    use = {
        minDurability = 12.5,
        validLimbs = {
            "arm_R", "forearm_R", "hand_R",
            "arm_L", "forearm_L", "hand_L",
            "thigh_R", "crus_R", "foot_R",
            "thigh_L", "crus_L", "foot_L"
        },
        canUse = function(ctx)
            return ctx and ctx.limb ~= nil
        end,
        apply = function(ctx)
            if not ctx or not ctx.limb then return false end

            if SERVER then
                local attachedDurability = math.max(((ctx.slot and ctx.slot.durability) or 100) - 12.5, 0.01)
                ctx.limb.tourniqueted = true
                ctx.limb.blockedBleeding = true
                ctx.limb.tourniquetDurability = attachedDurability
                ctx.limb.tourniquetSourceSlot = ctx.slotIdx
                ctx.limb.pain = math.Clamp((ctx.limb.pain or 0) + 12, 0, 100)
                ctx.setStatus("TOURNIQUET", 0.01)
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
            end
            return true
        end
    }
})
