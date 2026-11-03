WoundSystem = WoundSystem or {}
WoundSystem.Health = WoundSystem.Health or {}

local Config = WoundSystem.Health.Config or {}
WoundSystem.Health.Config = Config

local CVAR_FLAGS = {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}
local ENABLED_CVAR_FLAGS = {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}
local CHAT_CVAR_FLAGS = {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}

local CVars = Config.CVars or {}
Config.CVars = CVars

local function CreateOrGetConVar(name, default, flags, help, minValue, maxValue)
    return GetConVar(name) or CreateConVar(name, default, flags, help, minValue, maxValue)
end

CVars.Enabled = CreateOrGetConVar("woundsys_enabled", "1", ENABLED_CVAR_FLAGS, "Enable the C:U Health System.", 0, 1)
CVars.LimbTick = CreateOrGetConVar("woundsys_limb_tick_interval", "0.1", CVAR_FLAGS, "Limb physiology tick interval in seconds.", 0.1, 2)
CVars.CardioTick = CreateOrGetConVar("woundsys_cardio_tick_interval", "0.25", CVAR_FLAGS, "Cardio-lite tick interval in seconds.", 0.1, 2)
CVars.DislocationHealSpeed = CreateOrGetConVar("woundsys_dislocation_heal_speed", "0.07", CVAR_FLAGS, "Dislocation recovery speed per second.", 0.001, 5)
CVars.BoneHealSpeed = CreateOrGetConVar("woundsys_bone_heal_speed", "0.043", CVAR_FLAGS, "Fracture recovery speed per second.", 0.001, 5)
CVars.NaturalBleedSlowLiters = CreateOrGetConVar("woundsys_natural_bleed_slow_lpm", "0.027", CVAR_FLAGS, "Natural bleed-rate slowdown in L/min for limbs without shrapnel.", 0, 5)
CVars.FibrillationRise = CreateOrGetConVar("woundsys_fibrillation_rise_rate", "1", CVAR_FLAGS, "Fibrillation rise rate per second.", 0, 10)
CVars.FibrillationDecay = CreateOrGetConVar("woundsys_fibrillation_decay_rate", "0.75", CVAR_FLAGS, "Fibrillation decay rate per second.", 0, 10)
CVars.ShrapnelInputHz = CreateOrGetConVar("woundsys_shrapnel_input_hz", "20", CVAR_FLAGS, "Max accepted client shrapnel inputs per second.", 5, 60)
CVars.HealingRate = CreateOrGetConVar("woundsys_healing_rate", "1", CVAR_FLAGS, "Multiplier for limb muscle regeneration (C# healingrate).", 0, 10)
CVars.BleedRate = CreateOrGetConVar("woundsys_bleed_rate", "1", CVAR_FLAGS, "Multiplier for limb bleed speed (C# bleedrate).", 0, 10)
CVars.StrokesEnabled = CreateOrGetConVar("woundsys_strokes_enabled", "1", CVAR_FLAGS, "Enable hypertensive stroke simulation.", 0, 1)
CVars.TemperatureEnabled = CreateOrGetConVar("woundsys_temperature_enabled", "1", CVAR_FLAGS, "Enable body temperature simulation (hypothermia and overheating).", 0, 1)
CVars.MapSuffocationEnabled = CreateOrGetConVar("woundsys_map_suffocation_enabled", "1", CVAR_FLAGS, "Treat HL2 map oxygen/trigger_hurt suffocation as WoundSystem suffocation.", 0, 1)
CVars.MapSuffocationScale = CreateOrGetConVar("woundsys_map_suffocation_scale", "1", CVAR_FLAGS, "Multiplier for map suffocation damage routed into cardio.", 0, 10)
CVars.GunshotHearingEnabled = CreateOrGetConVar("woundsys_gunshot_hearing_enabled", "1", CVAR_FLAGS, "Enable hidden hearing loss from repeated gunfire.", 0, 1)
CVars.GunshotHearingRadius = CreateOrGetConVar("woundsys_gunshot_hearing_radius", "1400", CVAR_FLAGS, "Radius for gunshot hearing loss exposure.", 0, 5000)
CVars.GunshotHearingScale = CreateOrGetConVar("woundsys_gunshot_hearing_scale", "1", CVAR_FLAGS, "Multiplier for gunshot hearing loss exposure.", 0, 10)
CVars.ReplaceVanillaBlood = CreateOrGetConVar("woundsys_replace_vanilla_blood", "1", CVAR_FLAGS, "Disable vanilla red blood on WoundSystem players and ragdolls.", 0, 1)
CVars.ServerPainSounds = CreateOrGetConVar("woundsys_server_pain_sounds_enabled", "1", CVAR_FLAGS, "Allow pain vocalizations and yelps server-wide.", 0, 1)
CVars.ServerGrowlSounds = CreateOrGetConVar("woundsys_server_growl_sounds_enabled", "1", CVAR_FLAGS, "Allow unhappy growls, whines, and barking sounds server-wide.", 0, 1)
CVars.HEVEnabled = CreateOrGetConVar("woundsys_hev_enabled", "1", ENABLED_CVAR_FLAGS, "Enable HEV environmental suit automation, power, and voice behavior.", 0, 1)

CVars.UnconsciousTimescaleEnabled = CreateOrGetConVar("woundsys_unconscious_timescale_enabled", "0", ENABLED_CVAR_FLAGS, "Enable automatic timescale speedup when player(s) are unconscious.", 0, 1)
CVars.UnconsciousTimescale = CreateOrGetConVar("woundsys_unconscious_timescale", "3.0", CVAR_FLAGS, "Timescale value when player(s) are unconscious.", 1.0, 10.0)

CVars.ForceUnchipped = CreateOrGetConVar("woundsys_force_unchipped", "0", ENABLED_CVAR_FLAGS, "Force all players to be unchipped server-wide (hides chip diagnostic moodles).", 0, 1)
CVars.PersistAcrossMaps = CreateOrGetConVar("woundsys_persist_across_maps", "1", ENABLED_CVAR_FLAGS, "Persist player items and body status (0 = disabled, 1 = campaign transitions only, 2 = always).", 0, 2)
CVars.StaminaDrainScale = CreateOrGetConVar("woundsys_stamina_drain_scale", "1.0", CVAR_FLAGS, "Multiplier for sprinting stamina drain rate.", 0, 10)

CreateOrGetConVar("woundsystem_spawn_slot1", "BRUISE KIT", CVAR_FLAGS, "Default starting item in spawn slot 1.")
CreateOrGetConVar("woundsystem_spawn_slot2", "DISINFECTANT", CVAR_FLAGS, "Default starting item in spawn slot 2.")
CreateOrGetConVar("woundsystem_spawn_slot3", "GAUZE", CVAR_FLAGS, "Default starting item in spawn slot 3.")
CreateOrGetConVar("woundsystem_spawn_slot4", "weapon", CVAR_FLAGS, "Default starting item in spawn slot 4 ('weapon', 'empty', or item name).")
CreateOrGetConVar("woundsystem_spawn_slot5", "empty", CVAR_FLAGS, "Default starting item in spawn slot 5.")

concommand.Add("woundsystem_force_unchipped", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then
        if ply.ChatPrint then ply:ChatPrint("[WoundSystem] You must be an admin to run this command.") end
        return
    end

    local val = tonumber(args[1])
    if val == nil then
        val = CVars.ForceUnchipped:GetInt() == 1 and 0 or 1
    else
        val = math.Clamp(val, 0, 1)
    end

    CVars.ForceUnchipped:SetInt(val)
    local status = val == 1 and "ENABLED (All players forced UNCHIPPED)" or "DISABLED (Normal chip settings)"
    if IsValid(ply) then
        ply:ChatPrint("[WoundSystem] Server force unchipped is now: " .. status)
    else
        print("[WoundSystem] Server force unchipped is now: " .. status)
    end
end)

CreateOrGetConVar("woundsys_chat_distortion_enabled", "1", CHAT_CVAR_FLAGS, "Distort received chat by distance and line of sight.", 0, 1)
CreateOrGetConVar("woundsys_chat_distortion_close", "350", CHAT_CVAR_FLAGS, "Distance where chat is still clear.", 0, 10000)
CreateOrGetConVar("woundsys_chat_distortion_far", "1800", CHAT_CVAR_FLAGS, "Distance where chat becomes unreadable.", 1, 20000)
CreateOrGetConVar("woundsys_chat_distortion_power", "1.15", CHAT_CVAR_FLAGS, "Curve for distance chat loss. Higher keeps close/medium chat clearer.", 0.25, 4)
CreateOrGetConVar("woundsys_chat_distortion_wall", "0.12", CHAT_CVAR_FLAGS, "Extra chat loss when blocked by world geometry.", 0, 1)
CreateOrGetConVar("woundsys_chat_distortion_wall_min", "0.18", CHAT_CVAR_FLAGS, "Minimum chat loss when blocked by world geometry.", 0, 1)

local VOICE_CVAR_NAMES = {
    "woundsys_voice_proximity_enabled",
    "woundsys_voice_proximity_near",
    "woundsys_voice_proximity_far",
    "woundsys_voice_proximity_min_volume",
    "woundsys_voice_proximity_power",
    "woundsys_voice_proximity_wall_muffle",
    "woundsys_voice_proximity_wall_check_interval",
    "woundsys_voice_proximity_dead_talk",
    "woundsys_voice_proximity_unconscious_talk",
    "woundsys_voice_proximity_team_bypass"
}

CreateOrGetConVar("woundsys_voice_proximity_enabled", "1", CHAT_CVAR_FLAGS, "Enable proximity-limited 3D voice chat.", 0, 1)
CreateOrGetConVar("woundsys_voice_proximity_near", "350", CHAT_CVAR_FLAGS, "Distance where proximity voice is full volume.", 0, 10000)
CreateOrGetConVar("woundsys_voice_proximity_far", "1800", CHAT_CVAR_FLAGS, "Maximum distance where proximity voice can be heard.", 1, 20000)
CreateOrGetConVar("woundsys_voice_proximity_min_volume", "0.08", CHAT_CVAR_FLAGS, "Lowest client voice volume scale at maximum proximity range.", 0, 1)
CreateOrGetConVar("woundsys_voice_proximity_power", "1.15", CHAT_CVAR_FLAGS, "Curve for voice volume falloff. Higher keeps close/medium voice clearer.", 0.25, 4)
CreateOrGetConVar("woundsys_voice_proximity_wall_muffle", "0.35", CHAT_CVAR_FLAGS, "Voice volume multiplier when world geometry blocks the talker.", 0, 1)
CreateOrGetConVar("woundsys_voice_proximity_wall_check_interval", "0.35", CHAT_CVAR_FLAGS, "Seconds between client wall-muffle traces for active talkers.", 0, 2)
CreateOrGetConVar("woundsys_voice_proximity_dead_talk", "0", CHAT_CVAR_FLAGS, "Allow dead players to speak through proximity voice.", 0, 1)
CreateOrGetConVar("woundsys_voice_proximity_unconscious_talk", "0", CHAT_CVAR_FLAGS, "Allow unconscious players to speak through proximity voice.", 0, 1)
CreateOrGetConVar("woundsys_voice_proximity_team_bypass", "0", CHAT_CVAR_FLAGS, "Let same-team players bypass proximity voice range at full volume.", 0, 1)

WoundSystem.Health.FreezeHungerConVar = CreateOrGetConVar("woundsys_freeze_hunger", "1", CVAR_FLAGS, "Freeze hunger at the value a body starts with.", 0, 1)
WoundSystem.Health.FreezeThirstConVar = CreateOrGetConVar("woundsys_freeze_thirst", "1", CVAR_FLAGS, "Freeze thirst at the value a body starts with.", 0, 1)
WoundSystem.Health.DamageAttributionWindow = WoundSystem.Health.DamageAttributionWindow or 20
WoundSystem.Health.DeathRagdollCleanupDuration = WoundSystem.Health.DeathRagdollCleanupDuration or 3
WoundSystem.Health.DeathRagdollCleanupRadiusSqr = WoundSystem.Health.DeathRagdollCleanupRadiusSqr or (420 * 420)
WoundSystem.Health.LimbForce = WoundSystem.Health.LimbForce or {}
WoundSystem.Health.Circulation = WoundSystem.Health.Circulation or {}
WoundSystem.Health.LimbForce.EnabledCVar = CreateOrGetConVar("woundsys_limb_force_enabled", "1", CVAR_FLAGS, "Use original-style limb force for movement, jumping, and weapon handling.", 0, 1)
WoundSystem.Health.LimbForce.MovementScaleCVar = CreateOrGetConVar("woundsys_limb_force_movement_scale", "1", CVAR_FLAGS, "Scale how strongly limb force affects movement.", 0, 2)
WoundSystem.Health.LimbForce.WeaponThresholdCVar = CreateOrGetConVar("woundsys_limb_force_weapon_threshold", "0.16", CVAR_FLAGS, "Arm/hand force below this blocks weapon use.", 0, 1)
WoundSystem.Health.LimbForce.RagdollThresholdCVar = CreateOrGetConVar("woundsys_limb_force_ragdoll_threshold", "0.18", CVAR_FLAGS, "Leg/core force below this may cause collapse while moving.", 0, 1)
Config.ServerOptionsCVars = Config.ServerOptionsCVars or {
    woundsys_enabled = true,
    woundsys_limb_tick_interval = true,
    woundsys_cardio_tick_interval = true,
    woundsys_dislocation_heal_speed = true,
    woundsys_bone_heal_speed = true,
    woundsys_natural_bleed_slow_lpm = true,
    woundsys_fibrillation_rise_rate = true,
    woundsys_fibrillation_decay_rate = true,
    woundsys_shrapnel_input_hz = true,
    woundsys_healing_rate = true,
    woundsys_bleed_rate = true,
    woundsys_strokes_enabled = true,
    woundsys_temperature_enabled = true,
    woundsys_map_suffocation_enabled = true,
    woundsys_map_suffocation_scale = true,
    woundsys_gunshot_hearing_enabled = true,
    woundsys_gunshot_hearing_radius = true,
    woundsys_gunshot_hearing_scale = true,
    woundsys_replace_vanilla_blood = true,
    woundsys_server_pain_sounds_enabled = true,
    woundsys_server_growl_sounds_enabled = true,
    woundsys_hev_enabled = true,
    woundsys_chat_distortion_enabled = true,
    woundsys_chat_distortion_close = true,
    woundsys_chat_distortion_far = true,
    woundsys_chat_distortion_power = true,
    woundsys_chat_distortion_wall = true,
    woundsys_chat_distortion_wall_min = true,
    woundsys_limb_force_enabled = true,
    woundsys_limb_force_movement_scale = true,
    woundsys_limb_force_weapon_threshold = true,
    woundsys_limb_force_ragdoll_threshold = true,
    woundsys_freeze_hunger = true,
    woundsys_freeze_thirst = true,
    woundsys_brain_symptoms_enabled = true,
    woundsys_brain_symptom_interval = true,
    woundsys_brain_symptom_threshold = true,
    woundsys_brain_ragdoll_symptoms = true,
    woundsys_happiness_enabled = true,
    woundsys_happiness_ally_radius = true,
    woundsys_unconscious_timescale_enabled = true,
    woundsys_unconscious_timescale = true,
    woundsys_force_unchipped = true,
    woundsys_persist_across_maps = true,
    woundsys_stamina_drain_scale = true,
    woundsystem_spawn_slot1 = true,
    woundsystem_spawn_slot2 = true,
    woundsystem_spawn_slot3 = true,
    woundsystem_spawn_slot4 = true,
    woundsystem_spawn_slot5 = true
}

Config.ServerOptionsCVars.woundsys_enabled = true
Config.ServerOptionsCVars.woundsys_cardio_crit_oxygen = nil
Config.ServerOptionsCVars.woundsys_cardio_crit_pressure = nil
Config.ServerOptionsCVars.woundsys_cardio_damage_scale = nil

for _, cvarName in ipairs(VOICE_CVAR_NAMES) do
    Config.ServerOptionsCVars[cvarName] = true
end

function Config.CvFloat(cvar, fallback)
    local value = cvar and cvar:GetFloat() or fallback
    if value == nil or value ~= value then return fallback end
    return value
end

function Config.LimbTickInterval()
    return math.max(Config.CvFloat(CVars.LimbTick, 1), 0.1)
end

function Config.CardioTickInterval()
    return math.max(Config.CvFloat(CVars.CardioTick, 0.25), 0.1)
end

function Config.NaturalBleedSlowPerSecond()
    return Config.CvFloat(CVars.NaturalBleedSlowLiters, 0.027) / 0.075 / 60
end

function Config.ApplyFrozenThirst(body)
    if not body then return end

    local cvFreezeThirst = WoundSystem.Health.FreezeThirstConVar
    if not cvFreezeThirst or not cvFreezeThirst:GetBool() then
        body.frozenThirst = nil
        return
    end

    if body.frozenThirst == nil then
        body.frozenThirst = body.thirst or 100
    end

    body.thirst = math.Clamp(body.frozenThirst, -50, 250)
end

function Config.ApplyFrozenHunger(body)
    if not body then return end

    local cvFreezeHunger = WoundSystem.Health.FreezeHungerConVar
    if not cvFreezeHunger or not cvFreezeHunger:GetBool() then
        body.frozenHunger = nil
        return
    end

    if body.frozenHunger == nil then
        body.frozenHunger = body.hunger or 100
    end

    body.hunger = math.Clamp(body.frozenHunger, -50, 125)
end

function Config.ApplyFrozenNeeds(body)
    Config.ApplyFrozenHunger(body)
    Config.ApplyFrozenThirst(body)
end

WoundSystem.Health.ApplyFrozenThirst = Config.ApplyFrozenThirst
WoundSystem.Health.ApplyFrozenHunger = Config.ApplyFrozenHunger
WoundSystem.Health.ApplyFrozenNeeds = Config.ApplyFrozenNeeds

function Config.ApplyVanillaBloodMode(ent)
    if not IsValid(ent) or not ent.SetBloodColor then return end

    if Config.IsEnabled() and CVars.ReplaceVanillaBlood:GetBool() then
        ent:SetBloodColor(DONT_BLEED or -1)
    elseif ent:IsPlayer() then
        ent:SetBloodColor(BLOOD_COLOR_RED or 0)
    end
end

function Config.BloodRegenSpeed(body)
    local healingMult = Config.CvFloat(CVars.HealingRate, 1)
    return 0.035 * math.max((body.hunger or 0) * 0.01, 0) * healingMult
end

function Config.ViscosityRemap01(viscosity)
    return math.Clamp((viscosity + 100) / 100, 0, 1)
end

function Config.ComputeBleedClottingSpeed(body)
    local vis = body.bloodViscosity or 0
    return 0.025 * Config.ViscosityRemap01(vis)
end

function Config.ComputeBleedingSpeedMultiplier(body)
    local vis = body.bloodViscosity or 0
    local remapped = ((vis + 100) / 100) * (-0.01) + 0.01
    return (0.01 + math.Clamp(remapped, 0, 1)) * Config.CvFloat(CVars.BleedRate, 1)
end

function Config.ComputeHungerLimbHeal(body)
    return math.max((body.hunger or 100) * 0.01, 0)
end

function Config.CanSetServerConVar(name)
    return Config.ServerOptionsCVars[name] == true
end

function Config.IsEnabled()
    return not CVars.Enabled or CVars.Enabled:GetBool()
end

function Config.TemperatureEnabled()
    return not CVars.TemperatureEnabled or CVars.TemperatureEnabled:GetBool()
end

function Config.MapSuffocationEnabled()
    return not CVars.MapSuffocationEnabled or CVars.MapSuffocationEnabled:GetBool()
end

function Config.EvaluateImmunityInfectionSpeed(immunity)
    immunity = math.Clamp(immunity or 100, 0, 200)

    if immunity <= 50 then
        return Lerp(immunity / 50, 2.5, 1.5)
    elseif immunity <= 80 then
        return Lerp((immunity - 50) / 30, 1.5, 1.1)
    elseif immunity <= 100 then
        return Lerp((immunity - 80) / 20, 1.1, 1.0)
    elseif immunity <= 120 then
        return Lerp((immunity - 100) / 20, 1.0, 0.9)
    elseif immunity <= 140 then
        return Lerp((immunity - 120) / 20, 0.9, 0.69)
    elseif immunity <= 195 then
        return Lerp((immunity - 140) / 55, 0.69, 0.15)
    else
        return Lerp((immunity - 195) / 5, 0.15, -0.80)
    end
end

function Config.MapSuffocationScale()
    return Config.CvFloat(CVars.MapSuffocationScale, 1)
end
