if WoundSystem and WoundSystem.BrainEffects and WoundSystem.BrainEffects._ServerLoaded then
    for _, ply in ipairs(player.GetAll()) do
        timer.Remove("WoundSystem_LobotomyLoop_" .. ply:EntIndex())
        timer.Remove("DoomLoop_" .. ply:EntIndex())
        timer.Remove("WoundSystem_BrainControlReverse_" .. ply:EntIndex())
        timer.Remove("WoundSystem_BrainDamageRagdoll_" .. ply:EntIndex())
    end

    hook.Remove("PostEntityTakeDamage", "WoundSystem_LobotomyTriggerTakeDamage")
    hook.Remove("Tick", "WoundSystem_LobotomyCureCheck")
    hook.Remove("PlayerDeath", "WoundSystem_LobotomyDeathClean")
    hook.Remove("PlayerDisconnected", "WoundSystem_LobotomyDCClean")
    hook.Remove("PostEntityTakeDamage", "DoomTriggerTakeDamage")
    hook.Remove("Tick", "DoomCureCheck")
    hook.Remove("Think", "WoundSystem_CSharpBrainSymptomChecks")
    hook.Remove("PlayerDeath", "DoomDeathClean")
    hook.Remove("PlayerDisconnected", "DoomDCClean")
    timer.Remove("DoomCureCheck")
    timer.Remove("WoundSystem_CSharpBrainSymptomChecks")
end

WoundSystem = WoundSystem or {}
WoundSystem.BrainEffects = WoundSystem.BrainEffects or {}
WoundSystem.BrainEffects._ServerLoaded = true

local CVAR_FLAGS = {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}

local LOBOTOMY_START_HP = 15
local LOBOTOMY_COOLDOWN = 10
local LOBOTOMY_REPEAT_CHANCE = 20
local LOBOTOMY_RECOVERY_HEAL = 25
local LOBOTOMY_RECOVERY_HP = 50
local cvBrainSymptomsEnabled = CreateConVar("woundsys_brain_symptoms_enabled", "1", CVAR_FLAGS, "Enable C#-style brain damage symptoms.", 0, 1)
local cvBrainSymptomInterval = CreateConVar("woundsys_brain_symptom_interval", "30", CVAR_FLAGS, "Seconds between brain symptom checks.", 5, 120)
local cvBrainSymptomThreshold = CreateConVar("woundsys_brain_symptom_threshold", "95", CVAR_FLAGS, "Brain health below this can cause symptoms.", 0, 100)
local cvBrainRagdollSymptoms = CreateConVar("woundsys_brain_ragdoll_symptoms", "1", CVAR_FLAGS, "Allow brain damage to cause brief ragdoll stumbles.", 0, 1)

local function WoundSystemHealthEnabled()
    local config = WoundSystem and WoundSystem.Health and WoundSystem.Health.Config
    if config and config.IsEnabled then
        return config.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

if util and util.AddNetworkString then
    util.AddNetworkString("WoundSystem_LobotomyEffect")
end

if WoundSystem.Resources and WoundSystem.Resources.AddExistingFile then
    WoundSystem.Resources.AddExistingFile("sound/lobotomy_assets/Lobotomy.ogg")
    WoundSystem.Resources.AddExistingFile("sound/lobotomy.ogg")
end

local function SendFlashBrain(ply)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    net.Start("WoundSystem_LobotomyEffect")
    net.Send(ply)
end

local function ApplyHalveEffect(ply)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local newHp = math.floor(ply:Health() / 2)
    if newHp <= 0 then
        ply:Kill()
        return
    end

    ply:SetHealth(newHp)
    SendFlashBrain(ply)
end

local function ScheduleLobotomyLoop(ply)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local timerName = "WoundSystem_LobotomyLoop_" .. ply:EntIndex()
    local chance = LOBOTOMY_REPEAT_CHANCE

    timer.Create(timerName, math.random(20, 40), 1, function()
        if not WoundSystemHealthEnabled() then
            timer.Remove(timerName)
            return
        end

        if not IsValid(ply) or not ply:Alive() then return end
        if not ply.WoundSystemLobotomyActive then return end

        if math.random(1, 100) <= chance then
            ApplyHalveEffect(ply)
        end

        ScheduleLobotomyLoop(ply)
    end)
end

local function GetBody(ply)
    return WoundSystem
        and WoundSystem.Health
        and WoundSystem.Health.GetBody
        and WoundSystem.Health.GetBody(ply)
        or nil
end

local function SymptomRoll(brainHealth, multiplier)
    multiplier = multiplier or 1
    return math.Rand(0, 1) > (math.Clamp(brainHealth or 100, 0, 100) * 0.01 * multiplier)
end

local function SetReverseWindow(ply, duration)
    if not IsValid(ply) then return end

    duration = math.max(duration or 0, 0)
    if not WoundSystemHealthEnabled() and duration > 0 then return end
    ply:SetNWFloat("WoundSystemBrainReverseUntil", CurTime() + duration)
end

local function StartBrainControlReverse(ply)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local timerName = "WoundSystem_BrainControlReverse_" .. ply:EntIndex()
    timer.Remove(timerName)

    local pulseCount = math.random(6, 12)
    local pulseIndex = 0

    local function NextPulse()
        if not WoundSystemHealthEnabled() then
            SetReverseWindow(ply, 0)
            timer.Remove(timerName)
            return
        end

        if not IsValid(ply) or not ply:Alive() then
            timer.Remove(timerName)
            return
        end

        pulseIndex = pulseIndex + 1
        if pulseIndex > pulseCount then
            SetReverseWindow(ply, 0)
            timer.Remove(timerName)
            return
        end

        local onTime = math.Rand(0.25, 2)
        local offTime = math.Rand(0.6, 2.5)

        SetReverseWindow(ply, onTime)
        timer.Create(timerName, onTime + offTime, 1, NextPulse)
    end

    NextPulse()
end

local function StartBrainDamageRagdoll(ply, body)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end
    if cvBrainRagdollSymptoms and not cvBrainRagdollSymptoms:GetBool() then return end

    body = body or GetBody(ply)
    if not body or body.unconscious or body.fallingRagdoll then return end

    local timerName = "WoundSystem_BrainDamageRagdoll_" .. ply:EntIndex()
    timer.Remove(timerName)

    ply:SetNWFloat("WoundSystemBrainShakeUntil", CurTime() + 5)
    timer.Create(timerName, 5, 1, function()
        if not WoundSystemHealthEnabled() then
            ply:SetNWFloat("WoundSystemBrainShakeUntil", 0)
            return
        end

        if not IsValid(ply) or not ply:Alive() then return end

        local currentBody = GetBody(ply)
        if not currentBody or currentBody.unconscious or currentBody.fallingRagdoll then return end

        currentBody.fallingRagdoll = true
        currentBody.fallingRagdollWakeTime = CurTime() + 3
        currentBody.fallingRagdollReason = "brain"

        local health = WoundSystem and WoundSystem.Health
        if health and health.TryCreateUnconsciousRagdoll then
            health.TryCreateUnconsciousRagdoll(ply, currentBody)
        end
    end)
end

local function RunBrainSymptomCheck(ply)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) or not ply:Alive() then return end
    if not cvBrainSymptomsEnabled:GetBool() then return end

    local body = GetBody(ply)
    if not body or body.unconscious or body.brainDead then return end

    local brainHealth = math.Clamp(body.brainHealth or 100, 0, 100)
    local threshold = cvBrainSymptomThreshold:GetFloat()
    if brainHealth >= threshold then return end

    -- C# Body.HandlePeriodicChecks: each half-minute, low brain health can trigger independent symptoms.
    if SymptomRoll(brainHealth, 1) and math.Rand(0, 1) < 0.8 then
        StartBrainControlReverse(ply)
    end

    if (body.consciousness or 100) > 20 and SymptomRoll(brainHealth, 1) then
        SendFlashBrain(ply)
    end

    if SymptomRoll(brainHealth, 0.6) then
        StartBrainDamageRagdoll(ply, body)
    end

    local cas3BodyFeel = WoundSystem and WoundSystem.Health and WoundSystem.Health.CAS3BodyFeel
    if cas3BodyFeel and cas3BodyFeel.RunBrainSymptomExtras then
        cas3BodyFeel.RunBrainSymptomExtras(ply, body, brainHealth, SymptomRoll)
    end
end

hook.Add("PostEntityTakeDamage", "WoundSystem_LobotomyTriggerTakeDamage", function(ent, _, tookDamage)
    if not WoundSystemHealthEnabled() then return end
    if not tookDamage or not IsValid(ent) or not ent:IsPlayer() or not ent:Alive() then return end

    local startHp = LOBOTOMY_START_HP
    local cooldown = LOBOTOMY_COOLDOWN

    if ent:Health() <= startHp and not ent.WoundSystemLobotomyActive then
        if ent.WoundSystemLobotomyLastStart and ent.WoundSystemLobotomyLastStart > CurTime() - cooldown then return end

        ent.WoundSystemLobotomyActive = true
        ent.WoundSystemLobotomyLastStart = CurTime()

        ApplyHalveEffect(ent)
        ScheduleLobotomyLoop(ent)
    end
end)

timer.Create("WoundSystem_LobotomyCureCheck", 0.5, 0, function()
    if not WoundSystemHealthEnabled() then return end

    local recoveryHp = LOBOTOMY_RECOVERY_HP

    for _, ply in ipairs(player.GetAll()) do
        if ply.WoundSystemLobotomyActive and ply:Alive() and ply:Health() >= recoveryHp then
            ply.WoundSystemLobotomyActive = false
            timer.Remove("WoundSystem_LobotomyLoop_" .. ply:EntIndex())

            local heal = LOBOTOMY_RECOVERY_HEAL
            ply:SetHealth(math.min(ply:Health() + heal, 100))
        end
    end
end)

timer.Create("WoundSystem_CSharpBrainSymptomChecks", 1, 0, function()
    if not WoundSystemHealthEnabled() then return end
    if not cvBrainSymptomsEnabled:GetBool() then return end

    local interval = math.max(cvBrainSymptomInterval:GetFloat(), 5)
    local now = CurTime()

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            ply.WoundSystemNextBrainSymptomCheck = ply.WoundSystemNextBrainSymptomCheck or (now + math.Rand(2, interval))
            if now >= ply.WoundSystemNextBrainSymptomCheck then
                ply.WoundSystemNextBrainSymptomCheck = now + interval
                RunBrainSymptomCheck(ply)
            end
        end
    end
end)

local function Cleanup(ply)
    ply.WoundSystemLobotomyActive = false
    timer.Remove("WoundSystem_LobotomyLoop_" .. ply:EntIndex())
    timer.Remove("WoundSystem_BrainControlReverse_" .. ply:EntIndex())
    timer.Remove("WoundSystem_BrainDamageRagdoll_" .. ply:EntIndex())
    ply:SetNWFloat("WoundSystemBrainReverseUntil", 0)
    ply:SetNWFloat("WoundSystemBrainShakeUntil", 0)
end

hook.Add("PlayerDeath", "WoundSystem_LobotomyDeathClean", Cleanup)
hook.Add("PlayerDisconnected", "WoundSystem_LobotomyDCClean", Cleanup)

WoundSystem.BrainEffects.ApplyLobotomyHit = ApplyHalveEffect
WoundSystem.BrainEffects.ScheduleLobotomyLoop = ScheduleLobotomyLoop
WoundSystem.BrainEffects.FlashBrain = SendFlashBrain
WoundSystem.BrainEffects.StartBrainControlReverse = StartBrainControlReverse
WoundSystem.BrainEffects.RunBrainSymptomCheck = RunBrainSymptomCheck
