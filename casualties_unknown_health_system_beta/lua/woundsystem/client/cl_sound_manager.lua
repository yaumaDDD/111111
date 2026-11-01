-- healthsystem/cl_sound_manager.lua

WoundSystem = WoundSystem or {}

local function ClientConVar(name, default, help, min, max)
    local existing = GetConVar(name)
    if existing then return existing end

    return CreateClientConVar(name, tostring(default), true, false, help or "", min, max)
end

local cvAudioMaster = ClientConVar("woundsys_audio_master", "1", "Master volume for WoundSystem looping medical audio.", 0, 2)
local cvMusicEnabled = ClientConVar("woundsys_music_enabled", "1", "Enable the CAS3-style WoundSystem music manager.", 0, 1)
local cvMusicVolume = ClientConVar("woundsys_music_volume", "0.45", "CAS3 music song volume.", 0, 1)
local cvDroneVolume = ClientConVar("woundsys_music_drone_volume", "1", "CAS3 medical drone volume.", 0, 1)
local cvSadnessDistortion = ClientConVar("woundsys_music_sadness_distortion", "1", "Approximate CAS3 sadness mixer distortion.", 0, 1)
local cvTinnitusVolume = ClientConVar("woundsys_tinnitus_volume", "1.0", "Volume multiplier for deafened tinnitus ringing SFX.", 0, 2)

local function WoundSystemClientEnabled()
    local client = WoundSystem and WoundSystem.Client
    if client and client.IsEnabled then
        return client.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

if WoundSystem.SoundManagerLoaded then return end
WoundSystem.SoundManagerLoaded = true

local function SoundPathExists(path)
    return isstring(path) and path ~= "" and file.Exists(path, "GAME")
end

local function ResolveSoundPath(paths, required)
    for _, path in ipairs(paths or {}) do
        if SoundPathExists(path) then return path end
    end

    if required and paths and paths[1] then
        return paths[#paths]
    end
end

local function SurfaceSoundName(path)
    return string.Replace(tostring(path or ""), "sound/", "")
end

local function VolumeCVar(cvar, fallback, minValue, maxValue)
    if not cvar then return fallback end

    return math.Clamp(cvar:GetFloat(), minValue or 0, maxValue or 1)
end

local function Remap(val, inMin, inMax, outMin, outMax)
    return outMin + (val - inMin) * (outMax - outMin) / (inMax - inMin)
end

local function RemapClamped(val, inMin, inMax, outMin, outMax)
    if inMax == inMin then return outMin end

    return math.Clamp(Remap(val, inMin, inMax, outMin, outMax), math.min(outMin, outMax), math.max(outMin, outMax))
end

local soundTracks = {
    tinnitus = ResolveSoundPath({"sound/tinnitus.ogg", "sound/tinnitus.ogg"}, true),
    critical = ResolveSoundPath({"sound/criticalloop.ogg", "sound/criticalloop.ogg"}, true),
    unconscious = ResolveSoundPath({"sound/criticalloop-unconscious.ogg", "sound/criticalloop-unconscious.ogg"}, true),
    brainDying = ResolveSoundPath({"sound/music/DrawYourLastBreath1.ogg", "sound/dying.ogg"}, true),
    dead = ResolveSoundPath({"sound/music/DrawYourLastBreath2.ogg", "sound/death.ogg"}, true)
}

local function DronePath(exactName, fallbackName)
    local paths = {"sound/music/" .. exactName}
    if fallbackName then
        paths[#paths + 1] = "sound/" .. fallbackName
    end

    return ResolveSoundPath(paths, fallbackName ~= nil)
end

local DroneTracks = {
    {casIndex = 0, id = "pain", path = DronePath("PainDrone.ogg", "paindrone.ogg"), fadeIn = 8, fadeOut = 10},
    {casIndex = 1, id = "dying", path = DronePath("isthistheend.ogg", "isthistheend.ogg"), fadeIn = 14, fadeOut = 10},
    {casIndex = 2, id = "stamina", path = DronePath("exhausted.ogg", "exhaustedloop.ogg"), fadeIn = 14, fadeOut = 10},
    {casIndex = 3, id = "tired", path = DronePath("tired.ogg", "exhaustedloop.ogg"), fadeIn = 14, fadeOut = 10},
    {casIndex = 4, id = "radiation", path = DronePath("Biohazard.ogg"), fadeIn = 14, fadeOut = 10},
    {casIndex = 5, id = "threat_spider", path = DronePath("SpidersInTheDark.ogg"), fadeIn = 2, fadeOut = 10},
    {casIndex = 6, id = "sadness", path = DronePath("despair.ogg", "paindroneother.ogg"), fadeIn = 14, fadeOut = 20},
    {casIndex = 7, id = "threat_hostile", path = DronePath("HostileEncounter.ogg"), fadeIn = 4, fadeOut = 10},
    {casIndex = 8, id = "drowning", path = DronePath("drowning.ogg"), fadeIn = 14, fadeOut = 4},
    {casIndex = 9, id = "threat_hundreds", path = DronePath("TheresHundreds.ogg"), fadeIn = 2, fadeOut = 10},
    {casIndex = 10, id = "threat_run", path = DronePath("RUN_FOR_YOUR_LIFE.ogg"), fadeIn = 2, fadeOut = 10},
    {casIndex = 11, id = "threat_cold", path = DronePath("CombatInTheCold.ogg"), fadeIn = 4, fadeOut = 10},
    {casIndex = 12, id = "threat_murder", path = DronePath("amurderofyourown.ogg"), fadeIn = 1, fadeOut = 14},
    {casIndex = 13, id = "earthquake", path = DronePath("CaveIn.ogg"), fadeIn = 14, fadeOut = 10},
    {casIndex = 14, id = "radline", path = DronePath("radlinepulse.ogg"), fadeIn = 14, fadeOut = 10},
    {casIndex = 15, id = "threat_chase", path = DronePath("CHASE_IT_DOWN.ogg"), fadeIn = 2, fadeOut = 10},
    {casIndex = 16, id = "trader", path = DronePath("FamiliarFace.ogg"), fadeIn = 2, fadeOut = 1},
    {casIndex = 17, id = "threat_simulacrum", path = DronePath("ThreatSimulacrum.ogg"), fadeIn = 2, fadeOut = 5},
    {casIndex = 18, id = "threat_paranormal", path = DronePath("paranormalthreat.ogg"), fadeIn = 2, fadeOut = 3}
}

local DroneByCasIndex = {}
for _, track in ipairs(DroneTracks) do
    DroneByCasIndex[track.casIndex] = track
end

local AudioChannels = {}
local AudioSpecs = {}
local ActiveTinnitusStation = nil
local IsAudioInitialized = false
local InitializationGracePeriod = CurTime() + 2
local HasPlayedDeadSong = false
local CurrentHearingDSP = 0
local HearingSpikeWindowStartLoss = 0
local HearingSpikeWindowStartAt = 0
local LastMuffleTinnitusAt = 0
local AudioMuted = false
local ThreatDroneIndex = nil
local ThreatUntil = 0
local ForcedDrones = {}
local SongChannel = nil
local SongKey = nil
local SongPath = nil
local SongLoading = false
local SongRequestSerial = 0
local LastFrameAt = CurTime()
local LowCutoff = 30000
local MaxDroneAmount = 0
local PlayTinnitusOnce

local TINNITUS_SPIKE_AMOUNT = 10
local TINNITUS_SPIKE_WINDOW = 3
local TINNITUS_MUFFLE_TRANSITION_COOLDOWN = 0.4

local HearingDSPLevels = {
    {min = 75, dsp = 34},
    {min = 50, dsp = 33},
    {min = 25, dsp = 32},
    {min = 5, dsp = 31}
}

local function StopAudioChannel(station)
    if not IsValid(station) then return end

    pcall(function()
        station:Stop()
    end)
end

local function ApplyPlayerHearingDSP(ply, dspSeverity, tinnitusSeverity)
    if not IsValid(ply) or not ply.SetDSP then return end

    local severity = math.Clamp((dspSeverity or 0) * 100, 0, 100)
    local targetDSP = 0
    for _, level in ipairs(HearingDSPLevels) do
        if severity >= level.min then
            targetDSP = level.dsp
            break
        end
    end

    if targetDSP ~= CurrentHearingDSP then
        ply:SetDSP(targetDSP, false)

        if targetDSP > 0 and PlayTinnitusOnce and (tinnitusSeverity or 0) > 0.05 and CurTime() - LastMuffleTinnitusAt >= TINNITUS_MUFFLE_TRANSITION_COOLDOWN then
            local tinnitusVolume = Lerp(math.Clamp((severity - 5) / 95, 0, 1), 0.55, 1.2)
            PlayTinnitusOnce(tinnitusVolume)
            LastMuffleTinnitusAt = CurTime()
        end

        CurrentHearingDSP = targetDSP
    end
end

PlayTinnitusOnce = function(volume)
    volume = math.Clamp(volume or 1, 0, 1.4) * VolumeCVar(cvAudioMaster, 1, 0, 2) * VolumeCVar(cvTinnitusVolume, 1, 0, 2)

    StopAudioChannel(ActiveTinnitusStation)
    ActiveTinnitusStation = nil

    if volume <= 0.001 then return end

    sound.PlayFile(soundTracks.tinnitus, "noblock noplay 2d", function(station, errCode, errStr)
        if IsValid(station) then
            ActiveTinnitusStation = station
            station:EnableLooping(false)
            station:SetVolume(volume)
            station:SetPlaybackRate(1)

            if not pcall(function() station:Play() end) then
                ActiveTinnitusStation = nil
                surface.PlaySound(SurfaceSoundName(soundTracks.tinnitus))
            end
        else
            surface.PlaySound(SurfaceSoundName(soundTracks.tinnitus))
            print("[WoundSystem] AUDIO ERROR: failed to play tinnitus: " .. tostring(errCode) .. " | " .. tostring(errStr))
        end
    end)
end

local function LoadTrack(name, path, spec)
    if not path then return end

    AudioSpecs[name] = spec or {}
    sound.PlayFile(path, "noblock noplay 2d", function(station, errCode, errStr)
        if IsValid(station) then
            station:EnableLooping(true)
            station:SetVolume(0)
            station:SetPlaybackRate(1)
            station:Play()
            AudioChannels[name] = station
        else
            print("[WoundSystem] AUDIO ERROR: failed to load " .. tostring(name) .. " from " .. tostring(path))
            print("Error Code: " .. tostring(errCode) .. " | " .. tostring(errStr))
        end
    end)
end

local function StopSong()
    SongRequestSerial = SongRequestSerial + 1
    StopAudioChannel(SongChannel)
    SongChannel = nil
    SongKey = nil
    SongPath = nil
    SongLoading = false
end

local function PlaySong(path, key)
    if not path then return false end

    if SongKey == key and IsValid(SongChannel) and SongChannel:GetState() == GMOD_CHANNEL_PLAYING then
        return true
    end

    StopSong()
    SongLoading = true
    SongRequestSerial = SongRequestSerial + 1
    local requestSerial = SongRequestSerial

    sound.PlayFile(path, "noblock noplay 2d", function(station, errCode, errStr)
        if requestSerial ~= SongRequestSerial then
            StopAudioChannel(station)
            return
        end

        SongLoading = false

        if IsValid(station) then
            SongChannel = station
            SongKey = key
            SongPath = path
            station:EnableLooping(false)
            if key == "dead" or key == "brain_dying" then
                station:SetVolume(VolumeCVar(cvAudioMaster, 1, 0, 2) * VolumeCVar(cvMusicVolume, 0.45, 0, 1))
            else
                station:SetVolume(0)
            end
            station:SetPlaybackRate(1)
            station:Play()
        else
            if key == "dead" or key == "brain_dying" then
                surface.PlaySound(SurfaceSoundName(path))
            end

            print("[WoundSystem] AUDIO ERROR: failed to play song " .. tostring(path) .. ": " .. tostring(errCode) .. " | " .. tostring(errStr))
        end
    end)

    return true
end

local function InitializeAudioEngine()
    if IsAudioInitialized then return end
    IsAudioInitialized = true

    for _, station in pairs(AudioChannels) do
        StopAudioChannel(station)
    end

    AudioChannels = {}
    AudioSpecs = {}

    for _, track in ipairs(DroneTracks) do
        LoadTrack(track.id, track.path, track)
    end

    LoadTrack("critical", soundTracks.critical, {fadeIn = 2, fadeOut = 2})
    LoadTrack("unconscious", soundTracks.unconscious, {fadeIn = 2, fadeOut = 2})
end

local function SilenceAllAudio(stopSong)
    for _, station in pairs(AudioChannels) do
        if IsValid(station) then
            station:SetVolume(0)
            station:SetPlaybackRate(1)
        end
    end

    if stopSong then
        StopSong()
    elseif IsValid(SongChannel) then
        SongChannel:SetVolume(0)
    end
end

hook.Add("InitPostEntity", "HealthSystem_InitAudio", InitializeAudioEngine)
if IsValid(LocalPlayer()) then InitializeAudioEngine() end

local function ResetPlayerAudioState(ply)
    if not IsValid(ply) or ply ~= LocalPlayer() then return end
    if hg and hg.override and hg.override[ply] then return end -- Z-City fake-ragdoll get-up, not a real respawn

    CurrentHearingDSP = 0
    if ply.SetDSP then
        ply:SetDSP(0, false)
    end

    LowCutoff = 30000
    HearingSpikeWindowStartLoss = 0
    HearingSpikeWindowStartAt = 0
    LastMuffleTinnitusAt = 0
    HasPlayedDeadSong = false

    StopAudioChannel(ActiveTinnitusStation)
    ActiveTinnitusStation = nil
    RunConsoleCommand("stopsound")
end

hook.Add("PlayerSpawn", "HealthSystem_AudioResetOnSpawn", ResetPlayerAudioState)
hook.Add("PlayerDeath", "HealthSystem_AudioResetOnDeath", function(victim)
    if victim == LocalPlayer() then
        StopAudioChannel(ActiveTinnitusStation)
        ActiveTinnitusStation = nil
        RunConsoleCommand("stopsound")
    end
end)

local function SetDroneTarget(targets, casIndex, amount)
    local track = DroneByCasIndex[casIndex]
    if not track or not track.path then return end

    targets[track.id] = math.max(targets[track.id] or 0, math.Clamp(amount or 0, 0, 1))
end

local function CalculateTotalBleed(cardio)
    local total = cardio and cardio.totalBleedSpeed
    if total ~= nil then return total end

    total = 0
    if WoundSystemClientState and WoundSystemClientState.PlayerLimbs then
        for _, limbState in pairs(WoundSystemClientState.PlayerLimbs) do
            total = total + (limbState.bleed or 0)
        end
    end

    return total
end

local function GetTotalHappiness(ply)
    local state = WoundSystemClientState
    if state and state.Happiness ~= nil then
        return state.Happiness
    end

    if IsValid(ply) then
        return ply:GetNWFloat("WoundSystem_Happiness", 0)
    end

    return 0
end

local function BuildBodyAudioState(ply, cardio)
    cardio = cardio or {}

    local bloodOxygen = cardio.bloodOxygen or 100
    local bloodPressure = cardio.bloodPressure or 120
    local bloodVolume = cardio.bloodVolume or 100
    local consciousness = cardio.consciousness or 100
    local brainHealth = cardio.brainHealth or 100
    local heartRate = cardio.heartRate or 70
    local fibrillationProgress = cardio.fibrillationProgress or 0
    local temperature = cardio.temperature or 37
    local septicShock = cardio.septicShock or 0
    local strokeAmount = cardio.strokeAmount or 0
    local totalBleedSpeed = CalculateTotalBleed(cardio)
    local fibrillationRising = bloodOxygen < 60
        or bloodPressure < 88
        or heartRate > 200
        or (cardio.bloodViscosity or 0) > 80
        or temperature < 28.5
    local brainDying = bloodPressure < 10 and consciousness < 5
    local isDying = totalBleedSpeed > 0.134
        or (totalBleedSpeed > 0.02 and bloodVolume < 40)
        or septicShock > 75
        or temperature > 41
        or temperature < 29
        or (cardio.radiationSickness or 0) > 60
        or (fibrillationProgress > 1 and fibrillationRising)
        or bloodPressure < 80
        or bloodPressure > 170
        or bloodOxygen < 65
        or cardio.hasPulmonaryEmbolism
        or strokeAmount > 50
        or brainHealth <= 10
    local isCriticallyDying = (totalBleedSpeed > 0.02 and bloodVolume < 30)
        or bloodOxygen < 50
        or septicShock > 82.5
        or temperature < 27
        or temperature > 41.5
        or fibrillationProgress > 60
        or bloodPressure < 70

    return {
        alive = IsValid(ply) and ply:Alive(),
        mindWipe = cardio.mindWipe or false,
        conscious = not (cardio.unconscious or consciousness < 20),
        unconscious = cardio.unconscious or consciousness < 20,
        submerged = IsValid(ply) and ply.WaterLevel and ply:WaterLevel() >= 3,
        pain = math.Clamp(math.max(cardio.avgPain or 0, WoundSystem.MultiplayerFeedback and WoundSystem.MultiplayerFeedback.GetPainBoost and WoundSystem.MultiplayerFeedback.GetPainBoost() or 0), 0, 100),
        stamina = cardio.stamina or 100,
        energy = cardio.energy or 100,
        bloodOxygen = bloodOxygen,
        heartRate = heartRate,
        brainDying = brainDying,
        isDying = isDying,
        isCriticallyDying = isCriticallyDying,
        radiationSickness = cardio.radiationSickness or 0,
        earthquakeIntensity = WoundSystem.CAS3Music and WoundSystem.CAS3Music.EarthquakeIntensity or 0,
        radiationLineAmount = WoundSystem.CAS3Music and WoundSystem.CAS3Music.RadiationLineAmount or 0,
        traderOpen = WoundSystem.CAS3Music and WoundSystem.CAS3Music.TraderOpen or false,
        totalHappiness = GetTotalHappiness(ply),
        hearingLoss = cardio.hearingLoss or 0
    }
end

local function BuildDroneTargets(state)
    local targets = {}

    if state.pain > 60 then
        SetDroneTarget(targets, 0, RemapClamped(state.pain, 60, 85, 0.2, 1))
    end

    if state.totalHappiness <= -81.5 then
        SetDroneTarget(targets, 6, 1)
    elseif state.isDying then
        SetDroneTarget(targets, 1, 1)
    end

    if state.stamina < 50 then
        SetDroneTarget(targets, 2, 1 - state.stamina * 0.02)
    end

    if state.energy < 25 then
        SetDroneTarget(targets, 3, 1 - state.energy * 0.04)
    end

    if state.radiationSickness > 0 then
        SetDroneTarget(targets, 4, math.Clamp((state.radiationSickness / 100) * 3.5, 0, 1))
    end

    if ThreatDroneIndex and CurTime() < ThreatUntil then
        SetDroneTarget(targets, ThreatDroneIndex, 1)
    end

    for casIndex, amount in pairs(ForcedDrones) do
        SetDroneTarget(targets, casIndex, amount)
    end

    if state.submerged and state.bloodOxygen < 60 then
        SetDroneTarget(targets, 8, RemapClamped(state.bloodOxygen, 60, 20, 0, 1))
    end

    if state.earthquakeIntensity > 0 then
        SetDroneTarget(targets, 13, state.earthquakeIntensity)
    end

    if state.radiationLineAmount > 0 then
        SetDroneTarget(targets, 14, state.radiationLineAmount)
    end

    if state.traderOpen then
        SetDroneTarget(targets, 16, 1)
    end

    return targets
end

local function ProcessLoop(name, targetVolume, dt, rate, sadAmount)
    local station = AudioChannels[name]
    if station ~= nil and not IsValid(station) then
        AudioChannels[name] = nil
        IsAudioInitialized = false
        return
    end

    if not IsValid(station) then return end

    local spec = AudioSpecs[name] or {}
    local current = station:GetVolume()
    local fade = targetVolume > current and (spec.fadeIn or 14) or (spec.fadeOut or 10)
    local volume = math.Approach(current, math.Clamp(targetVolume or 0, 0, 2), dt / math.max(fade, 0.05))

    if station:GetState() ~= GMOD_CHANNEL_PLAYING and volume > 0.001 then
        station:Play()
    end

    station:SetVolume(volume)
    station:SetPlaybackRate(math.Clamp((rate or 1) * (1 - (sadAmount or 0) * 0.04), 0.78, 1.08))

    if volume <= 0 and station:GetState() == GMOD_CHANNEL_PLAYING then
        station:Pause()
    end
end

local function IsCriticalAudioLoopState(state)
    if not state or not state.alive then return false end
    if state.brainDying then return false end
    return state.isCriticallyDying == true and (state.heartRate or 0) > 5
end

local function ProcessCriticalLoops(state, dt, droneVolume, rate, sadAmount)
    local criticalTarget = 0
    local unconsciousTarget = 0

    if IsCriticalAudioLoopState(state) then
        if state.conscious then
            criticalTarget = droneVolume
        else
            unconsciousTarget = droneVolume
        end
    end

    ProcessLoop("critical", criticalTarget, dt, rate, sadAmount)
    ProcessLoop("unconscious", unconsciousTarget, dt, state.conscious and rate or rate * 0.9, sadAmount)
end

local function ProcessDrones(targets, state, dt, droneVolume, rate, sadAmount)
    local nextMax = 0

    for _, track in ipairs(DroneTracks) do
        local target = 0
        if state.alive and not state.brainDying and not state.mindWipe then
            target = (targets[track.id] or 0) * droneVolume
        end

        ProcessLoop(track.id, target, dt, rate, sadAmount)

        local station = AudioChannels[track.id]
        if IsValid(station) and droneVolume > 0.01 then
            nextMax = math.max(nextMax, station:GetVolume() / droneVolume)
        end
    end

    MaxDroneAmount = math.Clamp(nextMax, 0, 1)
end

local function UpdateLowCutoff(state, dt)
    local awakeOrTerminal = (state.conscious and not state.submerged) or state.brainDying or not state.alive
    local target = awakeOrTerminal and Lerp(MaxDroneAmount, 30000, 250) or Lerp(MaxDroneAmount, 300, 250)
    local speed = awakeOrTerminal and 4000 or 8000
    LowCutoff = math.Approach(LowCutoff, target, dt * speed)

    return 1 - math.Clamp((LowCutoff - 250) / (30000 - 250), 0, 1)
end

local function UpdateSong(state, dt, musicVolume, rate, sadAmount)
    local playing = IsValid(SongChannel) and SongChannel:GetState() == GMOD_CHANNEL_PLAYING

    if state.alive and state.brainDying then
        if SongKey ~= "brain_dying" or not playing then
            PlaySong(soundTracks.brainDying, "brain_dying")
        end
    elseif not state.alive and not HasPlayedDeadSong then
        HasPlayedDeadSong = true
        PlaySong(soundTracks.dead, "dead")
    elseif state.alive and (SongKey == "brain_dying" or SongKey == "dead") then
        StopSong()
    end

    if HasPlayedDeadSong and state.alive then
        HasPlayedDeadSong = false
    end

    if not IsValid(SongChannel) then return end

    local targetVolume = musicVolume * (1 - MaxDroneAmount * 0.85)
    if SongKey == "dead" or SongKey == "brain_dying" then
        targetVolume = musicVolume
    elseif not state.alive or state.mindWipe then
        targetVolume = 0
    end

    local wobble = 1 - sadAmount * 0.08 + math.sin(CurTime() * 0.8) * sadAmount * 0.03
    local songFadeTime = (SongKey == "dead" or SongKey == "brain_dying") and 0.15 or 1.5
    SongChannel:SetVolume(math.Approach(SongChannel:GetVolume(), math.Clamp(targetVolume * wobble, 0, 2), dt / songFadeTime))
    SongChannel:SetPlaybackRate(math.Clamp(rate * (1 - sadAmount * 0.06), 0.78, 1.05))
end

WoundSystem.CAS3Music = WoundSystem.CAS3Music or {}

function WoundSystem.CAS3Music.PulseThreat(casIndex, duration)
    ThreatDroneIndex = math.Clamp(math.floor(tonumber(casIndex) or 7), 0, 18)
    ThreatUntil = CurTime() + math.max(tonumber(duration) or 5, 0.1)
end

function WoundSystem.CAS3Music.StartDrone(casIndex, amount)
    ForcedDrones[math.Clamp(math.floor(tonumber(casIndex) or 0), 0, 18)] = math.Clamp(tonumber(amount) or 1, 0, 1)
end

function WoundSystem.CAS3Music.StopDrone(casIndex)
    ForcedDrones[math.Clamp(math.floor(tonumber(casIndex) or 0), 0, 18)] = nil
end

function WoundSystem.CAS3Music.PlaySong(path, key)
    return PlaySong(path, key or path)
end

function WoundSystem.CAS3Music.StopSong()
    StopSong()
end

function WoundSystem.CAS3Music.SkipTime(amount)
    if not IsValid(SongChannel) or SongChannel:GetState() ~= GMOD_CHANNEL_PLAYING then return false end

    local ok = pcall(function()
        local newTime = math.max((SongChannel:GetTime() or 0) + (tonumber(amount) or 0), 0)
        SongChannel:SetTime(newTime)
    end)

    return ok
end

hook.Add("Think", "HealthSystem_AudioCrossfade", function()
    local ply = LocalPlayer()
    local now = CurTime()
    local dt = math.Clamp(now - LastFrameAt, 0, 0.1)
    LastFrameAt = now

    if not IsValid(ply) or now < InitializationGracePeriod then return end

    if not WoundSystemClientEnabled() or not cvMusicEnabled:GetBool() then
        SilenceAllAudio(true)
        ApplyPlayerHearingDSP(ply, 0, 0)
        AudioMuted = true
        return
    end

    InitializeAudioEngine()

    local master = VolumeCVar(cvAudioMaster, 1, 0, 2)
    if master <= 0.001 then
        if not AudioMuted then
            SilenceAllAudio(false)
            AudioMuted = true
        end

        ApplyPlayerHearingDSP(ply, 0, 0)
        return
    end
    AudioMuted = false

    local cardio = WoundSystemClientState and WoundSystemClientState.Cardio
    local state = BuildBodyAudioState(ply, cardio)
    local hearingSeverity = math.Clamp((state.hearingLoss or 0) / 100, 0, 1)
    local nowReal = CurTime()

    if HearingSpikeWindowStartAt <= 0 or (nowReal - HearingSpikeWindowStartAt) > TINNITUS_SPIKE_WINDOW or state.hearingLoss < HearingSpikeWindowStartLoss then
        HearingSpikeWindowStartLoss = state.hearingLoss
        HearingSpikeWindowStartAt = nowReal
    end

    local spikeAmount = state.hearingLoss - HearingSpikeWindowStartLoss
    if spikeAmount >= TINNITUS_SPIKE_AMOUNT then
        local tinnitusVolume = math.Clamp(Remap(spikeAmount, TINNITUS_SPIKE_AMOUNT, 35, 0.7, 1.4), 0.7, 1.4)
        PlayTinnitusOnce(tinnitusVolume)
        LastMuffleTinnitusAt = nowReal
        HearingSpikeWindowStartLoss = state.hearingLoss
        HearingSpikeWindowStartAt = nowReal
    end

    local musicLowpassSeverity = UpdateLowCutoff(state, dt)
    ApplyPlayerHearingDSP(ply, math.max(hearingSeverity, musicLowpassSeverity * 0.85), hearingSeverity)

    local musicVolume = master * VolumeCVar(cvMusicVolume, 0.45, 0, 1)
    local droneVolume = master * VolumeCVar(cvDroneVolume, 1, 0, 1)
    local sadAmount = cvSadnessDistortion:GetBool() and math.Clamp(0 - state.totalHappiness, 0, 100) * 0.01 or 0
    local muffledRate = 1 - math.max(hearingSeverity * 0.18, musicLowpassSeverity * 0.08)

    UpdateSong(state, dt, musicVolume, muffledRate, sadAmount)
    ProcessDrones(BuildDroneTargets(state), state, dt, droneVolume, muffledRate, sadAmount)
    ProcessCriticalLoops(state, dt, droneVolume, muffledRate, sadAmount)
end)

net.Receive("WoundSystem_MinigameSound_Client", function()
    if not WoundSystemClientEnabled() then return end

    local ent = net.ReadEntity()
    local soundName = net.ReadString()
    local vol = net.ReadFloat()
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
        ent:EmitSound(soundName, 65, 100, vol)
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
