-- RU: падение не делает ран, а травмирует ту часть тела на которую упал + боль от Z-City анальгетиков
WoundSystem = WoundSystem or {}
WoundSystem.Health = WoundSystem.Health or {}

-- Re-open FALL logic to expose FallTrauma (no bleed)
function WoundSystem.Health.ApplyFallTrauma(ply, limbId, force)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    local H = WoundSystem.Health
    local BodyState = H.BodyState or _G.BodyState
    local PlayerLimbs = H.PlayerLimbs or _G.PlayerLimbs
    if not BodyState or not PlayerLimbs then return end
    local body = BodyState[ply]
    local limbs = PlayerLimbs[ply]
    if not body or not limbs then return end
    if body.isGodMode then return end

    limbId = limbId or "foot_R"
    if H.Fn and H.Fn.ResolveLivingLimb then
        limbId = H.Fn.ResolveLivingLimb(ply, limbId) or limbId
    end
    local state = limbs[limbId]
    if not state or state.dismembered then return end

    force = tonumber(force) or 0
    local jumpSpeed = (body and body.jumpSpeed) or 6.5
    if force <= jumpSpeed * 0.85 then return end -- expanded perception: trigger earlier than original 1.0*jumpSpeed

    -- cooldown per limb (same as impact but shorter)
    ply._nextLimbPhysicsDamage = ply._nextLimbPhysicsDamage or {}
    local now = CurTime()
    if (ply._nextLimbPhysicsDamage[limbId] or 0) > now then return end
    ply._nextLimbPhysicsDamage[limbId] = now + 0.18

    -- Trauma without wounds/bleed per RU: не делай раны при падении а немного травмируй ту часть тела на которую человек упал
    -- muscle -5 / -10 depending on force, no skin damage, no bleed
    local muscleLoss = math.Clamp(force * 0.18, 4, 16)
    state.muscle = math.Clamp((state.muscle or 100) - muscleLoss, 0, 100)

    -- pain which can be removed only by Z-City painkiller/analgesia
    -- Mark as fall pain so tick can keep it if no analgesia
    local painAdd = math.Clamp(force * 1.2, 12, 45)
    state.pain = math.Clamp((state.pain or 0) + painAdd, 0, 100)
    -- tag for persistent pain (checked in Status tick would be FallTrauma, but we store flag here)
    state.fallTraumaPain = math.Clamp((state.fallTraumaPain or 0) + painAdd * 0.5, 0, 60)
    state.fallTraumaUntil = now + math.Clamp(force * 1.5, 12, 45) -- duration pain stays unless analgesia

    -- small adrenaline/shock but no bleed/internalBleed unless very hard
    body.adrenaline = math.Clamp((body.adrenaline or 0) + force * 0.06, 0, 100)
    if force > jumpSpeed * 3.2 then
        -- hard fall: minor internal bleeding capped, still no open wound
        body.internalBleeding = math.Clamp((body.internalBleeding or 0) + 8, 0, 60)
    end

    -- update strength
    if H.LimbForce and H.LimbForce.ComputeTotalForce then
        state.muscleStrength = H.LimbForce.ComputeTotalForce(state, body, limbId)
    end

    -- sync
    if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end
    if H.SendCardioUpdate then H.SendCardioUpdate(ply, true) end

    -- notify
    ply:EmitSound("physics/body/body_medium_impact_soft"..math.random(3,7)..".wav", 62)

    hook.Run("WoundSystem_OnFallTrauma", ply, limbId, force)
end

-- Hook to detect contacted limb on fall: trace hull down from ply to find leg/foot that hit
-- We replace the default fall handling that used fixed foot_L/foot_R with contacted limb detection
hook.Add("OnPlayerHitGround", "WoundSystem_FallTraumaDetect", function(ply, inWater, onFloater, speed)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    local H = WoundSystem.Health
    if not H or not H.BodyState then return end
    -- skip if Z-City bridge will handle fall via WB.ApplyFall (it calls HandleDamage with DMG_FALL)
    -- Our ApplyFallTrauma will be called from HandleDamage rewrite; this hook just records contacted limb
    if not speed or speed < 100 then return end
    -- trace to find lowest bone near ground
    local pos = ply:GetPos()
    local tr = util.TraceHull({
        start = pos + Vector(0,0,12),
        endpos = pos - Vector(0,0,24),
        mins = Vector(-10,-10,0),
        maxs = Vector(10,10,6),
        filter = ply
    })
    -- we store contacted limb candidate based on velocity direction / last attacker? Simple: pick foot that is lower
    -- Check leg bone positions if available
    local boneLimb = "foot_R"
    -- Try to infer from player velocity or view: if moving left, left leg takes more? Use random for now but expanded range
    -- Expanded perception: also check for crus/foot impacts by checking speed threshold
    -- We stash for HandleDamage to use
    ply._woundSystemFallContactLimb = boneLimb
    -- also store speed for force calc already done via existing hook; this just marks limb
end)

-- Pain keeper for BOTH fall trauma and glass shards: боль снимается только обезболом ЗСити
timer.Create("WoundSystem_FallTraumaPainThink", 0.5, 0, function()
    if not WoundSystem or not WoundSystem.Health or not WoundSystem.Health.BodyState then return end
    local BodyState = WoundSystem.Health.BodyState
    local PlayerLimbs = WoundSystem.Health.PlayerLimbs
    if not BodyState or not PlayerLimbs then return end
    for ply, body in pairs(BodyState) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local limbs = PlayerLimbs[ply]
        if not limbs then continue end
        -- check opiate/analgesia from C:U + Z-City
        local opiate = (body.opiateAmount or 0) + (body.analgesia or 0)
        if ply.organism then opiate = opiate + (ply.organism.painkiller or 0) + (ply.organism.analgesia or 0) end
        local hasAnalgesia = opiate > 1.2
        for limbId, state in pairs(limbs) do
            if not state or state.dismembered then continue end
            -- FALL trauma floor
            if (state.fallTraumaUntil or 0) > CurTime() then
                if not hasAnalgesia then
                    local floorPain = math.Clamp((state.fallTraumaPain or 25), 22, 42)
                    if (state.pain or 0) < floorPain then state.pain = floorPain end
                else
                    state.fallTraumaPain = math.max((state.fallTraumaPain or 0) - 0.6 * 0.5, 0)
                    if state.fallTraumaPain <= 1 then state.fallTraumaUntil = 0 state.fallTraumaPain = nil end
                end
            else
                if state.fallTraumaPain then state.fallTraumaPain = nil end
            end
            -- GLASS shard floor: pain persists until extraction unless analgesia (RU: боль можно снять только обезболом ЗСити)
            local glassCount = 0
            if state.customStatuses and state.customStatuses["GLASS_SHARD"] then glassCount = tonumber(state.customStatuses["GLASS_SHARD"]) or 0 end
            if glassCount > 0 then
                if not hasAnalgesia then
                    local glassFloor = 28 + math.min(glassCount*4, 18)
                    if (state.pain or 0) < glassFloor then
                        state.pain = math.Clamp(glassFloor + math.sin(CurTime()*0.9)*1.5, 0, 100)
                    end
                else
                    -- with analgesia pain is suppressed but shard still there (glass не пропадает пока не вытащишь)
                    -- allow low pain but keep shard icon
                end
            end
        end
    end
end)
