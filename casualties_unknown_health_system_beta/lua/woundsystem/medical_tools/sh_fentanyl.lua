WoundSystem = WoundSystem or {}

WoundSystem.Items.Register("FENTANYL", {
    max = 100,
    title = "Fentanyl",
    desc = "A compact injectable analgesic. Drag the syringe down \nand keep it steady while injecting. Strongly reduces \npain, but can lower consciousness and breathing.",
    icon = "casunknown-images/items/fentanyl.png",
    pw = 8,
    ph = 14,
	removeOnDepleted = false,
    use = {
        minDurability = 0.01,
        minigame = "syringe",
        validLimbs = "any",
        syringe = {
            color = {0, 132, 173, 255},
            durabilityPerSecond = 18,
            woundStatus = "SYRINGE_WOUND",
            minigame = {
                -- Sim-space syringe/tissue positions. Lower Y pushes farther into the skin.
                syringeStartX = 0,
                syringeStartY = -150,
                skinY = -180,
                stopY = -273,

                -- Sprite scale/pivot. Pivot is normalized sprite space: 0.5, 1 = bottom center/tip.
                syringeScale = 2,
                syringePivotX = 0.5,
                syringePivotY = 1,
                syringeDrawOffsetY = -680,
                fillOffsetX = 5,
                fillOffsetY = 33,

                -- Background/front layer placement.
                frontLayerY = 300,
                boardOffsetY = 600,

                -- Hand/arm placement and rotation.
                handPivotX = 0.4,
                handPivotY = 0.1,
                handOffsetX = 40,
                handOffsetY = 0,
                handIdleAngle = 290,
                handHoldAngle = 290,

                -- Needle wobble and break tuning.
                breakSideForce = 80,
                rotationDirection = -1,
                rotationPerSideForce = 0.125,
                maxRotation = 20
            },
            drugEffects = {
                -- The source item is 100 units total: 90 water + 10 fentanyl.
                -- Injecting the full syringe adds 10 opiate units; the shared
                -- opiate tick handles pain relief, mood, tolerance, and sedation.
                opiateAmount = 420
            }
        }
    }
})
