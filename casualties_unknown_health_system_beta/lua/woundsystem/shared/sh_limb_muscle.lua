WoundSystem = WoundSystem or {}

local LimbMuscle = WoundSystem.LimbMuscle or {}
WoundSystem.LimbMuscle = LimbMuscle

-- Casualties: Unknown reference values (~0.10126/s base, ~0.0172/s below 10 muscle)
LimbMuscle.HEAL_RATE_NORMAL = 0.10126
LimbMuscle.HEAL_RATE_LOW = 0.0172
LimbMuscle.LOW_MUSCLE_THRESHOLD = 10
LimbMuscle.MUSCLE_DEATH_THRESHOLD = 5
LimbMuscle.INFECTION_MUSCLE_DECAY_RATE = 0.2
LimbMuscle.HYPOXIA_MUSCLE_DECAY_RATE = 0.6
LimbMuscle.ABDOMEN_FAILURE_BLEED_RATE = 0.2
LimbMuscle.FRACTURE_MUSCLE_CAP = 50

LimbMuscle.LimbRoles = {
    head = { isHead = true },
    thorax = { isVital = true },
    abdomen = { isAbdomen = true }
}

function LimbMuscle.GetRoles(limbName)
    return LimbMuscle.LimbRoles[limbName] or {}
end

function LimbMuscle.IsInfected(state)
    if not state then return false end
    return (state.infection or 0) > 0 or (state.infectionSpeed or 0) > 0
end

function LimbMuscle.GetHealRatePerSecond(muscleHealth)
    muscleHealth = tonumber(muscleHealth) or 0
    if muscleHealth < LimbMuscle.LOW_MUSCLE_THRESHOLD then
        return LimbMuscle.HEAL_RATE_LOW
    end
    return LimbMuscle.HEAL_RATE_NORMAL
end

-- C#: (!infected || isHead) && body.hunger > 0, plus shrapnel blocks regen
function LimbMuscle.CanRegenerateMuscle(state, limbName, body)
    if not state then return false end
    
    local muscle = state.muscle or 100
    local roles = LimbMuscle.GetRoles(limbName)
    local hasShrapnel = (state.shrapnel or 0) > 0
    if hasShrapnel then
        if not roles.isHead or muscle > 14.28571 then
            return false
        end
    end

    local hunger = body and body.hunger
    if hunger == nil then hunger = 100 end
    if hunger <= 0 then return false end

    local infected = LimbMuscle.IsInfected(state)
    if infected and not roles.isHead then return false end

    return true
end

-- Recreates the C# Limb.Update() muscleHealth block only.
-- Returns updated state and optional body side-effects for the server cardio layer.
function LimbMuscle.Tick(state, limbName, body, dt, healingRateMult)
    if not state then return state, {} end

    dt = tonumber(dt) or 0
    healingRateMult = tonumber(healingRateMult) or 1

    local muscle = state.muscle or 100
    local infectionAmount = state.infection or 0
    local roles = LimbMuscle.GetRoles(limbName)
    local bodyEffects = {}

    local infected = infectionAmount > 0 or (state.infectionSpeed or 0) > 0

    if infected and infectionAmount > 75 then
        muscle = muscle - (LimbMuscle.INFECTION_MUSCLE_DECAY_RATE * dt)
    elseif (not infected or roles.isHead) and (body and (body.hunger or 100) > 0) then
        local sleeping = body and (body.sleeping or body.unconscious)
        local sleepingMult = sleeping and 1.4 or 1.0
        local lowMuscleFactor = (muscle > 10 or roles.isHead) and 1.0 or 0.25
        
        local hasShrapnel = (state.shrapnel or 0) > 0
        local shrapnelFactor = 1.0
        if hasShrapnel then
            if not roles.isHead or muscle > 14.28571 then
                shrapnelFactor = 0.0
            end
        end

        local hungerHealCurrent = body and body.hungerLimbHealCurrent or (math.max((body and body.hunger or 100) * 0.01, 0))
        
        -- C# MuscleHealRate: dt * 0.08 * sleepingMult * lowMuscleFactor * shrapnelFactor * hungerHealCurrent * healingRateMult
        local muscleHealRate = dt * 0.08 * sleepingMult * lowMuscleFactor * shrapnelFactor * hungerHealCurrent * healingRateMult
        muscle = muscle + muscleHealRate
    end

    if muscle <= LimbMuscle.MUSCLE_DEATH_THRESHOLD then
        if roles.isVital then
            bodyEffects.zeroRespiratory = true
        end
        if roles.isAbdomen then
            bodyEffects.internalBleeding = LimbMuscle.ABDOMEN_FAILURE_BLEED_RATE * dt
        end
    end

    if (state.broken or state.dislocated) and muscle > LimbMuscle.FRACTURE_MUSCLE_CAP then
        muscle = LimbMuscle.FRACTURE_MUSCLE_CAP
    end

    muscle = math.Clamp(muscle, 0, 100)

    if body then
        if (body.bloodOxygen or 100) <= 5 or (body.bloodPressure or 120) < 20 then
            muscle = muscle - (LimbMuscle.HYPOXIA_MUSCLE_DECAY_RATE * dt)
            muscle = math.Clamp(muscle, 0, 100)
        end
    end

    state.muscle = muscle
    return state, bodyEffects
end

function LimbMuscle.GetMuscleHealth(limbId, limbsTable)
    limbsTable = limbsTable or (WoundSystemClientState and WoundSystemClientState.PlayerLimbs)
    local state = limbsTable and limbsTable[limbId]
    return state and state.muscle or nil
end

function LimbMuscle.GetAllMuscleHealth(limbsTable)
    limbsTable = limbsTable or (WoundSystemClientState and WoundSystemClientState.PlayerLimbs)
    if not limbsTable then return {} end

    local out = {}
    for limbId, state in pairs(limbsTable) do
        if state then
            out[limbId] = state.muscle or 0
        end
    end
    return out
end

-- Convenience aliases for GUI / other addons
WoundSystem.GetLimbMuscleHealth = LimbMuscle.GetMuscleHealth
WoundSystem.GetAllLimbMuscleHealth = LimbMuscle.GetAllMuscleHealth
