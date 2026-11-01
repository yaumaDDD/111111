WoundSystem = WoundSystem or {}

WoundSystem.Items.Register("AED", {
    max = 100,
    slot = 5,
    title = "AED",
    desc = "Automated external defibrillator. Place both pads, wait for analysis, then press the shock button if advised.",
    icon = "casunknown-images/items/aed.png",
    pw = 24,
    ph = 24,
    removeOnDepleted = false,
    use = {
        minDurability = 2,
        minigame = "aed",
        validLimbs = "any",
        aed = {
            startCost = 1,
            analyzeCost = 2,
            shockCost = 14,
            analyzeTime = 4.25,
            chargeTime = 3.5,
            padTargetDistance = 150,
            shockChance = 1
        }
    }
})
