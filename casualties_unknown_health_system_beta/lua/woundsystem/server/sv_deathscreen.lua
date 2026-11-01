util.AddNetworkString("WoundSystem_PlayerDied")
util.AddNetworkString("WoundSystem_PlayerRespawnRequest")
util.AddNetworkString("WoundSystem_ClearDeathScreen")

local function WoundSystemHealthEnabled()
    local config = WoundSystem and WoundSystem.Health and WoundSystem.Health.Config
    if config and config.IsEnabled then
        return config.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

local function IsManualConsoleSuicide(ply, inflictor, attacker)
    if not IsValid(ply) then return false end

    local world = game.GetWorld and game.GetWorld() or NULL
    local attackerIsSelf = IsValid(attacker) and attacker == ply
    local inflictorIsSelf = IsValid(inflictor) and inflictor == ply
    local noAttacker = not IsValid(attacker)
    local noInflictor = not IsValid(inflictor)
    local worldInflict = IsValid(inflictor) and inflictor == world
    local worldAttack = IsValid(attacker) and attacker == world

    if attackerIsSelf or inflictorIsSelf then
        return true
    end

    if (noAttacker or worldAttack) and (noInflictor or worldInflict) then
        return true
    end

    return false
end

local function ClearLastStandState(ply)
    if not IsValid(ply) then return end

    local body = WoundSystem and WoundSystem.GetBody and WoundSystem.GetBody(ply)
    if body then
        body.lastStandTime = 0
    end
end

hook.Add("PlayerDeath", "WoundSystem_DeathScreenTrigger", function(ply, inflictor, attacker)
    if IsManualConsoleSuicide(ply, inflictor, attacker) then
        ClearLastStandState(ply)
    end

    if not WoundSystemHealthEnabled() then
        ply.WoundSys_CanRespawn = true
        return
    end

    ply.WoundSys_CanRespawn = false
    if WoundSystem and WoundSystem.DebugDeath then
        print("[WoundSystem Death] PlayerDeath triggered for:", tostring(ply:Nick()), "type=", deathType, "canRespawnBefore=false")
    end
    
    local deathType = "normal"
    local totalBleedSpeed = 0
    if WoundSystem and WoundSystem.GetPlayerPhysiology then
        local _, bleedSpeed = WoundSystem.GetPlayerPhysiology(ply)
        totalBleedSpeed = bleedSpeed or 0
    end
    
    if ply:WaterLevel() >= 3 then
        deathType = "drowning"
    elseif (totalBleedSpeed or 0) > 0.02 then
        deathType = "violent"
    end

    net.Start("WoundSystem_PlayerDied")
        net.WriteString(deathType)
        net.WriteUInt(WoundSystem.Health and WoundSystem.Health.GetLifecycleSeq and WoundSystem.Health.GetLifecycleSeq(ply) or 0, 24)
    net.Send(ply)
    if WoundSystem and WoundSystem.DebugDeath then
        print("[WoundSystem Death] Sent WoundSystem_PlayerDied to", tostring(ply:Nick()))
    end
end)

-- Blocks standard mouse-click / spacebar respawning
hook.Add("PlayerDeathThink", "WoundSystem_BlockRespawn", function(ply)
    if not WoundSystemHealthEnabled() then
        ply.WoundSys_CanRespawn = true
        return
    end

    if ply.WoundSys_CanRespawn == false then
        return false 
    end
end)

local function ClearDeathScreenBlocks()
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then
            ply.WoundSys_CanRespawn = true

            net.Start("WoundSystem_ClearDeathScreen")
            net.Send(ply)
        end
    end
end

if cvars and cvars.AddChangeCallback then
    cvars.AddChangeCallback("woundsys_enabled", function(_, _, newValue)
        if tostring(newValue) == "0" then
            timer.Simple(0, ClearDeathScreenBlocks)
        end
    end, "WoundSystem_DeathScreenEnabledState")
end

-- Processes the click-to-respawn request from the client
net.Receive("WoundSystem_PlayerRespawnRequest", function(len, ply)
    if IsValid(ply) and not ply:Alive() then
        ply.WoundSys_CanRespawn = true
        ply:Spawn()
    end
end)
