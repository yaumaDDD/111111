WoundSystem = WoundSystem or {}

WoundSystem.Items.Register("PLASTICBANDAGE", {
    max = 100,
    title = "Plastic Dressing",
    desc = "A roll of specially synthesized tough material, made \nto efficiently cover wounds and stabilize fractures. \nHas no effect on muscle health.",
    icon = "casunknown-images/items/plasticbandage.png",
    pw = 18,
    ph = 18,
    use = {
        minDurability = 100 / 12,
        minigame = "bandage",
        bandageMode = "plasticbandage",
        durabilityPerWrap = 100 / 12,
        allowUnwounded = true,
        bandage = {
            mode = "plasticbandage",
            color = {97, 150, 204, 255},
            hint = "Press RMB/ESC to exit",
            durabilityPerWrap = 100 / 12,
            effectDivisor = 12,
            effects = {
                skinHealAmount = 60,
                bandageSlowAmount = 72,
                pain = -100,
                boneHealTimer = -30,
                dislocationTimer = -30
            }
        }
    }
})
