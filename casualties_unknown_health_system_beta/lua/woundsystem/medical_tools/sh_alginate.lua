WoundSystem = WoundSystem or {}

WoundSystem.Items.Register("ALGINATE", {
    max = 100,
    title = "Alginate dressing",
    desc = "A hemostatic wound dressing for heavy bleeding. It \nclots faster than standard gauze but does little for \nfractures or dislocations.",
    icon = "casunknown-images/items/alginate.png",
    pw = 20,
    ph = 20,
    use = {
        minDurability = 100 / 15,
        minigame = "bandage",
        bandageMode = "alginate",
        requireBleed = false,
        allowUnwounded = true,
        bandage = {
            mode = "alginate",
            allowUnwounded = true,
            color = {220, 235, 225, 255},
            hint = "Press RMB/ESC to exit",
            durabilityPerWrap = 100 / 15,
            effectDivisor = 15,
            requireBleed = false,
            effects = {
                skinHealAmount = 125,
                bandageSlowAmount = 72.5,
                pain = -80,
                disinfectTime = 800
            },
            bandagedAtBleed = 2,
            bandagedAtSlow = 20
        }
    }
})
