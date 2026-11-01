util.AddNetworkString("WoundSystem_StartSelfHarmMinigame")
util.AddNetworkString("WoundSystem_SelfHarmCompleted")

WoundSystem = WoundSystem or {}
WoundSystem.SelfHarmDisabled = true

function WoundSystem.RemoveEye(ply)
    if not IsValid(ply) then return end

    local headState = WoundSystem.Health and WoundSystem.Health.GetLimbState and WoundSystem.Health.GetLimbState(ply, "head")
    local body = WoundSystem.Health and WoundSystem.Health.GetBody and WoundSystem.Health.GetBody(ply)

    if headState then
        headState.eyes = math.max((headState.eyes or 2) - 1, 0)
        headState.pain = 100
        headState.bleed = math.Clamp((headState.bleed or 0) + 20, 0, 100)
        if body then
            body.bothEyesGone = (headState.eyes <= 0)
            body.traumaAmount = math.Clamp((body.traumaAmount or 0) + 35, 0, 100)
        end
        if WoundSystem.Health.SendLimbUpdate then
            WoundSystem.Health.SendLimbUpdate(ply, "head", true)
        end
    end
end

-- CAS3 SelfHarmer.cs constants
local LOW_MOOD_THRESHOLD   = -70   -- body.totalHappiness <= -70
local STILL_THRESHOLD      = 30    -- timeWasStill > 30 -> AttemptHarm
local SOUND_THRESHOLD      = 20    -- timeWasStill > 20 -> play warningLoop
local SELFHARM_COOLDOWN    = 180   -- cooldownTime = 180 (SelfHarm coroutine)
local SUICIDE_COOLDOWN     = 300   -- cooldownTime = 300 (Suicide coroutine)
local VELOCITY_STILL_CAP   = 100   -- Source units/s ~= 5 m/s CAS3

-- CAS3 SelfHarmer.cs: blackAmount = Lerp(blackAmount, Clamp01((timeWasStill-20)*0.1) + horrifiedLevel*0.008, dt*2)
-- We store per-player state in player variables.

local function GetTotalHappiness(ply)
    if WoundSystemHappiness and WoundSystemHappiness.Total then
        return WoundSystemHappiness.Total(ply)
    end
    return ply:GetNWFloat("WoundSystem_Happiness", 0)
end

local function GetBaseHappiness(ply)
    if WoundSystemHappiness and WoundSystemHappiness.Get then
        return WoundSystemHappiness.Get(ply)
    end
    return 0
end

local function AddHappiness(ply, amount)
    if WoundSystemHappiness and WoundSystemHappiness.Add then
        WoundSystemHappiness.Add(ply, amount)
    end
end

local function GetHorrified(ply)
    local body = WoundSystem.Health and WoundSystem.Health.GetBody and WoundSystem.Health.GetBody(ply)
    return body and (body.horrifiedLevel or 0) or 0
end

-- Check if player has a plushie in inventory (CAS3: body.FindByIdThorough("plushie"))
local function HasPlushie(ply)
    if WoundSystem and WoundSystem.Health and WoundSystem.Health.GetInventory then
        local inv = WoundSystem.Health.GetInventory(ply)
        if inv then
            for slotId, item in pairs(inv) do
                if item and (item.id == "plushie" or item.itemId == "plushie") then
                    return true, slotId
                end
            end
        end
    end
    return false
end

-- Check if player has gun in inventory (CAS3: body.FindByTagThorough("gun"))
local function HasGun(ply)
    if WoundSystem and WoundSystem.Health and WoundSystem.Health.GetInventory then
        local inv = WoundSystem.Health.GetInventory(ply)
        if inv then
            for slotId, item in pairs(inv) do
                if item and (item.tags and table.HasValue(item.tags, "gun")) then
                    return true
                end
            end
        end
    end
    -- Fallback: check held weapon
    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and (wep:GetClass():find("gun") or wep:GetClass():find("pistol") or wep:GetClass():find("rifle")) then
        return true
    end
    return false
end

-- Check if BOTH eyes are gone
local function BothEyesGone(ply)
    local body = WoundSystem.Health and WoundSystem.Health.GetBody and WoundSystem.Health.GetBody(ply)
    return body and body.bothEyesGone or false
end

-- Get the available non-dismembered arm limbs (CAS3: limbs[4] = left forearm, limbs[7] = right forearm)
local ARM_LIMBS = {"left_forearm", "right_forearm", "left_arm", "right_arm"}
local function PickArmLimb(ply)
    local limbs = WoundSystem.Health and WoundSystem.Health.GetLimbs and WoundSystem.Health.GetLimbs(ply)
    if not limbs then return nil end
    -- Try to pick a random forearm that isn't dismembered
    local candidates = {}
    for _, limbId in ipairs(ARM_LIMBS) do
        local state = limbs[limbId]
        if state and not state.dismembered then
            table.insert(candidates, limbId)
        end
    end
    if #candidates == 0 then
        -- Fallback: any non-dismembered limb except head
        for limbId, state in pairs(limbs) do
            if limbId ~= "head" and not state.dismembered then
                table.insert(candidates, limbId)
            end
        end
    end
    if #candidates == 0 then return nil end
    return candidates[math.random(1, #candidates)]
end

local function ApplySelfHarmWound(ply)
    -- CAS3 SelfHarm(): muscle -= 13, skin -= 35, bleed += Rand(6,10), pain += Rand(20,30)
    local limbId = PickArmLimb(ply)
    if not limbId then return end

    local state = WoundSystem.Health.GetLimbState and WoundSystem.Health.GetLimbState(ply, limbId)
    if not state then return end

    state.muscle = math.Clamp((state.muscle or 100) - 13, 0, 100)
    state.skin   = math.Clamp((state.skin or 100) - 35, 0, 100)
    state.bleed  = math.Clamp((state.bleed or 0) + math.Rand(6, 10), 0, 100)
    state.pain   = math.Clamp((state.pain or 0) + math.Rand(20, 30), 0, 100)
    state.hasSelfHarmWound = true

    if WoundSystem.Health.SendLimbUpdate then
        WoundSystem.Health.SendLimbUpdate(ply, limbId, true)
    end

    -- CAS3: happiness += 4, sound selfharm + harmSting (0.7)
    AddHappiness(ply, 4)
    ply:EmitSound("woundsystem/selfharm.ogg", 75, 100, 1.0)
    timer.Simple(0.1, function()
        if IsValid(ply) then ply:EmitSound("woundsystem/harmSting.ogg", 75, 100, 0.7) end
    end)

    -- CAS3: body.rb.AddForce(Random.insideUnitCircle * 500)
    local impulse = Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0):GetNormal() * 200
    ply:SetVelocity(impulse)
end

local function ApplySuicideWound(ply, isEye)
    -- CAS3 Suicide(): muscle -= 30, skin -= 70, bleed += Rand(45,60), pain += Rand(25,35), adrenaline += 50
    local limbId
    if isEye then
        limbId = "head"
    else
        -- CAS3: Random.Range(0,1)<0.5 ? limbs[4] : limbs[7] (left or right forearm)
        limbId = math.random() < 0.5 and "left_forearm" or "right_forearm"
        local limbs = WoundSystem.Health.GetLimbs and WoundSystem.Health.GetLimbs(ply)
        if limbs then
            local state = limbs[limbId]
            if state and state.dismembered then
                limbId = "torso"
            end
        end
    end

    local state = WoundSystem.Health.GetLimbState and WoundSystem.Health.GetLimbState(ply, limbId)
    if state then
        state.muscle = math.Clamp((state.muscle or 100) - 30, 0, 100)
        state.skin   = math.Clamp((state.skin or 100) - 70, 0, 100)
        state.bleed  = math.Clamp((state.bleed or 0) + math.Rand(45, 60), 0, 100)
        state.pain   = math.Clamp((state.pain or 0) + math.Rand(25, 35), 0, 100)
        state.hasSuicideWound = true
        if WoundSystem.Health.SendLimbUpdate then
            WoundSystem.Health.SendLimbUpdate(ply, limbId, true)
        end
    end

    -- CAS3: adrenaline += 50
    local body = WoundSystem.Health.GetBody and WoundSystem.Health.GetBody(ply)
    if body then body.adrenaline = math.Clamp((body.adrenaline or 0) + 50, 0, 100) end

    -- CAS3: happiness += isEye ? 16 : 12.5
    AddHappiness(ply, isEye and 16 or 12.5)

    -- CAS3: RemoveEye() if isEye
    if isEye and WoundSystem and WoundSystem.RemoveEye then
        WoundSystem.RemoveEye(ply)
    end

    -- CAS3: body.rb.AddForce(Random.insideUnitCircle * 700)
    local impulse = Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0):GetNormal() * 280
    ply:SetVelocity(impulse)

    -- Sounds: suicide + harmSting(1, 0.7)
    ply:EmitSound("woundsystem/suicide.ogg", 75, 100, 1.0)
    timer.Simple(0.1, function()
        if IsValid(ply) then ply:EmitSound("woundsystem/harmSting.ogg", 75, 100, 0.7) end
    end)
end

-- CAS3 SelfHarmer.Update() logic (runs every tick)
local THINK_INTERVAL = 0.05  -- ~20 times/sec, close to Unity Update()
local nextThink = 0

hook.Add("Think", "WoundSystem_SelfHarmServerThink", function()
    if WoundSystem and WoundSystem.SelfHarmDisabled then return end
    local now = CurTime()
    if now < nextThink then return end
    nextThink = now + THINK_INTERVAL

    local dt = THINK_INTERVAL

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then
            ply._wsSHTimeWasStill = 0
            continue
        end

        -- Skip if currently harming (minigame is open server-side tracking)
        if ply._wsIsHarming then continue end

        local totalHappiness = GetTotalHappiness(ply)
        local baseHappiness  = GetBaseHappiness(ply)

        if totalHappiness <= LOW_MOOD_THRESHOLD then
            -- CAS3: blackAmount lerp
            local horrified = GetHorrified(ply)
            local stillTime = ply._wsSHTimeWasStill or 0
            local blackTarget = math.Clamp((stillTime - 20) * 0.1, 0, 1) + horrified * 0.008
            ply._wsSHBlackAmount = Lerp(dt * 2, ply._wsSHBlackAmount or 0, blackTarget)

            local cooldown = ply._wsSHCooldown or 0
            if cooldown > now then
                -- CAS3: else branch in cooldown -> timeWasStill = 0, cooldownTime -= dt, stop scarySource
                ply._wsSHTimeWasStill = 0
                -- (warningloop stops - handled client side since client owns the audio)
            else
                -- CAS3: conscious && velocity < 5 m/s
                local vel = ply:GetVelocity():Length()
                local isVeryDepressed = baseHappiness < -75
                if ply:Alive() and vel < VELOCITY_STILL_CAP then
                    -- CAS3: timeWasStill += dt * (happiness < -75 ? 1 : 0.75) * 2.5
                    local speedMult = isVeryDepressed and 1.0 or 0.75
                    ply._wsSHTimeWasStill = (ply._wsSHTimeWasStill or 0) + dt * speedMult * 2.5
                else
                    -- CAS3: timeWasStill -= dt * (happiness < -75 ? 2 : 3) * 2.5
                    local decayMult = isVeryDepressed and 2.0 or 3.0
                    ply._wsSHTimeWasStill = math.max(0, (ply._wsSHTimeWasStill or 0) - dt * decayMult * 2.5)
                end

                stillTime = ply._wsSHTimeWasStill or 0

                -- CAS3: timeWasStill > 30 -> AttemptHarm
                if stillTime > STILL_THRESHOLD then
                    ply._wsSHTimeWasStill = 0
                    ply._wsIsHarming = true

                    -- CAS3 AttemptHarm():
                    -- 1. Has plushie -> destroy it, happiness+5, cooldown=240, harming=false
                    -- 2. totalHappiness > -90 -> SelfHarm() coroutine
                    -- 3. totalHappiness <= -90 -> Suicide() coroutine

                    local hasPlushie = HasPlushie(ply)
                    if hasPlushie then
                        -- CAS3: it.condition = 0, happiness += 5, cooldownTime = 240
                        AddHappiness(ply, 5)
                        ply._wsSHCooldown = now + 240
                        ply._wsIsHarming = false

                    elseif totalHappiness > -90 then
                        -- CAS3: StartCoroutine(SelfHarm()) -> WaitForMinigame(1) -> apply wounds
                        ply._wsSHCooldown = now + SELFHARM_COOLDOWN

                        net.Start("WoundSystem_StartSelfHarmMinigame")
                            net.WriteInt(1, 8)
                            net.WriteBool(false)
                        net.Send(ply)
                        -- wound application happens in net.Receive("WoundSystem_SelfHarmCompleted")

                    else
                        -- CAS3: StartCoroutine(Suicide())
                        -- If has gun -> GunSuicide; else eye if totalHappiness<=-99.9 & !bothEyesGone & 50% chance
                        ply._wsSHCooldown = now + SUICIDE_COOLDOWN

                        local isEye = totalHappiness <= -99 and not BothEyesGone(ply) and math.random() < 0.5
                        local cuts  = isEye and 1 or 5

                        net.Start("WoundSystem_StartSelfHarmMinigame")
                            net.WriteInt(cuts, 8)
                            net.WriteBool(isEye)
                        net.Send(ply)
                    end
                end
            end
        else
            -- CAS3: else -> blackAmount lerp toward horrifiedLevel*0.008, timeWasStill=0, stop sound
            local horrified = GetHorrified(ply)
            ply._wsSHBlackAmount = Lerp(dt * 2, ply._wsSHBlackAmount or 0, horrified * 0.008)
            ply._wsSHTimeWasStill = 0
        end
    end
end)

net.Receive("WoundSystem_SelfHarmCompleted", function(_, ply)
    if not IsValid(ply) or not ply:Alive() then return end

    local wasEye   = net.ReadBool()
    local cutsCount = net.ReadInt(8)

    ply._wsIsHarming = false

    local totalHappiness = GetTotalHappiness(ply)

    if wasEye or cutsCount >= 5 or totalHappiness <= -90 then
        -- Suicide-level wound (muscle -30, skin -70, bleed +45..60, pain +25..35, adrenaline +50, suicideWound overlay)
        ApplySuicideWound(ply, wasEye)
    else
        -- Self-harm wound (muscle -13, skin -35, bleed +6..10, pain +20..30, selfHarmWound overlay)
        ApplySelfHarmWound(ply)
    end
end)

-- Cleanup on death/disconnect
hook.Add("PlayerDeath", "WoundSystem_SelfHarmReset", function(ply)
    ply._wsIsHarming = false
    ply._wsSHTimeWasStill = 0
    ply._wsSHBlackAmount = 0
    ply._wsSHCooldown = 0
end)

hook.Add("PlayerDisconnected", "WoundSystem_SelfHarmCleanup", function(ply)
    ply._wsIsHarming = nil
    ply._wsSHTimeWasStill = nil
    ply._wsSHBlackAmount = nil
    ply._wsSHCooldown = nil
end)

-- Admin command to trigger self-harm minigame on player or target
concommand.Add("woundsystem_trigger_selfharm", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then return end

    local target = ply
    if args[1] then
        local found = player.GetByNick(args[1])
        if IsValid(found) then target = found end
    end

    if not IsValid(target) then return end

    local cuts  = tonumber(args[2]) or 1
    local isEye = (args[3] == "1" or args[3] == "eye")

    net.Start("WoundSystem_StartSelfHarmMinigame")
        net.WriteInt(cuts, 8)
        net.WriteBool(isEye)
    net.Send(target)

    if IsValid(ply) then
        ply:ChatPrint("[WoundSystem] Triggered self-harm minigame on " .. target:Nick())
    end
end)
