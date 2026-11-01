WoundSystem = WoundSystem or {}

if WoundSystem.Statuses then
    WoundSystem.Statuses.Register("SYRINGE_WOUND", {
        title = "Syringe wound",
        desc = "A recent syringe puncture is visible on this limb.",
        icon = "casunknown-images/icons/injectionwound.png",
        type = "bool",
        order = 31
    })
end
