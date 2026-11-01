WoundSystem = WoundSystem or {}
WoundSystem.Health = WoundSystem.Health or {}

local ValidFaceExpressions = {
    normal = true,
    tired = true,
    pain = true,
    shock = true,
    panic = true,
    sad = true,
    happy = true,
    unconscious = true,
    dead = true,
    disfigured = true
}

local function SetNWStringIfChanged(ent, key, value)
    if ent:GetNWString(key, "") ~= value then
        ent:SetNWString(key, value)
    end
end

local function SetNWFloatIfChanged(ent, key, value)
    if math.abs(ent:GetNWFloat(key, 0) - value) > 0.01 then
        ent:SetNWFloat(key, value)
    end
end

local function SetNWIntIfChanged(ent, key, value)
    if ent:GetNWInt(key, -1) ~= value then
        ent:SetNWInt(key, value)
    end
end

local function SetNWBoolIfChanged(ent, key, value)
    if ent:GetNWBool(key, false) ~= value then
        ent:SetNWBool(key, value)
    end
end

function WoundSystem.Health.SetFacialExpressionNW(ply, expression, intensity, eyes)
    if not IsValid(ply) then return end

    expression = tostring(expression or "normal")
    if not ValidFaceExpressions[expression] then
        expression = "normal"
    end

    intensity = math.Clamp(tonumber(intensity) or 0, 0, 1)
    eyes = math.Clamp(math.floor(tonumber(eyes) or 2), 0, 2)

    SetNWStringIfChanged(ply, "WoundSystemFaceExpression", expression)
    SetNWFloatIfChanged(ply, "WoundSystemFaceIntensity", intensity)
    SetNWIntIfChanged(ply, "WoundSystemFaceEyes", eyes)
end

function WoundSystem.Health.ResetForcedFacialExpressionNW(ply)
    if not IsValid(ply) then return end

    SetNWBoolIfChanged(ply, "WoundSystemFaceForce", false)
    SetNWStringIfChanged(ply, "WoundSystemFaceForceExpression", "normal")
    SetNWFloatIfChanged(ply, "WoundSystemFaceForceIntensity", 0)
    SetNWIntIfChanged(ply, "WoundSystemFaceForceEyes", 2)
end

function WoundSystem.Health.GetFacialExpressionEyes(body, limbs)
    local head = limbs and limbs.head
    local eyes = head and tonumber(head.eyes)

    if eyes == nil then
        if body and body.bothEyesGone then
            eyes = 0
        elseif body and body.eyeGone then
            eyes = 1
        else
            eyes = 2
        end
    end

    return math.Clamp(math.floor(eyes), 0, 2)
end

function WoundSystem.Health.GetMaxLimbPain(limbs, includeDismembered)
    local maxPain = 0
    if not istable(limbs) then return maxPain end

    for _, limb in pairs(limbs) do
        if istable(limb) and (includeDismembered or not limb.dismembered) then
            maxPain = math.max(maxPain, tonumber(limb.pain) or 0)
        end
    end

    return maxPain
end

function WoundSystem.Health.ApplyCAS3PainResilience(body, rawPain)
    rawPain = math.max(tonumber(rawPain) or 0, 0)

    if WoundSystem.Skills and WoundSystem.Skills.ApplyPainResilience then
        if not istable(body) then return rawPain end
        if not body.skills and WoundSystem.Skills.CreateDefault then
            body.skills = WoundSystem.Skills.CreateDefault()
        end
        return WoundSystem.Skills.ApplyPainResilience(rawPain, body.skills)
    end

    return rawPain
end

function WoundSystem.Health.ComputeCAS3BodyPain(body, limbs)
    if not body or not istable(limbs) then return 0 end

    local rawPain = 0
    local adrenaline = (tonumber(body.curAdrenaline) or tonumber(body.adrenaline) or 0) * 0.5
    for _, state in pairs(limbs) do
        if istable(state) and not state.dismembered then
            rawPain = math.max(rawPain, (tonumber(state.pain) or 0) - adrenaline)
        end
    end

    rawPain = math.max(rawPain, 0)
    return WoundSystem.Health.ApplyCAS3PainResilience(body, rawPain), rawPain, adrenaline
end

function WoundSystem.Health.RecomputeBodyPain(body, limbs)
    if not body or not istable(limbs) then return 0 end

    body.avgPain = WoundSystem.Health.ComputeCAS3BodyPain(body, limbs)
    body.averagePain = body.avgPain

    return body.avgPain
end

function WoundSystem.Health.UpdateFacialExpressionState(ply, body, limbs)
    if not IsValid(ply) or not istable(body) then return end

    local eyes = WoundSystem.Health.GetFacialExpressionEyes(body, limbs)
    local consciousness = tonumber(body.consciousness) or 100
    local pain = math.max(tonumber(body.pain) or 0, WoundSystem.Health.GetMaxLimbPain(limbs))
    local painShock = tonumber(body.painShock) or 0
    local shock = tonumber(body.shock) or 0
    local adrenaline = math.max(tonumber(body.curAdrenaline) or 0, tonumber(body.adrenaline) or 0)
    local bloodVolume = tonumber(body.bloodVolume) or 100
    local bloodOxygen = tonumber(body.bloodOxygen) or 100
    local radiation = tonumber(body.radiationSickness) or 0
    local sickness = tonumber(body.sicknessAmount) or 0
    local temperature = tonumber(body.temperature) or 37
    local happiness = tonumber(body.totalHappiness) or tonumber(body.happiness) or 0
    if WoundSystemHappiness and WoundSystemHappiness.Total then
        happiness = WoundSystemHappiness.Total(ply)
    end
    local totalBleedSpeed = tonumber(body.totalBleedSpeed) or 0
    local badLookAmount = tonumber(body.badLookAmount) or 0
    local specialCrying = (tonumber(body.specialCryingUntil) or 0) > CurTime()
    local velocityZ = ply:GetVelocity().z

    local painScore = math.Clamp(pain / 100, 0, 1)
    local shockScore = math.max(
        math.Clamp(painShock, 0, 1),
        math.Clamp(shock / 100, 0, 1),
        math.Clamp(adrenaline / 100, 0, 1),
        math.Clamp((55 - bloodVolume) / 35, 0, 1),
        math.Clamp((70 - bloodOxygen) / 45, 0, 1),
        math.Clamp((65 - consciousness) / 65, 0, 1)
    )

    local expression = "normal"
    local intensity = 0

    if not ply:Alive() or body.brainDead then
        expression = "dead"
        intensity = 1
    elseif body.disfigured then
        expression = "disfigured"
        intensity = math.Clamp(math.max(0.45, painScore, shockScore * 0.75), 0, 1)
    elseif body.unconscious or consciousness <= 8 then
        expression = "unconscious"
        intensity = 1
    elseif pain > 95 or painShock > 0.82 or velocityZ < -900 then
        expression = "panic"
        intensity = math.Clamp(math.max(painScore, painShock, math.Clamp((-velocityZ - 900) / 700, 0, 1)), 0, 1)
    elseif body.vomiting or badLookAmount > 0 or specialCrying then
        expression = "sad"
        intensity = math.Clamp(math.max(badLookAmount / 8, specialCrying and 0.55 or 0, math.abs(math.min(happiness, 0)) / 100), 0, 1)
    elseif pain >= 70 or happiness < -75 then
        expression = "sad"
        intensity = math.Clamp(math.max((pain - 55) / 45, math.abs(math.min(happiness, 0)) / 100), 0, 1)
    elseif radiation > 80 or body.sleeping or (body.sleepingPillAmount or 0) > 150 then
        expression = "tired"
        intensity = math.Clamp(math.max(radiation / 100, body.sleeping and 1 or 0, math.Clamp(((body.sleepingPillAmount or 0) - 150) / 450, 0, 1)), 0, 1)
    elseif (shock > 21 or adrenaline > 20 or bloodOxygen < 82 or pain > 50 or totalBleedSpeed > 0.1 or velocityZ < -600 or radiation > 60) and not body.mindWipe then
        expression = "shock"
        intensity = math.Clamp(math.max(shockScore, (pain - 35) / 65, totalBleedSpeed * 1.5, math.Clamp((-velocityZ - 600) / 600, 0, 1)), 0, 1)
    elseif consciousness < 70 or pain > 35 or sickness > 40 or temperature < 32 or temperature > 40 or body.mindWipe then
        expression = "tired"
        intensity = math.Clamp(math.max((70 - consciousness) / 70, (pain - 25) / 75, sickness / 100, math.abs(temperature - 37) / 8, body.mindWipe and 0.75 or 0), 0, 1)
    elseif happiness > 50 then
        expression = "happy"
        intensity = math.Clamp((happiness - 50) / 50, 0, 1)
    elseif painScore >= 0.12 then
        expression = "pain"
        intensity = math.Clamp(painScore, 0, 1)
    end

    WoundSystem.Health.SetFacialExpressionNW(ply, expression, intensity, eyes)
end
