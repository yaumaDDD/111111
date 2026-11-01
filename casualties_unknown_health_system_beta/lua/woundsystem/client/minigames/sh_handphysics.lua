-- Shared hand physics to mimic C# MinigameBase behavior
local HandPhysics = {}

HandPhysics.PHYSICS_RATE = 60

local function Lerp(a, b, t)
    return a + (b - a) * math.Clamp(t, 0, 1)
end

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

-- simple pseudo-noise using sines (stable across clients)
local function simpleNoise(t, a, b)
    return (math.sin(t * a) + math.sin(t * b + 2.3)) * 0.5
end

-- Ensure fields exist on mg
function HandPhysics.Init(mg)
    mg.handPos = mg.handPos or { x = 0, y = 0 }
    mg.handVelocity = mg.handVelocity or { x = 0, y = 0 }
    mg.handScreenX = mg.handScreenX or (ScrW() * 0.5)
    mg.handScreenY = mg.handScreenY or (ScrH() * 0.5)
    mg.handScreenVelX = mg.handScreenVelX or 0
    mg.handScreenVelY = mg.handScreenVelY or 0
    mg._hp_acc = mg._hp_acc or 0
end

-- opts: table with optional fields: pain (0..1), str (0..10), conc (0..100),
-- bounds: {minX, maxX, minY, maxY} (optional, defaults to full screen)
-- windowHalfSize: optional clamp radius for sim-space mapping (not used here)
function HandPhysics.Step(mg, dt, opts)
    opts = opts or {}
    HandPhysics.Init(mg)

    local pain = math.Clamp(tonumber(opts.pain) or 0, 0, 1)
    local str = tonumber(opts.str) or 0
    local conc = tonumber(opts.conc) or 100

    local num = 1 / HandPhysics.PHYSICS_RATE
    mg._hp_acc = math.min((mg._hp_acc or 0) + dt * HandPhysics.PHYSICS_RATE, HandPhysics.PHYSICS_RATE * 0.25)

    local bounds = opts.bounds or { 0, ScrW(), 0, ScrH() }

    while mg._hp_acc >= 1 do
        -- target mouse pos
        local mx, my = gui.MousePos()
        if mx <= 0 and my <= 0 then mx, my = ScrW() * 0.5, ScrH() * 0.5 end

        -- shake from pain (pseudo Perlin)
        local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
        local t = CurTime()
        local shakeX = simpleNoise(t, 2.9, 2.7) - 0.5
        local shakeY = simpleNoise(t, 2.86, 2.2) - 0.5
        local shakeScaleX = (pain) * ((opts.shakeX or 120) * scale)
        local shakeScaleY = (pain) * ((opts.shakeY or 40) * scale)
        local offsetX = shakeX * shakeScaleX
        local offsetY = shakeY * shakeScaleY

        local targetX = mx + offsetX
        local targetY = my + offsetY

        -- responsiveness and damping inspired by C# formulas
        local responsiveness = tonumber(opts.responsiveness) or (4 + (str * 0.3))
        local followScale = tonumber(opts.followScale) or 0.25
        followScale = followScale * (conc * 0.01)
        local relax = tonumber(opts.relax) or 1.5

        -- convert to local vector toward target (b)
        local dx = (targetX - mg.handScreenX) * followScale
        local dy = (targetY - mg.handScreenY) * followScale
        local maxLen = (opts.maxLength or 75) * scale
        local len = math.sqrt(dx * dx + dy * dy)
        if len > maxLen then
            dx = dx / len * maxLen
            dy = dy / len * maxLen
        end

        -- Lerp velocity toward b and damp
        mg.handScreenVelX = Lerp(mg.handScreenVelX, dx, responsiveness * num)
        mg.handScreenVelY = Lerp(mg.handScreenVelY, dy, responsiveness * num)

        mg.handScreenVelX = Lerp(mg.handScreenVelX, 0, num * relax)
        mg.handScreenVelY = Lerp(mg.handScreenVelY, 0, num * relax)

        local positionScale = tonumber(opts.positionScale) or 60
        mg.handScreenX = mg.handScreenX + mg.handScreenVelX * num * positionScale
        mg.handScreenY = mg.handScreenY + mg.handScreenVelY * num * positionScale
        -- clamp to bounds
        mg.handScreenX = clamp(mg.handScreenX, bounds[1], bounds[2])
        mg.handScreenY = clamp(mg.handScreenY, bounds[3], bounds[4])

        mg._hp_acc = mg._hp_acc - 1
    end
end

-- compute draw rotation based on horizontal velocity and optional offset
function HandPhysics.Rotation(mg, rotOffset)
    rotOffset = rotOffset or 0
    return (mg.handScreenVelX or 0) * 0.5 + rotOffset
end

return HandPhysics
