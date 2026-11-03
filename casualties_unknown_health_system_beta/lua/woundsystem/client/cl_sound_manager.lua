-- healthsystem/cl_sound_manager.lua
--
-- Z-City integration: the CAS3 audio manager (drones, music, heartbeat loops, critical loops, tinnitus, hearing DSP) is removed.
-- WoundSystem plays only the medical sounds of what the player applies (minigame sounds: bandage, syringe, tweezers, wrench,
-- squelch, AED ...). Everything else (pain, breathing, vomiting, ambience) is Z-City's.

WoundSystem = WoundSystem or {}

if WoundSystem.SoundManagerLoaded then return end
WoundSystem.SoundManagerLoaded = true

local cvAudioMaster = GetConVar("woundsys_audio_master")
    or CreateClientConVar("woundsys_audio_master", "1", true, false, "Loudness of the sounds of applied medical items.", 0, 2)

local function WoundSystemClientEnabled()
    local client = WoundSystem and WoundSystem.Client
    if client and client.IsEnabled then
        return client.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

-- kept as empty stubs for old callers
WoundSystem.CAS3Music = WoundSystem.CAS3Music or {}
function WoundSystem.CAS3Music.PulseThreat() end
function WoundSystem.CAS3Music.StartDrone() end
function WoundSystem.CAS3Music.StopDrone() end
function WoundSystem.CAS3Music.PlaySong() return false end
function WoundSystem.CAS3Music.StopSong() end
function WoundSystem.CAS3Music.SkipTime() return false end

net.Receive("WoundSystem_MinigameSound_Client", function()
    if not WoundSystemClientEnabled() then return end

    local ent = net.ReadEntity()
    local soundName = net.ReadString()
    local vol = net.ReadFloat() * math.Clamp(cvAudioMaster:GetFloat(), 0, 2)
    local isLoop = net.ReadBool()
    local stop = net.ReadBool()

    if not IsValid(ent) then return end

    if isLoop then
        ent.woundsys_LoopSounds = ent.woundsys_LoopSounds or {}
        if stop then
            if ent.woundsys_LoopSounds[soundName] then
                ent.woundsys_LoopSounds[soundName]:Stop()
                ent.woundsys_LoopSounds[soundName] = nil
            end
        else
            if not ent.woundsys_LoopSounds[soundName] then
                ent.woundsys_LoopSounds[soundName] = CreateSound(ent, soundName)
            end

            ent.woundsys_LoopSounds[soundName]:Play()
            ent.woundsys_LoopSounds[soundName]:ChangeVolume(vol, 0)
        end
    else
        ent:EmitSound(soundName, 65, 100, math.Clamp(vol, 0, 1))
    end
end)

function WoundSystem.BroadcastMinigameSound(soundName, volume, isLoop, stop)
    net.Start("WoundSystem_MinigameSound")
    net.WriteString(soundName)
    net.WriteFloat(volume or 0.5)
    net.WriteBool(isLoop or false)
    net.WriteBool(stop or false)
    net.SendToServer()
end
