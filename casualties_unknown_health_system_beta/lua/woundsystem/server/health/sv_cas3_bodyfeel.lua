if WoundSystem and WoundSystem.Health and WoundSystem.Health.CAS3BodyFeel and WoundSystem.Health.CAS3BodyFeel._Loaded then
    for _, ply in ipairs(player.GetAll()) do
        timer.Remove("WoundSystem_CAS3Vomit_" .. ply:EntIndex())
    end
end

WoundSystem = WoundSystem or {}
WoundSystem.Health = WoundSystem.Health or {}
WoundSystem.Health.CAS3BodyFeel = WoundSystem.Health.CAS3BodyFeel or {}

local CAS3 = WoundSystem.Health.CAS3BodyFeel
CAS3._Loaded = true

local VOMIT_THRESHOLD = 60
local VOMIT_WINDUP = 5

local TemperatureMovementKeys = {
    {20, 0.60},
    {30, 0.79},
    {33, 1.00},
    {40.7, 1.00},
    {45, 0.50},
    {52.232174, 0.275}
}

local WeightMovementKeys = {
    {-80, 0.65},
    {-60, 0.75},
    {-40, 0.95},
    {0, 1.00},
    {30, 0.90},
    {60, 0.72},
    {100, 0.45}
}

local function Enabled()
    if WoundSystemHealthEnabled then
        return WoundSystemHealthEnabled()
    end

    local config = WoundSystem and WoundSystem.Health and WoundSystem.Health.Config
    if config and config.IsEnabled then
        return config.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

local function Clamp01(value)
    return math.Clamp(tonumber(value) or 0, 0, 1)
end

local function Curve(keys, value, fallback)
    value = tonumber(value) or 0
    if not keys or #keys == 0 then return fallback or 1 end

    if value <= keys[1][1] then return keys[1][2] end

    for i = 2, #keys do
        local prev = keys[i - 1]
        local nextKey = keys[i]
        if value <= nextKey[1] then
            local span = math.max(nextKey[1] - prev[1], 0.001)
            return Lerp(math.Clamp((value - prev[1]) / span, 0, 1), prev[2], nextKey[2])
        end
    end

    return keys[#keys][2]
end

local function StaminaStrength(value)
    value = Clamp01(value)
    return math.Clamp(1 - math.pow(1 - value, 3.05), 0, 1)
end

local function AddClamped(body, key, amount, minValue, maxValue, fallback)
    if not body then return end
    body[key] = math.Clamp((tonumber(body[key]) or fallback or 0) + (tonumber(amount) or 0), minValue, maxValue)
end

local function PlayPillSound(ply)
    if not IsValid(ply) then return end
    ply:EmitSound("pills.ogg", 58, math.random(96, 103), 0.8)
end

local function GetBody(ply)
    return WoundSystem
        and WoundSystem.Health
        and WoundSystem.Health.GetBody
        and WoundSystem.Health.GetBody(ply)
        or nil
end

local function MouthOrigin(ply, body)
    local source = WoundSystem.GetCurrentCharacter and WoundSystem.GetCurrentCharacter(ply) or (body and IsValid(body.unconsciousRagdoll) and body.unconsciousRagdoll or ply)
    if not IsValid(source) then return nil, nil, nil end

    local bone = source.LookupBone and source:LookupBone("ValveBiped.Bip01_Head1") or nil
    if bone and source.GetBonePosition then
        local pos, ang = source:GetBonePosition(bone)
        if pos and ang then
            return pos + ang:Forward() * 7 - ang:Up() * 2, ang:Forward(), source
        end
    end

    if source.EyePos and source.EyeAngles then
        local ang = source:EyeAngles()
        return source:EyePos() + ang:Forward() * 8 - ang:Up() * 3, ang:Forward(), source
    end

    return source:WorldSpaceCenter(), source:GetForward(), source
end

local function SendVomitWarning(ply, body)
    if not IsValid(ply) or (body.consciousness or 100) <= 20 then return end
    if not net or not net.Start then return end

    net.Start("WoundSystem_VomitWarning")
    net.Send(ply)
end

function CAS3.InitBodyFields(body)
    if not body then return end

    if body.vomitTime == nil then body.vomitTime = 0 end
    if body.vomiting == nil then body.vomiting = false end
    if body.vomitPower == nil then body.vomitPower = 0 end
    if body.badLookAmount == nil then body.badLookAmount = 0 end
    if body.antidepressantAmount == nil then body.antidepressantAmount = 0 end
    if body.antidepressantCurrentAmount == nil then body.antidepressantCurrentAmount = 0 end
    if body.sleepingPillAmount == nil then body.sleepingPillAmount = 0 end
    if body.sleepingPillWasSleeping == nil then body.sleepingPillWasSleeping = false end
    if body.specialCryingUntil == nil then body.specialCryingUntil = 0 end
    if body.stimulantMultiplier == nil then body.stimulantMultiplier = 0 end
end

function CAS3.ResetBodyFields(body)
    if not body then return end

    body.vomitTime = 0
    body.vomiting = false
    body.vomitPower = 0
    body.badLookAmount = 0
    body.antidepressantAmount = 0
    body.antidepressantCurrentAmount = 0
    body.sleepingPillAmount = 0
    body.sleepingPillWasSleeping = false
    body.specialCryingUntil = 0
    body.stimulantMultiplier = 0
end

function CAS3.GetStaminaRegenScale(body)
    if not body then return 1 end

    local over = math.Clamp(tonumber(body.overEncumberance) or 0, 0, 1)
    local caffeine = math.Clamp((tonumber(body.caffeinated) or 0) / 400, 0, 1)
    local stimulant = math.Clamp(tonumber(body.stimulantMultiplier) or 0, 0, 0.35)
    return math.Clamp((1 - over * 0.55) * (1 + caffeine + stimulant), 0.25, 2.35)
end

function CAS3.GetStaminaDrainScale(body)
    if not body then return 1 end

    local weight = math.max(tonumber(body.weightOffset) or 0, 0)
    local over = math.Clamp(tonumber(body.overEncumberance) or 0, 0, 1)
    local stimulant = math.Clamp(tonumber(body.stimulantMultiplier) or 0, 0, 0.35)
    return math.Clamp(1 + over * 0.8 + weight * 0.006 - stimulant * 0.35, 0.65, 2)
end

function CAS3.GetMovementMultipliers(ply, body, limbs, limbForceEnabled)
    if not body then return 1, 1 end

    CAS3.InitBodyFields(body)

    local limbMult = 1
    local limbForce = WoundSystem.Health and WoundSystem.Health.LimbForce
    if limbForceEnabled ~= false and limbForce and limbForce.GetLegMovementMultiplier then
        limbMult = math.Clamp(limbForce.GetLegMovementMultiplier(ply) or 1, 0.05, 1)
    end

    local consciousnessMult = StaminaStrength((body.consciousness or 100) * 0.01)
    local staminaMult = StaminaStrength((body.stamina or 100) * 0.01)
    local tempMult = Curve(TemperatureMovementKeys, body.temperature or 37, 1)
    local weightMult = Curve(WeightMovementKeys, body.weightOffset or 0, 1)
    local temporaryMult = math.Clamp(1 - (tonumber(body.temporarySlowdown) or 0), 0.05, 1)
    local over = math.Clamp(tonumber(body.overEncumberance) or 0, 0, 1)
    local overMult = math.Clamp(1 - over * over, 0.1, 1)
    local stimulant = math.Clamp(tonumber(body.stimulantMultiplier) or 0, 0, 0.35)

    if body.onHardStimulants then
        stimulant = math.max(stimulant, 0.18)
    end

    local speedMult = math.min(limbMult, consciousnessMult, staminaMult, tempMult, weightMult, temporaryMult)
    speedMult = math.Clamp(speedMult * overMult * (1 + stimulant), 0.05, 1.25)

    local totalHappiness = tonumber(body.totalHappiness) or tonumber(body.happiness) or 0
    local forceMult = math.Clamp(totalHappiness * 0.01 + 1.2, 0, 1)

    return speedMult, forceMult
end

function CAS3.DropHeldThings(ply, reason)
    if not IsValid(ply) or not ply:Alive() then return false end

    local health = WoundSystem and WoundSystem.Health
    if health and health.CancelActiveMedicalSessions then
        health.CancelActiveMedicalSessions(ply, reason or "interrupted")
    end

    if health and health.DropRecoverableActiveWeapon then
        return health.DropRecoverableActiveWeapon(ply)
    end

    return false
end

function CAS3.TriggerVomit(ply, body, power)
    if not Enabled() then return false end
    if not IsValid(ply) or not ply:Alive() or not body then return false end

    CAS3.InitBodyFields(body)
    body.vomitPower = math.max(tonumber(body.vomitPower) or 0, tonumber(power) or 0)

    if body.vomiting then return true end

    body.vomiting = true
    body.vomitTime = 0
    body.badLookAmount = math.max(body.badLookAmount or 0, 0.5)
    body.specialCryingUntil = math.max(body.specialCryingUntil or 0, CurTime() + VOMIT_WINDUP + 2)
    ply.WoundSystemCAS3VomitFinishAt = CurTime() + VOMIT_WINDUP

    SendVomitWarning(ply, body)

    timer.Create("WoundSystem_CAS3Vomit_" .. ply:EntIndex(), VOMIT_WINDUP, 1, function()
        if not Enabled() then return end
        if not IsValid(ply) or not ply:Alive() then return end

        local currentBody = GetBody(ply)
        if currentBody ~= body or not currentBody or not currentBody.vomiting then return end
        CAS3.FinishVomit(ply, currentBody)
    end)

    return true
end

function CAS3.FinishVomit(ply, body)
    if not Enabled() then return false end
    if not IsValid(ply) or not ply:Alive() or not body then return false end

    CAS3.InitBodyFields(body)

    local power = math.Clamp(tonumber(body.vomitPower) or 0, 0, 4)
    body.vomiting = false
    body.vomitPower = 0
    body.vomitTime = 0
    body.temporarySlowdown = math.max(body.temporarySlowdown or 0, 0.95)
    body.badLookAmount = math.max(body.badLookAmount or 0, 7 + power * 2)
    body.specialCryingUntil = math.max(body.specialCryingUntil or 0, CurTime() + 4)

    CAS3.DropHeldThings(ply, "vomit")

    local pos, forward, source = MouthOrigin(ply, body)
    if pos and WoundSystem.BloodEffects and WoundSystem.BloodEffects.Emit then
        WoundSystem.BloodEffects.Emit(pos, forward, math.Clamp(1.15 + power * 0.35, 0.8, 3), "vomit", nil, source)
    end

    source = IsValid(source) and source or ply
    source:EmitSound(math.random(1, 2) == 1 and "vomit1.ogg" or "vomit2a.ogg", 70, 100, 0.9)

    AddClamped(body, "happiness", -2.5, -100, 100, 0)
    AddClamped(body, "sicknessAmount", -(8 + power * 5), 0, 100, 0)
    AddClamped(body, "bloodVolume", -1, -100, 200, 100)
    if power > 0 then
        AddClamped(body, "internalBleeding", power * 10, 0, 100, 0)
    end

    if body.sleeping and (body.sleepingPillAmount or 0) <= 0 then
        body.sleeping = false
    end

    if WoundSystem.TalkerSayLine then
        WoundSystem.TalkerSayLine(ply, "vomit", nil, true)
    end

    if SendCardioUpdate then
        SendCardioUpdate(ply)
    end

    return true
end

function CAS3.ApplyConsciousnessEffects(ply, body, dt)
    if not body then return end
    if not body.vomiting then return end

    local finishAt = IsValid(ply) and (ply.WoundSystemCAS3VomitFinishAt or 0) or 0
    local elapsed = math.Clamp(VOMIT_WINDUP - math.max(finishAt - CurTime(), 0), 0, VOMIT_WINDUP)
    body.temporarySlowdown = math.max(body.temporarySlowdown or 0, math.Clamp(elapsed * 0.15, 0, 0.95))
    body.badLookAmount = math.max(body.badLookAmount or 0, elapsed * 0.4)
    body.consciousness = math.min(body.consciousness or 100, math.max(0, 100 - elapsed * 13.5))
end

function CAS3.ApplyAntidepressants(ply, body, doseFraction)
    if not Enabled() or not body then return false end

    doseFraction = math.Clamp(tonumber(doseFraction) or 0, 0, 1)
    AddClamped(body, "antidepressantAmount", 100 * doseFraction, 0, 1000, 0)
    AddClamped(body, "happiness", 1 * doseFraction, -100, 100, 0)
    if math.Rand(0, 1) < (0.3 * doseFraction) then
        AddClamped(body, "sicknessAmount", 30 * doseFraction, 0, 100, 0)
    end

    PlayPillSound(ply)
    if SendCardioUpdate then SendCardioUpdate(ply) end
    return true
end

function CAS3.ApplySleepingPills(ply, body, doseFraction)
    if not Enabled() or not body then return false end

    doseFraction = math.Clamp(tonumber(doseFraction) or 0, 0, 1)
    AddClamped(body, "sleepingPillAmount", 300 * doseFraction, 0, 999999, 0)
    PlayPillSound(ply)
    if SendCardioUpdate then SendCardioUpdate(ply) end
    return true
end

function CAS3.ApplyEnergyDrink(ply, body, doseFraction)
    if not Enabled() or not body then return false end

    doseFraction = math.Clamp(tonumber(doseFraction) or 0, 0, 1)
    AddClamped(body, "stamina", 25 * doseFraction, 0, 100, 100)
    AddClamped(body, "sicknessAmount", 20 * doseFraction, 0, 100, 0)
    AddClamped(body, "happiness", 2.5 * doseFraction, -100, 100, 0)
    AddClamped(body, "weightOffset", 0.4 * doseFraction, -80, 100, 0)
    AddClamped(body, "caffeinated", 400 * doseFraction, 0, 999999, 0)
    if SendCardioUpdate then SendCardioUpdate(ply) end
    return true
end

local function TickAntidepressants(body, dt)
    body.antidepressantCurrentAmount = math.Approach(tonumber(body.antidepressantCurrentAmount) or 0, tonumber(body.antidepressantAmount) or 0, dt * 5)
    body.antidepressantAmount = math.max((tonumber(body.antidepressantAmount) or 0) - dt * 0.185, 0)

    local current = tonumber(body.antidepressantCurrentAmount) or 0
    body.antidepressantHappiness = math.Clamp((0 - (body.happiness or 0)) * 0.6 * Clamp01(current * 0.0166), -100, 100)
    body.happiness = math.Clamp((body.happiness or 0) + current * 0.00003 * dt, -100, 100)

    if current >= 250 then
        body.overdoseIndex = math.max(body.overdoseIndex or 0, 2)
        body.bloodPressure = math.max(0, (body.bloodPressure or 120) - dt * 3)
    end
end

local function TickSleepingPills(body, dt, actualOpiateReception)
    body.sleepingPillAmount = math.max(tonumber(body.sleepingPillAmount) or 0, 0)

    if body.sleepingPillAmount <= 0 then
        body.sleepingPillWasSleeping = false
        return
    end

    if body.sleeping then
        body.sleepingPillWasSleeping = true
    elseif body.sleepingPillWasSleeping then
        body.sleepingPillAmount = body.sleepingPillAmount * 0.75
        body.sleepingPillWasSleeping = false
    end

    body.sleepingPillAmount = math.max(body.sleepingPillAmount - dt, 0)

    if body.sleepingPillAmount > 900 or ((actualOpiateReception or 0) > 15 and body.sleepingPillAmount > 150) then
        body.overdoseIndex = math.max(body.overdoseIndex or 0, 2)
        body.bloodPressure = math.max(0, (body.bloodPressure or 120) - dt * 2.5)

        local rr = body.respiratoryRate or 100
        if rr > 70 then body.respiratoryRate = math.Approach(rr, 70, dt * 15) end

        if body.unconscious then
            body.bloodPressure = math.max(0, (body.bloodPressure or 120) - dt * 2.5)
            if (body.heartRate or 70) > 30 then body.heartRate = math.Approach(body.heartRate or 70, 30, dt) end
            rr = body.respiratoryRate or 100
            if rr > 40 then body.respiratoryRate = math.Approach(rr, 40, dt * 15) end
        end
    end
end

local function TickStimulants(body, dt)
    body.caffeinated = math.max((tonumber(body.caffeinated) or 0) - dt, 0)
    local caffeineStim = math.Clamp((body.caffeinated or 0) / 4000, 0, 0.16)
    local hardStim = body.onHardStimulants and 0.25 or 0
    body.stimulantMultiplier = math.Clamp(math.max(caffeineStim, hardStim), 0, 0.35)
end

local function TickVomit(ply, body, dt, actualOpiateReception)
    if body.vomiting then return end

    local sickness = math.Clamp(body.sicknessAmount or 0, 0, 100)
    if sickness > 0 then
        local rate = sickness > 50 and sickness * 0.01 or sickness * 0.0025
        body.vomitTime = (body.vomitTime or 0) + dt * rate
    end

    if (actualOpiateReception or 0) < -0.5 then
        body.vomitTime = (body.vomitTime or 0) + math.Clamp(-actualOpiateReception, 0, 25) * dt * 0.02
    end

    if (body.vomitTime or 0) > VOMIT_THRESHOLD then
        local power = math.Clamp(((body.vomitTime or 0) - VOMIT_THRESHOLD) / 40, 0, 2)
        CAS3.TriggerVomit(ply, body, power)
    end
end

function CAS3.TickBody(ply, body, limbs, dt, actualOpiateReception)
    if not Enabled() or not IsValid(ply) or not ply:Alive() or not body then return end

    CAS3.InitBodyFields(body)
    TickAntidepressants(body, dt)
    TickSleepingPills(body, dt, actualOpiateReception)
    TickStimulants(body, dt)
    TickVomit(ply, body, dt, actualOpiateReception)

    body.badLookAmount = math.Approach(body.badLookAmount or 0, body.vomiting and (body.badLookAmount or 0) or 0, dt * 0.8)
    if (body.specialCryingUntil or 0) < CurTime() and not body.vomiting then
        body.specialCryingUntil = 0
    end
end

function CAS3.RunBrainSymptomExtras(ply, body, brainHealth, rollFn)
    if not Enabled() then return end
    if not IsValid(ply) or not ply:Alive() or not body or body.unconscious or body.brainDead then return end

    brainHealth = math.Clamp(brainHealth or body.brainHealth or 100, 0, 100)
    rollFn = isfunction(rollFn) and rollFn or function(value, multiplier)
        return math.Rand(0, 1) > (math.Clamp(value or 100, 0, 100) * 0.01 * (multiplier or 1))
    end

    if rollFn(brainHealth, 1) and math.Rand(0, 1) < 0.75 then
        ply:SetNWFloat("WoundSystemBrainShakeUntil", math.max(ply:GetNWFloat("WoundSystemBrainShakeUntil", 0), CurTime() + 2.25))
        if WoundSystem.TalkerSayLine then
            WoundSystem.TalkerSayLine(ply, "hitbycreature", nil, true)
        end
    end

    if rollFn(brainHealth, 1) and math.Rand(0, 1) < 0.06 then
        CAS3.TriggerVomit(ply, body, 0.25)
    end

    if rollFn(brainHealth, 1) then
        CAS3.DropHeldThings(ply, "brain")
        body.specialCryingUntil = math.max(body.specialCryingUntil or 0, CurTime() + 2)
        if WoundSystem.TalkerSayLine then
            WoundSystem.TalkerSayLine(ply, "braindamaged", nil, true)
        end
    end
end
