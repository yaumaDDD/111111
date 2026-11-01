WoundSystem = WoundSystem or {}

WoundSystem.Items.Register("BRUISE KIT", {
    max = 100,
    slot = 1,
    title = "Bruise kit",
    desc = "A combination of drugs and other medicines, made to \naid muscle healing. Increases muscle/skin health and \nhighly aids dislocations. Doesn't affect bleeding.",
    icon = "casunknown-images/items/bruisekit.png",
    pw = 12,
    ph = 20,
    use = {
        minDurability = 10,
        minigame = "bandage",
        bandageMode = "bruise",
        durabilityPerWrap = 10,
        allowUnwounded = true,
        bandage = {
            mode = "bruise",
            color = {50, 255, 70, 255},
            hint = "Press RMB/ESC to exit",
            durabilityPerWrap = 10,
            effectDivisor = 10,
            effects = {
                skinHealAmount = 100,
                muscle = 1,
                pain = -80,
                dislocationTimer = -80
            }
        }
    }
})
