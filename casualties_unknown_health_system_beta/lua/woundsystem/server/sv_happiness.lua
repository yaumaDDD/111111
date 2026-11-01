if WoundSystem and WoundSystem.HappinessServerLoaded then return end

WoundSystem = WoundSystem or {}
WoundSystem.HappinessServerLoaded = true

local HAPPINESS_NW = "WoundSystem_Happiness"
local HAPPINESS_BASE_NW = "WoundSystem_HappinessBase"
local HAPPINESS_MIN = -100
local HAPPINESS_MAX = 100
local ALLY_RADIUS_UNITS = 262

local CVAR_FLAGS = {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}
local cvAllyRadius = CreateConVar("woundsys_happiness_ally_radius", tostring(ALLY_RADIUS_UNITS), CVAR_FLAGS, "Ally happiness radius in Source units. Default is about 5 meters.", 1, 5000)
local cvEnabled = CreateConVar("woundsys_happiness_enabled", "1", CVAR_FLAGS, "Enable the WoundSystem happiness simulation.", 0, 1)

local function WoundSystemHealthEnabled()
    local config = WoundSystem and WoundSystem.Health and WoundSystem.Health.Config
    if config and config.IsEnabled then
        return config.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

local Happiness = {}
local DamageMemory = {}
local NegativeRecoveryTicks = {}

local function IsNpcLike(ent)
    return IsValid(ent) and (ent:IsNPC() or (ent.IsNextBot and ent:IsNextBot()))
end

local function IsActor(ent)
    return IsValid(ent) and (ent:IsPlayer() or IsNpcLike(ent))
end

local function IsAssignedPlayerTeam(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false end

    local teamId = ply:Team()
    if not teamId then return false end
    if TEAM_UNASSIGNED and teamId == TEAM_UNASSIGNED then return false end
    if TEAM_SPECTATOR and teamId == TEAM_SPECTATOR then return false end

    local teamName = team.GetName(teamId) or ""
    teamName = string.lower(teamName)

    if teamName == "" then return false end
    if teamName == "unassigned" or teamName == "spectator" or teamName == "connecting" then return false end

    return true
end

local function UsesComparableTeams(a, b)
    return IsValid(a) and IsValid(b) and a:IsPlayer() and b:IsPlayer() and IsAssignedPlayerTeam(a) and IsAssignedPlayerTeam(b)
end

local function RecordDamage(victim, attacker)
    if not IsValid(victim) or not victim:IsPlayer() then return end
    if not IsActor(attacker) or attacker == victim then return end

    DamageMemory[victim] = DamageMemory[victim] or {}
    DamageMemory[victim][attacker] = true
end

local function HasDamaged(victim, attacker)
    return DamageMemory[victim] and DamageMemory[victim][attacker] == true
end

local function ClearAttackerLife(attacker)
    for victim, attackers in pairs(DamageMemory) do
        if not IsValid(victim) then
            DamageMemory[victim] = nil
        elseif attackers then
            attackers[attacker] = nil
        end
    end
end

local function GetDisposition(a, b)
    if not IsValid(a) or not IsValid(b) or not a.Disposition then return nil end

    local ok, disposition = pcall(a.Disposition, a, b)
    if not ok then return nil end

    return disposition
end

local function IsFriendlyDisposition(ent, viewer)
    return GetDisposition(ent, viewer) == D_LI
end

local function IsHostileDisposition(ent, viewer)
    local disposition = GetDisposition(ent, viewer)
    return disposition == D_HT or disposition == D_FR
end

local function IsAlly(viewer, candidate)
    if not IsValid(viewer) or not viewer:IsPlayer() then return false end
    if not IsValid(candidate) or candidate == viewer then return false end

    if candidate:IsPlayer() then
        if UsesComparableTeams(viewer, candidate) then
            return viewer:Team() == candidate:Team()
        end

        return not HasDamaged(viewer, candidate)
    end

    if IsNpcLike(candidate) then
        return IsFriendlyDisposition(candidate, viewer)
    end

    return false
end

local function IsEnemy(viewer, candidate)
    if not IsValid(viewer) or not viewer:IsPlayer() then return false end
    if not IsValid(candidate) or candidate == viewer then return false end

    if candidate:IsPlayer() then
        if UsesComparableTeams(viewer, candidate) then
            return viewer:Team() ~= candidate:Team()
        end

        return HasDamaged(viewer, candidate)
    end

    if IsNpcLike(candidate) then
        return IsHostileDisposition(candidate, viewer) or not IsAlly(viewer, candidate)
    end

    return false
end

local function SetHappiness(ply, value)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not WoundSystemHealthEnabled() then
        Happiness[ply] = nil
        ply:SetNWFloat(HAPPINESS_BASE_NW, 0)
        ply:SetNWFloat(HAPPINESS_NW, 0)
        return
    end

    value = math.Clamp(value or 0, HAPPINESS_MIN, HAPPINESS_MAX)
    if math.abs(value) < 0.0001 then value = 0 end

    Happiness[ply] = value
    ply:SetNWFloat(HAPPINESS_BASE_NW, value)
    ply:SetNWFloat(HAPPINESS_NW, value)

    if WoundSystem and WoundSystem.Health and WoundSystem.Health.GetBody then
        local body = WoundSystem.Health.GetBody(ply)
        if body then body.happiness = value end
    end
end

local function GetHappiness(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return 0 end
    if not WoundSystemHealthEnabled() or cvEnabled:GetBool() == false then return 0 end

    local value = Happiness[ply]
    if value == nil then
        if WoundSystem and WoundSystem.Health and WoundSystem.Health.GetBody then
            local body = WoundSystem.Health.GetBody(ply)
            if body and body.happiness ~= nil then
                value = body.happiness
            end
        end

        if value == nil then
            value = ply:GetNWFloat(HAPPINESS_BASE_NW, 0)
        end

        Happiness[ply] = value
    end
    return value
end

local function Clamp01(value)
    return math.Clamp(value, 0, 1)
end

-- C#: (1f - Clamp01(need * 0.01f + 0.6f)) * 18f
local function NeedHappinessPenalty(needValue)
    needValue = math.min(tonumber(needValue) or 0, 100)
    return (1 - Clamp01(needValue * 0.01 + 0.6)) * 18
end

local function GetPhysiologyContext(ply)
    local ctx = {
        averagePain = 0,
        totalBleedSpeed = 0,
        bloodVolume = 100,
        hunger = 100,
        thirst = 100,
        sicknessAmount = 0,
        radiationSickness = 0,
        wetness = 0,
        hearingLoss = 0,
        opiateHappiness = 0,
        antidepressantHappiness = 0,
        traumaAmount = 0,
        horrifiedLevel = 0,
        mindWipe = false
    }

    if WoundSystem and WoundSystem.GetPlayerPhysiology then
        ctx.averagePain, ctx.totalBleedSpeed, ctx.bloodVolume = WoundSystem.GetPlayerPhysiology(ply)
    end

    if WoundSystem.Health and WoundSystem.Health.GetBody then
        local body = WoundSystem.Health.GetBody(ply)
        if body then
            ctx.averagePain = body.avgPain or ctx.averagePain
            ctx.bloodVolume = body.bloodVolume or ctx.bloodVolume
            ctx.totalBleedSpeed = body.totalBleedSpeed or ctx.totalBleedSpeed
            ctx.hunger = body.hunger or ctx.hunger
            ctx.thirst = body.thirst or ctx.thirst
            ctx.sicknessAmount = body.sicknessAmount or 0
            ctx.radiationSickness = body.radiationSickness or 0
            ctx.wetness = body.wetness or 0
            ctx.hearingLoss = body.hearingLoss or 0
            ctx.opiateHappiness = body.opiateHappiness or 0
            ctx.antidepressantHappiness = body.antidepressantHappiness or 0
            ctx.traumaAmount = body.traumaAmount or 0
            ctx.horrifiedLevel = body.horrifiedLevel or 0
            ctx.mindWipe = body.mindWipe == true
        end
    end

    return ctx
end

-- CAS3-style dynamic happiness: base mood plus physiology/trauma modifiers.
local function GetTotalHappiness(ply)
    if not WoundSystemHealthEnabled() or cvEnabled:GetBool() == false then return 0 end

    local happiness = GetHappiness(ply)
    local ctx = GetPhysiologyContext(ply)

    local total = happiness
        - ((happiness < -50) and (ctx.totalBleedSpeed * 15) or 0)
        - ctx.averagePain * 0.1
        - ctx.sicknessAmount * 0.1
        - NeedHappinessPenalty(ctx.hunger)
        - NeedHappinessPenalty(ctx.thirst)
        - ctx.radiationSickness * 0.1
        - ctx.hearingLoss * 0.2
        - (100 - math.min(ctx.bloodVolume, 100)) * 0.2
        - ctx.traumaAmount * 0.525
        - ctx.wetness * 0.05
        + ctx.opiateHappiness
        + ctx.antidepressantHappiness

    if ctx.mindWipe then
        total = 0
    end

    total = total * (1 - math.Clamp(ctx.horrifiedLevel or 0, 0, 100) * 0.005)

    return math.Clamp(total, HAPPINESS_MIN, HAPPINESS_MAX)
end

local function AddHappiness(ply, amount)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if amount == 0 then return end

    SetHappiness(ply, GetHappiness(ply) + amount)
    ply:SetNWFloat(HAPPINESS_NW, GetTotalHappiness(ply))
end

local function GetDepressionFailureChance(ply)
    if not WoundSystemHealthEnabled() then return 0 end

    local total = GetTotalHappiness(ply)
    if total > -20 then return 0 end

    return math.Clamp((math.abs(total) - 20) / 100, 0, 0.8)
end

local function RollAllowsDepressedAction(ply, actionName)
    if not WoundSystemHealthEnabled() then return true end

    local chance = GetDepressionFailureChance(ply)
    if chance <= 0 then return true end

    if math.Rand(0, 1) >= chance then return true end

    ply._woundSystemNextDepressionNotice = ply._woundSystemNextDepressionNotice or 0
    if CurTime() >= ply._woundSystemNextDepressionNotice then
        local notice = actionName
        if notice == nil then notice = "You cannot bring yourself to do that." end
        if notice ~= "" then
            ply:PrintMessage(HUD_PRINTCENTER, notice)
            ply._woundSystemNextDepressionNotice = CurTime() + 2.5
        end
    end

    AddHappiness(ply, -0.15)
    return false
end

local function ResolveOwner(ent)
    if not IsValid(ent) then return nil end
    if IsActor(ent) then return ent end

    if ent.GetDriver then
        local driver = ent:GetDriver()
        if IsActor(driver) then return driver end
    end

    if ent.GetOwner then
        local owner = ent:GetOwner()
        if IsActor(owner) then return owner end
    end

    if ent.GetCreator then
        local creator = ent:GetCreator()
        if IsActor(creator) then return creator end
    end

    if ent.GetPhysicsAttacker then
        local physAttacker = ent:GetPhysicsAttacker(10)
        if IsActor(physAttacker) then return physAttacker end
    end

    return nil
end

local function ResolveDamageAttacker(dmginfo)
    if not dmginfo then return nil end

    local attacker = ResolveOwner(dmginfo:GetAttacker())
    if attacker then return attacker end

    return ResolveOwner(dmginfo:GetInflictor())
end

local function ResolveKillAttacker(attacker, inflictor)
    return ResolveOwner(attacker) or ResolveOwner(inflictor)
end

local function CountNearbyAllies(ply)
    local count = 0
    local radius = math.max(cvAllyRadius:GetFloat(), 1)

    for _, ent in ipairs(ents.FindInSphere(ply:GetPos(), radius)) do
        if ent == ply then continue end

        if ent:IsPlayer() then
            if ent:Alive() and IsAlly(ply, ent) then
                count = count + 1
            end
        elseif IsNpcLike(ent) and ent:Health() > 0 and IsAlly(ply, ent) then
            count = count + 1
        end
    end

    return count
end

local function ApplyNearbyAllyGain(ply)
    local allyCount = CountNearbyAllies(ply)
    if allyCount <= 0 then return end

    AddHappiness(ply, 0.1 + ((allyCount - 1) * 0.05))
end

local function ApproachZero(value, amount)
    if value > 0 then
        return math.max(0, value - amount)
    elseif value < 0 then
        return math.min(0, value + amount)
    end

    return 0
end

local function ApplyPassiveDrift(ply)
    local happiness = GetHappiness(ply) or 0

    if happiness > 0 then
        NegativeRecoveryTicks[ply] = 0
        SetHappiness(ply, ApproachZero(happiness, 0.1))
    elseif happiness < 0 then
        NegativeRecoveryTicks[ply] = (NegativeRecoveryTicks[ply] or 0) + 1

        if NegativeRecoveryTicks[ply] >= 3 then
            NegativeRecoveryTicks[ply] = 0
            SetHappiness(ply, ApproachZero(happiness, 0.1))
        end
    else
        NegativeRecoveryTicks[ply] = 0
    end
end

local function CanWitnessDeath(viewer, victim, deathPos)
    if not IsValid(viewer) or not viewer:IsPlayer() or not viewer:Alive() then return false end
    if not IsValid(victim) or viewer == victim then return false end
    if not IsAlly(viewer, victim) then return false end

    local eyePos = viewer:EyePos()
    local toDeath = deathPos - eyePos
    if toDeath:LengthSqr() <= 1 then return true end

    local fov = viewer:GetFOV()
    if not fov or fov <= 0 then fov = 90 end

    local dot = viewer:GetAimVector():Dot(toDeath:GetNormalized())
    if dot < math.cos(math.rad(fov * 0.5)) then return false end

    local tr = util.TraceLine({
        start = eyePos,
        endpos = deathPos,
        filter = {viewer, victim},
        mask = MASK_VISIBLE_AND_NPCS
    })

    return not tr.Hit or tr.Fraction >= 0.98
end

local function ApplyWitnessEffects(victim, killer)
    if not IsValid(victim) then return end

    local deathPos = victim:WorldSpaceCenter()
    for _, viewer in ipairs(player.GetAll()) do
        if viewer ~= killer and CanWitnessDeath(viewer, victim, deathPos) then
            AddHappiness(viewer, math.Rand(-15, -5))
        end
    end
end

local function ApplyKillHappiness(victim, attacker)
    if not IsValid(victim) or not IsValid(attacker) or not attacker:IsPlayer() or attacker == victim then return end
    if not (victim:IsPlayer() or IsNpcLike(victim)) then return end

    local victimDamagedAttacker = HasDamaged(attacker, victim)

    if IsAlly(attacker, victim) then
        if victimDamagedAttacker then
            AddHappiness(attacker, math.Rand(0.5, 3))
        else
            AddHappiness(attacker, math.Rand(-10, -5))
        end
    elseif IsEnemy(attacker, victim) then
        if victimDamagedAttacker then
            AddHappiness(attacker, math.Rand(3, 5))
        else
            AddHappiness(attacker, math.Rand(-2, -0.5))
        end
    end
end

local function HandleDeath(victim, attacker, inflictor)
    local killer = ResolveKillAttacker(attacker, inflictor)

    ApplyKillHappiness(victim, killer)
    ApplyWitnessEffects(victim, killer)
end

hook.Add("PlayerInitialSpawn", "WoundSystem_HappinessInit", function(ply)
    if not WoundSystemHealthEnabled() then return end
    SetHappiness(ply, 0)
end)

hook.Add("PlayerSpawn", "WoundSystem_HappinessRespawn", function(ply)
    if OverrideSpawn then return end -- Z-City fake-ragdoll get-up, not a real respawn
    if not WoundSystemHealthEnabled() then return end
    SetHappiness(ply, 0)
    NegativeRecoveryTicks[ply] = 0
    ClearAttackerLife(ply)
end)

hook.Add("PlayerDisconnected", "WoundSystem_HappinessCleanup", function(ply)
    Happiness[ply] = nil
    DamageMemory[ply] = nil
    NegativeRecoveryTicks[ply] = nil
    ClearAttackerLife(ply)
end)

hook.Add("EntityRemoved", "WoundSystem_HappinessEntityCleanup", function(ent)
    DamageMemory[ent] = nil
    ClearAttackerLife(ent)
end)

hook.Add("EntityTakeDamage", "WoundSystem_HappinessDamageMemory", function(victim, dmginfo)
    if not WoundSystemHealthEnabled() then return end
    if cvEnabled:GetBool() == false then return end
    if not IsValid(victim) or not victim:IsPlayer() then return end

    RecordDamage(victim, ResolveDamageAttacker(dmginfo))
end)

hook.Add("PlayerDeath", "WoundSystem_HappinessPlayerDeath", function(victim, inflictor, attacker)
    if not WoundSystemHealthEnabled() then return end
    if cvEnabled:GetBool() == false then return end

    HandleDeath(victim, attacker, inflictor)
end)

hook.Add("OnNPCKilled", "WoundSystem_HappinessNPCDeath", function(npc, attacker, inflictor)
    if not WoundSystemHealthEnabled() then return end
    if cvEnabled:GetBool() == false then return end

    HandleDeath(npc, attacker, inflictor)
end)

timer.Create("WoundSystem_HappinessTick", 1, 0, function()
    if not WoundSystemHealthEnabled() then
        for ply in pairs(Happiness) do
            if IsValid(ply) then
                ply:SetNWFloat(HAPPINESS_BASE_NW, 0)
                ply:SetNWFloat(HAPPINESS_NW, 0)
            end
            Happiness[ply] = nil
            NegativeRecoveryTicks[ply] = nil
        end
        return
    end
    if cvEnabled:GetBool() == false then return end

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) then continue end

        if not Happiness[ply] then
            SetHappiness(ply, 0)
        end

        if ply:Alive() then
            -- FIRST: Run standard shifts (passive restoration/ally gain)
            ApplyPassiveDrift(ply)
            ApplyNearbyAllyGain(ply)

            -- SECOND: Process the math and apply physical penalties directly to the network
            local dynamicTotal = GetTotalHappiness(ply)
            ply:SetNWFloat(HAPPINESS_NW, dynamicTotal)

            if WoundSystem and WoundSystem.Health and WoundSystem.Health.GetBody then
                local body = WoundSystem.Health.GetBody(ply)
                if body then body.totalHappiness = dynamicTotal end
            end
        end
    end
end)

WoundSystemHappiness = WoundSystemHappiness or {}
WoundSystemHappiness.Get = GetHappiness
WoundSystemHappiness.GetBase = GetHappiness
WoundSystemHappiness.Set = SetHappiness
WoundSystemHappiness.Add = AddHappiness
WoundSystemHappiness.IsAlly = IsAlly
WoundSystemHappiness.Total = GetTotalHappiness
WoundSystemHappiness.DepressionFailureChance = GetDepressionFailureChance
WoundSystemHappiness.RollAllowsAction = RollAllowsDepressedAction
