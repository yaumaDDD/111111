WoundSystem = WoundSystem or {}

WoundSystem.Items.Register("GAUZE", {
    max = 100,
    slot = 3,
    title = "Dressing",
    desc = "A roll of dressing with a bandage, used to slow down \nbleeding, stabilize fractures and aid skin healing. Has \nno effect on muscle health.",
    icon = "casunknown-images/items/gauze.png",
    pw = 16,
    ph = 16,
    use = {
        minDurability = 0.01,
        minigame = "bandage",
        durabilityPerWrap = 100 / 12,
        requireBleed = false,
        allowUnwounded = true,
        bandage = {
            mode = "gauze",
            color = {255, 255, 255, 255},
            hint = "Press RMB/ESC to exit",
            durabilityPerWrap = 100 / 12,
            effectDivisor = 12,
            effects = {
                bandageSlowAmount = 45,
                skinHealAmount = 30,
                pain = -60,
                boneHealTimer = -20,
                dislocationTimer = -20
            },
            bandagedAtBleed = 1,
            bandagedAtSlow = 10
        }
    }
})
