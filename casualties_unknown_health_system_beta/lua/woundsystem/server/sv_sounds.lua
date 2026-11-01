-- healthsystem/lua/woundsystem/server/sv_sounds.lua

hook.Remove("Think", "WoundSystem_Sounds_PantLoop")
hook.Remove("Think", "WoundSystem_Sounds_TryGrowl")
hook.Remove("Think", "WoundSystem_Talker_FallScream")

WoundSystem = WoundSystem or {}

local function WoundSystemHealthEnabled()
    local config = WoundSystem and WoundSystem.Health and WoundSystem.Health.Config
    if config and config.IsEnabled then
        return config.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

local LAND_SMALL = { "body/landsmall1.ogg" }
local LAND_MEDIUM = { "body/landmedium1.ogg" }
local LAND_HEAVY = { "body/landheavy1.ogg", "body/landheavy2.ogg" }
local BODY_FALLS = {
    "body/bodyfall1.ogg",
    "body/bodyfall2.ogg",
    "body/bodyfall3.ogg",
    "body/bodyfall4.ogg",
    "body/bodyfall5.ogg"
}
local PANT_SOUND_FILE = "pant.ogg"
local PANT_THINK_INTERVAL = 0.15
local GROWL_THINK_INTERVAL = 60
local GROWLS = {
    "growl1.ogg",
    "growl2.ogg",
    "growl3.ogg",
    "growl4.ogg",
    "growl5.ogg",
    "growl6.ogg",
    "growl7.ogg",
    "growl8.ogg",
    "growl9.ogg",
    "growl10.ogg",
    "growl11.ogg"
}
local YAWNS = { "yawn1.ogg", "yawn2.ogg" }

for _, ply in ipairs(player.GetAll()) do
    if ply.woundsys_PantSound then
        ply.woundsys_PantSound:Stop()
        ply.woundsys_PantSound = nil
    end
end

local function RandomFrom(list)
    return list[math.random(#list)]
end

local function GetBody(ply)
    return WoundSystem
        and WoundSystem.Health
        and WoundSystem.Health.GetBody
        and WoundSystem.Health.GetBody(ply)
        or nil
end

local function ShouldPlayPainSound(ply)
    local serverCVar = GetConVar("woundsys_server_pain_sounds_enabled")
    if serverCVar and not serverCVar:GetBool() then return false end
    return ply:GetInfoNum("woundsys_pain_sounds_enabled", 1) == 1
end

local function ShouldPlayDeathSound(ply)
    return ply:GetInfoNum("woundsys_death_sounds_enabled", 1) == 1
end

local function ShouldPlayGrowlSound(ply)
    local serverCVar = GetConVar("woundsys_server_growl_sounds_enabled")
    if serverCVar and not serverCVar:GetBool() then return false end
    return ply:GetInfoNum("woundsys_growl_sounds_enabled", 1) == 1
end

local function StopPantSound(ply)
    if not ply then return end
    if not ply.woundsys_PantSound then return end

    ply.woundsys_PantSound:FadeOut(0.2)
    ply.woundsys_PantSound = nil
end

local function PantWaterLevel(ply, body)
    local ent = WoundSystem.GetCurrentCharacter and WoundSystem.GetCurrentCharacter(ply) or (body and IsValid(body.unconsciousRagdoll) and body.unconsciousRagdoll or ply)
    if not IsValid(ent) or not ent.WaterLevel then return 0 end

    return ent:WaterLevel()
end

local function BodyIsConscious(body)
    if not body then return false end
    if body.conscious ~= nil then return body.conscious == true end
    return not body.unconscious and (body.consciousness or 100) >= 20
end

local function BodyIsBreathing(ply, body)
    if not body then return false end
    if body.breathing ~= nil then return body.breathing == true end
    if PantWaterLevel(ply, body) >= 3 and not body.hasScubaGear then return false end
    return (body.respiratoryRate or 100) > 10
end

local function PantTarget(ply, body)
    if not BodyIsConscious(body) then return 0, 100 end

    local breathing = BodyIsBreathing(ply, body)
    local stamina = math.Clamp(tonumber(body.stamina) or 100, 0, 100)
    local inWater = PantWaterLevel(ply, body) >= 3 or body.inWater == true
    local volume = (breathing and not inWater) and math.Clamp((70 - stamina) * 0.01, 0, 1) or 0
    local pitch = breathing and math.Clamp((1.25 - stamina * 0.004) * 100, 1, 255) or 100

    return volume, pitch
end

local function UpdatePantSound(ply, body)
    if not IsValid(ply) or not ply:Alive() then
        StopPantSound(ply)
        return
    end

    local volume, pitch = PantTarget(ply, body)

    if volume <= 0.005 then
        StopPantSound(ply)
        return
    end

    if not ply.woundsys_PantSound then
        ply.woundsys_PantSound = CreateSound(ply, PANT_SOUND_FILE)
        if not ply.woundsys_PantSound then return end
        ply.woundsys_PantSound:PlayEx(0, pitch)
    end

    ply.woundsys_PantSound:ChangeVolume(volume, PANT_THINK_INTERVAL)
    ply.woundsys_PantSound:ChangePitch(pitch, PANT_THINK_INTERVAL)
end

local function TotalHappiness(ply)
    if WoundSystemHappiness and WoundSystemHappiness.Total then
        return WoundSystemHappiness.Total(ply)
    end

    return IsValid(ply) and ply:GetNWFloat("WoundSystem_Happiness", 0) or 0
end

local function TryGrowl(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if not ShouldPlayGrowlSound(ply) then return end

    local body = GetBody(ply)
    if not BodyIsConscious(body) then return end

    local happiness = TotalHappiness(ply)
    if happiness >= -15 then return end

    local chance = math.Clamp(-happiness * 0.01, 0, 1)
    if math.Rand(0, 1) >= chance then return end

    ply:EmitSound(RandomFrom(GROWLS), 62, math.random(92, 108), 0.55)
end

local PAIN_SOUNDS = {
    "body/death1.ogg",
    "body/death3.ogg",
    "body/death4.ogg",
    "body/deatth5.ogg",
    "body/exp5.ogg",
    "body/exp7.ogg",
    "body/exp6.ogg",
    "body/exp8.ogg",
    "body/exp9.ogg",
    "body/exp10.ogg",
    "body/exp11.ogg",
    "body/exp12.ogg",
    "body/exp13.ogg",
    "body/exp14.ogg",
    "body/exp15.ogg",
    "body/exp16.ogg",
    "body/exp17.ogg",
    "body/pain1.ogg"
}

local function PainValue(body)
    return math.Clamp(tonumber(body and (body.avgPain or body.averagePain)) or 0, 0, 100)
end

local function UpdatePainSound(ply, body, dt)
    if not IsValid(ply) or not ply:Alive() or not BodyIsConscious(body) then return end

    local avgPain = PainValue(body)
    ply.woundsys_PainSoundTime = ply.woundsys_PainSoundTime or 0

    if avgPain > 20 then
        if ply.woundsys_PainSoundTime < 0 then
            ply.woundsys_PainSoundTime = math.Rand(30, 50)

            if ShouldPlayPainSound(ply) then
                ply:EmitSound(RandomFrom(PAIN_SOUNDS), 80, math.random(85, 115), 1)
            end
        end

        ply.woundsys_PainSoundTime = ply.woundsys_PainSoundTime - (dt * (avgPain * 0.1))
    else
        ply.woundsys_PainSoundTime = ply.woundsys_PainSoundTime - dt
    end
end

local function UpdateYawnSound(ply, body, dt)
    if not IsValid(ply) or not ply:Alive() or not BodyIsConscious(body) then return end

    local consciousness = body.consciousness or 100
    if consciousness >= 80 then return end

    ply.woundsys_YawnTime = (ply.woundsys_YawnTime or 0) + dt
    if ply.woundsys_YawnTime > 60 then
        ply.woundsys_YawnTime = math.Rand(-20, 20)
        ply:EmitSound(RandomFrom(YAWNS), 70, math.random(85, 115), 1)
    end
end

local function TryTalkLine(ply, lineType, cooldown, force)
    if not IsValid(ply) or not WoundSystem.TalkerSayLine then return end

    local key = "woundsys_NextTalk_" .. tostring(lineType or "")
    if (ply[key] or 0) > CurTime() then return end

    if WoundSystem.TalkerSayLine(ply, lineType, nil, force) then
        ply[key] = CurTime() + (cooldown or 8)
    end
end

hook.Add("WoundSystem_OnDislocate", "WoundSystem_Sounds_Dislocate", function(ply, limbName, state)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) then return end
    ply:EmitSound("body/dislocation.ogg", 75, math.random(90, 110))
end)

hook.Add("WoundSystem_OnFracture", "WoundSystem_Sounds_Fracture", function(ply, limbName, state)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) then return end
    ply:EmitSound("body/BoneBreak" .. math.random(1, 3) .. ".ogg", 70, math.random(90, 110))
end)

hook.Add("WoundSystem_OnImpact", "WoundSystem_Sounds_Impact", function(ply, limb, force)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) then return end

    -- Headhit (tinnitus) is client-side only for the victim
    if limb == "head" and force > 5.4 then -- 3.0 * 1.8 = 5.4
        ply:SendLua("surface.PlaySound(\"body/headhit.ogg\")")
    end

    -- Body fall impacts
    if force > 3.0 then
        local body = GetBody(ply)
        if body and body.fallingRagdoll and (ply.woundsys_NextBodyFallSound or 0) < CurTime() then
            ply.woundsys_NextBodyFallSound = CurTime() + 0.25
            ply:EmitSound(RandomFrom(BODY_FALLS), 76, math.random(90, 110), 0.95)
        end
    end

end)

hook.Add("WoundSystem_OnDismember", "WoundSystem_Sounds_Dismember", function(ply, limbName)
    if not WoundSystemHealthEnabled() then return end
    if not IsValid(ply) then return end
    ply:EmitSound("body/gore" .. math.random(1, 5) .. ".ogg", 65, math.random(90, 110))
end)

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

local DRIPS = {
    "drip/drip2.ogg", "drip/drip3.ogg", "drip/drip4.ogg", "drip/drip7.ogg",
    "drip/drip11.ogg", "drip/drip15.ogg", "drip/drip16.ogg", "drip/drip17.ogg",
    "drip/drip18.ogg", "drip/drip20.ogg", "drip/drip21.ogg", "drip/drip24.ogg"
}

hook.Add("WoundSystem_OnBloodPool", "WoundSystem_Sounds_BloodPool", function(groundPos, ignoreEnt)
    if not WoundSystemHealthEnabled() then return end

    local soundName = DRIPS[math.random(#DRIPS)]
    sound.Play(soundName, groundPos, 65, math.random(90, 110), 1)
end)

timer.Create("WoundSystem_Sounds_PantLoop", PANT_THINK_INTERVAL, 0, function()
    if not WoundSystemHealthEnabled() then
        for _, ply in ipairs(player.GetAll()) do
            StopPantSound(ply)
        end
        return
    end

    local now = CurTime()
    local dt = math.Clamp(now - (WoundSystem.LastPantSoundThink or now), 0, 0.5)
    WoundSystem.LastPantSoundThink = now

    for _, ply in ipairs(player.GetAll()) do
        local body = GetBody(ply)
        UpdatePantSound(ply, body)
        UpdatePainSound(ply, body, dt)
        UpdateYawnSound(ply, body, dt)
    end
end)

timer.Create("WoundSystem_Sounds_TryGrowl", GROWL_THINK_INTERVAL, 0, function()
    if not WoundSystemHealthEnabled() then return end

    for _, ply in ipairs(player.GetAll()) do
        TryGrowl(ply)
    end
end)

hook.Add("Think", "WoundSystem_Sounds_TrackFallSpeed", function()
    if not WoundSystemHealthEnabled() then return end

    local now = CurTime()

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            if ply:IsOnGround() or ply:GetMoveType() ~= MOVETYPE_WALK then
                if (ply.woundsys_FallSpeedClearAt or 0) < now then
                    ply.woundsys_MaxFallSpeed = 0
                    ply.woundsys_FallRagdollRisk = 0
                end
            else
                local fallSpeed = math.max(-(ply:GetVelocity().z or 0), 0)
                ply.woundsys_MaxFallSpeed = math.max(ply.woundsys_MaxFallSpeed or 0, fallSpeed)
                ply.woundsys_FallRagdollRisk = math.max(
                    ply.woundsys_FallRagdollRisk or 0,
                    math.Clamp((fallSpeed - 300) / 1100, 0, 1)
                )
                ply.woundsys_FallSpeedClearAt = now + 0.45

                if fallSpeed >= 950 and (ply.woundsys_NextFallScream or 0) < now then
                    ply.woundsys_NextFallScream = now + 6
                    TryTalkLine(ply, "fallscream", 6, false)
                end
            end
        end
    end
end)

hook.Add("OnPlayerHitGround", "WoundSystem_Sounds_Land", function(ply, inWater, onFloater, speed)
    if not WoundSystemHealthEnabled() then return end
    if inWater then return end

    local body = GetBody(ply)
    local wasFallingRagdoll = body and body.fallingRagdoll
    local fallSpeed = math.max(tonumber(speed) or 0, tonumber(ply.woundsys_MaxFallSpeed) or 0)
    local ragdollRisk = math.max(ply.woundsys_FallRagdollRisk or 0, math.Clamp((fallSpeed - 300) / 1100, 0, 1))
    local volume = math.Clamp(0.55 + (fallSpeed / 1100) + (ragdollRisk * 0.25), 0.55, 1)
    local pitch = math.Clamp(108 - (ragdollRisk * 18) + math.random(-4, 4), 86, 112)

    ply.woundsys_MaxFallSpeed = 0
    ply.woundsys_FallRagdollRisk = 0
    ply.woundsys_FallSpeedClearAt = CurTime() + 0.15

    if wasFallingRagdoll then
        if (ply.woundsys_NextBodyFallSound or 0) < CurTime() then
            ply.woundsys_NextBodyFallSound = CurTime() + 0.25
            ply:EmitSound(RandomFrom(BODY_FALLS), 78, pitch, volume)
        end
        return
    end

    if fallSpeed >= 980 or ragdollRisk >= 0.62 then
        ply:EmitSound(RandomFrom(LAND_HEAVY), 76, pitch, volume)
        TryTalkLine(ply, "hitgroundhard", 8, false)
    elseif fallSpeed >= 520 or ragdollRisk >= 0.22 then
        ply:EmitSound(RandomFrom(LAND_MEDIUM), 72, pitch, volume)
    elseif fallSpeed > 80 then
        ply:EmitSound(RandomFrom(LAND_SMALL), 66, math.Clamp(pitch + 6, 92, 116), volume * 0.85)
    end
end)

local DEATHS = { "body/death1.ogg", "body/death3.ogg", "body/death4.ogg" }

hook.Add("DoPlayerDeath", "WoundSystem_Sounds_Death", function(ply, attacker, dmginfo)
    StopPantSound(ply)
    if not WoundSystemHealthEnabled() then return end

    if ShouldPlayDeathSound(ply) then
        local soundName = DEATHS[math.random(#DEATHS)]
        ply:EmitSound(soundName, 85, math.random(95, 105))
    end
end)

hook.Add("PlayerDisconnected", "WoundSystem_Sounds_StopPant", StopPantSound)
hook.Add("ShutDown", "WoundSystem_Sounds_StopAllPant", function()
    for _, ply in ipairs(player.GetAll()) do
        StopPantSound(ply)
    end
end)
