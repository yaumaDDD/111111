WoundSystem = WoundSystem or {}

if WoundSystem.Statuses then
    WoundSystem.Statuses.Register("ARTERIAL_BLEED", {
        title = "Артериальное кровотечение",
        desc = "Разорвана крупная артерия. Кровопотеря очень быстрая, бинт почти не помогает — нужен жгут. Боль сильная.",
        icon = "casunknown-images/icons/extremebleed.png",
        type = "bool",
        order = 29,
        color = {255, 30, 30},
        tick = function(ctx, value, dt)
            if not ctx or not ctx.limb then return value end
            local limb = ctx.limb
            local body = ctx.body
            if not value then return false end
            -- если наложен жгут выше — не кровим (blockedBleeding уже true, но для страховки)
            if limb.blockedBleeding or limb.tourniqueted then return true end
            -- артериальное кровит сильно, даже через бинт; жгут единственный способ остановить
            limb.bleed = math.Clamp((limb.bleed or 0) + 0.35 * (dt or 0) * 10, 0, 100)
            limb.pain = math.max(limb.pain or 0, 45)
            -- пульс ускоряет истекание крови — добавим в CardioLite через bleed, но здесь хотя бы боль
            if body then
                body.adrenaline = math.Clamp((body.adrenaline or 0) + 0.08 * (dt or 0), 0, 100)
            end
            return true
        end,
        onExpire = function(ctx)
            if ctx and ctx.limb then ctx.limb.arterialBleed = nil end
        end
    })
end
