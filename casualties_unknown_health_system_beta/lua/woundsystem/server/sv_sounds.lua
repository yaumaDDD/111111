-- healthsystem/lua/woundsystem/server/sv_sounds.lua
--
-- Z-City integration. WoundSystem keeps only the medical sounds of applied items (the minigame sounds relayed below, the
-- pill sound in sv_cas3_bodyfeel.lua, the syringe / tweezers / wrench / squelch sounds in sv_health.lua).
-- Removed: pain / death / growl / yawn vocalizations, panting, fall screams, landing / body-fall sounds, head-hit tinnitus,
-- blood drips, talker lines. Bones and amputations use Z-City sounds.

hook.Remove("Think", "WoundSystem_Sounds_PantLoop")
hook.Remove("Think", "WoundSystem_Sounds_TryGrowl")
hook.Remove("Think", "WoundSystem_Talker_FallScream")
hook.Remove("Think", "WoundSystem_Sounds_TrackFallSpeed")
hook.Remove("OnPlayerHitGround", "WoundSystem_Sounds_Land")
hook.Remove("DoPlayerDeath", "WoundSystem_Sounds_Death")
timer.Remove("WoundSystem_Sounds_PantLoop")
timer.Remove("WoundSystem_Sounds_TryGrowl")

WoundSystem = WoundSystem or {}

local function WoundSystemHealthEnabled()
    local config = WoundSystem and WoundSystem.Health and WoundSystem.Health.Config
    if config and config.IsEnabled then
        return config.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

-- Z-City sounds (the same files Z-City plays for its own bones / amputations)
hook.Add("WoundSystem_OnDislocate", "WoundSystem_Sounds_Dislocate", function(ply, limbName, state)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) then return end
    ply:EmitSound("bones/bone" .. math.random(8) .. ".mp3", 75, 100, 1, CHAN_AUTO)
end)

hook.Add("WoundSystem_OnFracture", "WoundSystem_Sounds_Fracture", function(ply, limbName, state)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) then return end
    ply:EmitSound("bones/bone" .. math.random(8) .. ".mp3", 75, 100, 1, CHAN_AUTO)
end)

hook.Add("WoundSystem_OnDismember", "WoundSystem_Sounds_Dismember", function(ply, limbName)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) then return end
    ply:EmitSound("player/zombie_head_explode_0" .. math.random(6) .. ".wav", 70, math.random(95, 105), 1)
end)

-- the sounds of the medical minigames (what the player does while applying an item) are relayed to the other players
util.AddNetworkString("WoundSystem_MinigameSound")
util.AddNetworkString("WoundSystem_MinigameSound_Client")

net.Receive("WoundSystem_MinigameSound", function(len, ply)
    if not WoundSystemHealthEnabled() then return end

    local soundName = net.ReadString()
    local volume = net.ReadFloat()
    local isLoop = net.ReadBool()
    local stop = net.ReadBool()

    net.Start("WoundSystem_MinigameSound_Client")
    net.WriteEntity(ply)
    net.WriteString(soundName)
    net.WriteFloat(volume)
    net.WriteBool(isLoop)
    net.WriteBool(stop)
    net.SendOmit(ply)
end)
