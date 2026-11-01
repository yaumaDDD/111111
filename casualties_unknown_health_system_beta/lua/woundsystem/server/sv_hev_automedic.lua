if not SERVER then return end

local nextHevThink = 0
local HEV_SCAN_INTERVAL = 5
local HEV_HEAL_COST_SPLINT = 5
local HEV_HEAL_COST_BANDAGE = 3
local HEV_HEAL_COST_PAINKILLER = 4
local HEV_HEAL_COST_ANTIDOTE = 5
local HEV_PASSIVE_POWER_COST = 0.5

local function IsHealthSystemEnabled()
    return not WoundSystemHealthEnabled or WoundSystemHealthEnabled()
end

local function IsHEVEnabled()
    if WoundSystem and WoundSystem.Health and WoundSystem.Health.Config and WoundSystem.Health.Config.CVars and WoundSystem.Health.Config.CVars.HEVEnabled then
        return WoundSystem.Health.Config.CVars.HEVEnabled:GetBool()
    end

    local cvar = GetConVar("woundsys_hev_enabled")
    return cvar and cvar:GetBool() or true
end

local function HasHEVSuit(ply)
    if not IsValid(ply) then return false end

    -- Native GMod/HL2 engine check
    if ply.IsSuitEquipped and ply:IsSuitEquipped() then return true end

    -- Common addon checks
    if ply.GetNWBool and (ply:GetNWBool("IsSuitEquipped", false) or ply:GetNWBool("HasSuit", false)) then return true end
    if ply.GetNW2Bool and (ply:GetNW2Bool("IsSuitEquipped", false) or ply:GetNW2Bool("HasSuit", false)) then return true end

    -- Internal healthsystem tracking variables
    if ply.HEVEquipped == true or ply.WoundSystemHEVEquipped == true then
        local armored = tonumber(ply:Armor()) or 0
        local power = tonumber(ply.WoundSystemHEVPower) or 0
        if power > 0 or armored > 0 then
            return true
        end
    end

    if type(ply.WoundSystemHEVPower) == "number" and ply.WoundSystemHEVPower > 0 then
        return true
    end

    return false
end

local function HEVClearStaleState(ply)
    if not IsValid(ply) then return end

    if not HasHEVSuit(ply) then
        ply.HEVEquipped = false
        ply.WoundSystemHEVEquipped = false
        ply.WoundSystemHEVPower = 0
        if ply.SetArmor then
            ply:SetArmor(0)
        end
    end
end

local function GetHEVPower(ply)
    if not IsValid(ply) then return 0 end

    return math.Clamp(tonumber(ply:Armor()) or 0, 0, 100)
end

local function SetHEVPower(ply, power)
    if not IsValid(ply) then return 0 end

    power = math.Clamp(tonumber(power) or 0, 0, 100)

    if ply.SetArmor then
        ply:SetArmor(power)
    end

    ply.WoundSystemHEVEquipped = true
    return power
end

local function HEVGetShrapnelBlockChance(ply)
    if not IsHEVEnabled() then return 0 end
    if not IsValid(ply) then return 0 end
    if not HasHEVSuit(ply) then return 0 end

    local power = GetHEVPower(ply)
    if power <= 0 then return 0 end

    return math.Clamp(power / 100, 0, 1)
end

WoundSystem = WoundSystem or {}
WoundSystem.HEVGetShrapnelBlockChance = HEVGetShrapnelBlockChance
util.AddNetworkString("WoundSystem_HEV_SelfTalk")

local PLAYER = FindMetaTable("Player")
if PLAYER and not PLAYER.EmitHEVSound then
    function PLAYER:EmitHEVSound(snd)
        if not IsValid(self) or not snd or snd == "" then return end

        self:EmitSound(snd, 60, 100, 1, CHAN_AUTO)
    end
end

local HEV_SFX_FILES = {
    ["fvox/beep.wav"] = true,
    ["fvox/boop.wav"] = true,
    ["fvox/bell.wav"] = true,
    ["fvox/warning.wav"] = true,
    ["fvox/hiss.wav"] = true,
    ["fvox/hev_logon.wav"] = true,
    ["fvox/powerarmor_on.wav"] = true,
    ["fvox/atmospherics_on.wav"] = true,
    ["fvox/vitalsigns_on.wav"] = true,
    ["fvox/automedic_on.wav"] = true,
    ["fvox/communications_on.wav"] = true,
    ["fvox/health_critical.wav"] = true,
    ["fvox/near_death.wav"] = true,
    ["fvox/evacuate_area.wav"] = true,
    ["fvox/blood_loss.wav"] = true,
    ["fvox/medical_repaired.wav"] = true,
    ["fvox/wound_sterilized.wav"] = true,
    ["fvox/morphine_shot.wav"] = true,
    ["fvox/antidote_shot.wav"] = true,
    ["fvox/major_fracture.wav"] = true,
    ["fvox/immobilize.wav"] = true,
    ["fvox/internal_bleeding.wav"] = true,
    ["fvox/pressure_point.wav"] = true,
    ["fvox/contaminant_detected.wav"] = true,
    ["fvox/analgesic.wav"] = true,
    ["fvox/medical_emergency.wav"] = true,
    ["fvox/seek_medical_attention.wav"] = true,
    ["fvox/seek_medic.wav"] = true,
    ["fvox/atmosphere_warning.wav"] = true,
    ["fvox/medical_repaired.wav"] = true,
    ["fvox/major_lacerations.wav"] = true,
    ["fvox/minor_lacerations.wav"] = true,
    ["fvox/bleeding_stopped.wav"] = true,
    ["fvox/blood_toxins.wav"] = true,
    ["fvox/shock_damage.wav"] = true,
    ["fvox/radiation_detected.wav"] = true,
    ["fvox/chemical_detected.wav"] = true,
    ["fvox/biohazard_detected.wav"] = true,
    ["fvox/immediately.wav"] = true,
    ["fvox/pain_block.wav"] = true
}

local HEV_SPOKEN_TEXT = {
    ["fvox/health_critical.wav"] = "CRITICAL VITALS",
    ["fvox/health_dropping.wav"] = "VITAL SIGNS ARE DROPPING",
    ["fvox/health_dropping2.wav"] = "VITAL SIGNS ARE DROPPING",
    ["fvox/near_death.wav"] = "EMERGENCY. USER DEATH IMMINENT.",
    ["fvox/evacuate_area.wav"] = "EVACUATE AREA",
    ["fvox/blood_loss.wav"] = "BLOOD LOSS DETECTED",
    ["fvox/medical_repaired.wav"] = "MEDICAL DAMAGE REPAIRED",
    ["fvox/wound_sterilized.wav"] = "WOUND STERILIZED",
    ["fvox/morphine_shot.wav"] = "MORPHINE ADMINISTERED",
    ["fvox/antidote_shot.wav"] = "ANTIDOTE ADMINISTERED",
    ["fvox/major_fracture.wav"] = "MAJOR FRACTURE DETECTED",
    ["fvox/minor_fracture.wav"] = "MINOR FRACTURE DETECTED",
    ["fvox/immobilize.wav"] = "IMMOBILIZE",
    ["fvox/internal_bleeding.wav"] = "INTERNAL BLEEDING DETECTED",
    ["fvox/pressure_point.wav"] = "PRESSURE POINT",
    ["fvox/contaminant_detected.wav"] = "CONTAMINANT DETECTED",
    ["fvox/analgesic.wav"] = "ANALGESIC",
    ["fvox/medical_emergency.wav"] = "MEDICAL EMERGENCY",
    ["fvox/seek_medical_attention.wav"] = "SEEK MEDICAL ATTENTION",
    ["fvox/seek_medic.wav"] = "SEEK MEDIC",
    ["fvox/atmosphere_warning.wav"] = "ATMOSPHERE WARNING",
    ["fvox/minor_lacerations.wav"] = "MINOR LACERATIONS DETECTED",
    ["fvox/major_lacerations.wav"] = "MAJOR LACERATIONS DETECTED",
    ["fvox/bleeding_stopped.wav"] = "BLEEDING HAS STOPPED",
    ["fvox/blood_toxins.wav"] = "BLOOD TOXIN LEVELS DETECTED",
    ["fvox/shock_damage.wav"] = "ELECTRICAL DAMAGE DETECTED",
    ["fvox/heat_damage.wav"] = "EXTREME HEAT DAMAGE DETECTED",
    ["fvox/radiation_detected.wav"] = "HAZARDOUS RADIATION LEVELS DETECTED",
    ["fvox/chemical_detected.wav"] = "HAZARDOUS CHEMICAL DETECTED",
    ["fvox/biohazard_detected.wav"] = "BIOHAZARD DETECTED",
    ["fvox/immediately.wav"] = "IMMEDIATELY",
    ["fvox/pain_block.wav"] = "PAIN SUPPRESSANT ADMINISTERED",
    ["fvox/weaponselect_on.wav"] = "DEFENSIVE WEAPON SYSTEM ACTIVATED",
    ["fvox/munitionview_on.wav"] = "MUNITION LEVEL MONITORING ACTIVATED",
    ["fvox/powerarmor_on.wav"] = "HIGH-IMPACT REACTIVE ARMOR ACTIVATED",
    ["fvox/atmospherics_on.wav"] = "ATMOSPHERIC CONTAMINANT SENSORS ACTIVATED",
    ["fvox/vitalsigns_on.wav"] = "VITAL SIGNS MONITORING ACTIVATED",
    ["fvox/automedic_on.wav"] = "AUTOMATIC MEDICAL SYSTEMS ENGAGED",
    ["fvox/communications_on.wav"] = "COMMUNICATIONS INTERFACE ONLINE",
    ["fvox/hev_logon.wav"] = "WELCOME TO THE HEV MARK 4 PROTECTIVE SYSTEM",
    ["fvox/bell.wav"] = "WELCOME TO THE HEV MARK 4 PROTECTIVE SYSTEM",
    ["fvox/power_restored.wav"] = "POWER RESTORED",
    ["fvox/armor_gone.wav"] = "ARMOR COMPROMISED",
    ["fvox/voice_on.wav"] = "VOICE SYSTEM ACTIVATED",
    ["fvox/voice_off.wav"] = "VOICE SYSTEM DEACTIVATED",
    ["fvox/flatline.wav"] = "FLATLINE",
    ["fvox/targetting_system.wav"] = "AUTOMATIC TARGET ACQUISITION SYSTEM ACTIVATED",
    ["fvox/activated.wav"] = "ACTIVATED"
}

local function HEVGetSpokenDisplayText(snd)
    if not snd or snd == "" then return nil end
    local name = snd:match("([^/\\]+)$") or snd
    if HEV_SFX_FILES[name] then
        return nil
    end
    return HEV_SPOKEN_TEXT[name] or (name and string.upper(name:gsub("%.wav$", "")))
end

local HEV_SOUND_LENGTHS = {
    ["fvox/beep.wav"] = 0.217,
    ["fvox/boop.wav"] = 0.410,
    ["fvox/bell.wav"] = 0.692,
    ["fvox/warning.wav"] = 0.703,
    ["fvox/hiss.wav"] = 0.538,
    ["fvox/hev_logon.wav"] = 10.129,
    ["fvox/powerarmor_on.wav"] = 4.202,
    ["fvox/atmospherics_on.wav"] = 4.219,
    ["fvox/vitalsigns_on.wav"] = 3.334,
    ["fvox/automedic_on.wav"] = 3.506,
    ["fvox/communications_on.wav"] = 3.376,
    ["fvox/health_critical.wav"] = 3.153,
    ["fvox/near_death.wav"] = 3.606,
    ["fvox/evacuate_area.wav"] = 2.117,
    ["fvox/blood_loss.wav"] = 2.159,
    ["fvox/medical_repaired.wav"] = 2.762,
    ["fvox/wound_sterilized.wav"] = 1.960,
    ["fvox/morphine_shot.wav"] = 1.960,
    ["fvox/antidote_shot.wav"] = 1.971,
    ["fvox/major_fracture.wav"] = 2.431,
    ["fvox/immobilize.wav"] = 2.431,
    ["fvox/internal_bleeding.wav"] = 2.406,
    ["fvox/pressure_point.wav"] = 2.0,
    ["fvox/contaminant_detected.wav"] = 2.0,
    ["fvox/analgesic.wav"] = 2.0,
    ["fvox/medical_emergency.wav"] = 2.0,
    ["fvox/seek_medical_attention.wav"] = 2.5,
    ["fvox/seek_medic.wav"] = 2.508,
    ["fvox/atmosphere_warning.wav"] = 2.0,
    ["fvox/munitionview_on.wav"] = 3,
    ["fvox/weaponselect_on.wav"] = 3,
    ["fvox/communications_on.wav"] = 4,
    ["fvox/voice_on.wav"] = 1.486,
    ["fvox/voice_off.wav"] = 1.214
}

local function HEVGetSoundDuration(snd)
    if not snd or snd == "" then return 0.5 end

    local dur = HEV_SOUND_LENGTHS[snd]
    if dur then return dur end

    local name = snd:match("([^/\\]+)$") or snd
    dur = HEV_SOUND_LENGTHS[name]
    if dur then return dur end

    return 1.2
end

local function HEVEmitSound(ply, snd)
    if not IsValid(ply) or not snd or snd == "" then return end

    local spokenText = HEVGetSpokenDisplayText(snd)
    if spokenText then
        local duration = HEVGetSoundDuration(snd) or 1.2
        net.Start("WoundSystem_HEV_SelfTalk")
            net.WriteString(spokenText)
            net.WriteFloat(duration)
        net.Send(ply)
    end

    if ply.EmitHEVSound then
        ply:EmitHEVSound(snd)
    else
        ply:EmitSound(snd, 60, 100, 1, CHAN_AUTO)
    end
end

local HEV_VOICE_GAP = 0.35

local function HEVEmitSequence(ply, ...)
    local sounds = {...}
    if not IsValid(ply) then return end

    local filtered = {}
    for _, snd in ipairs(sounds) do
        if snd and snd ~= "" then
            table.insert(filtered, snd)
        end
    end

    if #filtered == 0 then return end

    ply.WoundSystemHEVVoiceQueue = ply.WoundSystemHEVVoiceQueue or {}
    
    for _, snd in ipairs(filtered) do
        table.insert(ply.WoundSystemHEVVoiceQueue, snd)
    end
end

hook.Add("Think", "WoundSystem_HEV_VoiceQueueProcess", function()
    local now = CurTime()
    for _, ply in ipairs(player.GetAll()) do
        if ply.WoundSystemHEVVoiceQueue and #ply.WoundSystemHEVVoiceQueue > 0 then
            if now >= (ply.WoundSystemHEVNextVoiceTime or 0) then
                local snd = table.remove(ply.WoundSystemHEVVoiceQueue, 1)
                if IsValid(ply) and ply:Alive() then
                    HEVEmitSound(ply, snd)
                    local length = HEVGetSoundDuration(snd)
                    ply.WoundSystemHEVNextVoiceTime = now + length + HEV_VOICE_GAP
                else
                    ply.WoundSystemHEVVoiceQueue = nil
                end
            end
        end
    end
end)

local HEV_ISSUE_ORDER = {
    "critical",
    "severe",
    "internal_bleeding",
    "bleeding",
    "fracture",
    "broken",
    "infection",
    "pain",
    "toxin",
    "shock",
    "warning",
    "heal"
}

local HEV_BOOT_SEQUENCE = {
    "fvox/bell.wav",
    "fvox/hev_logon.wav",
    "fvox/powerarmor_on.wav",
    "fvox/atmospherics_on.wav",
    "fvox/vitalsigns_on.wav",
    "fvox/automedic_on.wav",
    "fvox/munitionview_on.wav",
    "fvox/weaponselect_on.wav",
    "fvox/communications_on.wav"
}

local function HEVGetLimbSeverity(state)
    if not state then return 0 end

    local score = 0
    if state.dismembered then score = score + 220 end
    if state.broken then score = score + 110 end
    if state.dislocated then score = score + 80 end
    if (state.bleed or 0) > 0 then score = score + math.min(90, (state.bleed or 0) * 2.2) end
    if (state.infection or 0) > 0 then score = score + math.min(70, (state.infection or 0) * 1.8) end
    if (state.pain or 0) > 0 then score = score + math.min(35, (state.pain or 0) * 0.5) end
    if state.isBandaged then score = score - 6 end
    if state.hevBrace then score = score - 8 end

    return score
end

local function HEVVoiceForIssue(issue)
    local issueMap = {
        critical = {"fvox/beep.wav", "fvox/health_critical.wav", "fvox/evacuate_area.wav", "fvox/seek_medic.wav"},
        severe = {"fvox/beep.wav", "fvox/near_death.wav", "fvox/evacuate_area.wav", "fvox/immediately.wav"},
        internal_bleeding = {"fvox/boop.wav", "fvox/internal_bleeding.wav", "fvox/blood_loss.wav", "fvox/pressure_point.wav"},
        bleeding = {"fvox/boop.wav", "fvox/blood_loss.wav", "fvox/pressure_point.wav", "fvox/bleeding_stopped.wav"},
        fracture = {"fvox/boop.wav", "fvox/major_fracture.wav", "fvox/immobilize.wav", "fvox/seek_medic.wav"},
        broken = {"fvox/boop.wav", "fvox/major_fracture.wav", "fvox/medical_repaired.wav", "fvox/immobilize.wav"},
        laceration = {"fvox/boop.wav", "fvox/minor_lacerations.wav", "fvox/major_lacerations.wav", "fvox/pressure_point.wav"},
        infection = {"fvox/boop.wav", "fvox/hiss.wav", "fvox/antidote_shot.wav", "fvox/wound_sterilized.wav"},
        pain = {"fvox/boop.wav", "fvox/morphine_shot.wav", "fvox/pain_block.wav", "fvox/seek_medic.wav"},
        toxin = {"fvox/boop.wav", "fvox/antidote_shot.wav", "fvox/blood_toxins.wav", "fvox/medical_emergency.wav"},
        shock = {"fvox/beep.wav", "fvox/warning.wav", "fvox/shock_damage.wav", "fvox/evacuate_area.wav"},
        environmental = {"fvox/beep.wav", "fvox/radiation_detected.wav", "fvox/chemical_detected.wav", "fvox/biohazard_detected.wav"},
        heal = {"fvox/boop.wav", "fvox/medical_repaired.wav", "fvox/wound_sterilized.wav"},
        warning = {"fvox/beep.wav", "fvox/warning.wav", "fvox/boop.wav", "fvox/medical_emergency.wav"}
    }

    return issueMap[issue] or {"fvox/boop.wav", "fvox/boop.wav", "fvox/warning.wav"}
end

local function HEVResetVoiceState(ply)
    if not IsValid(ply) then return end

    ply.WoundSystemHEVVoiceQueue = nil
    ply.WoundSystemHEVVoiceBusy = false
    ply.WoundSystemHEVBootOnline = false
    ply.WoundSystemHEVLastIssueKey = nil
    ply.WoundSystemHEVLastIssueTime = nil
    ply.HEV_CritWarned = false
    ply.WoundSystemHEVBootAt = 0
    ply.WoundSystemHEVIntroPlayed = false
end

local function HEVIssueCooldown(ply, key, seconds)
    local now = CurTime()
    local lastAt = ply.WoundSystemHEVLastIssueTime or 0
    local lastKey = ply.WoundSystemHEVLastIssueKey or ""

    if key == lastKey and now - lastAt < seconds then
        return false
    end

    ply.WoundSystemHEVLastIssueKey = key
    ply.WoundSystemHEVLastIssueTime = now
    return true
end

local function HEVSmartMessage(ply, issue, sounds)
    if not IsValid(ply) then return end
    if not issue then return end
    if not HEVIssueCooldown(ply, issue, 26) then return end

    local seq = sounds or HEVVoiceForIssue(issue)
    if not seq or #seq <= 0 then return end

    -- All HEV lines must use the same player queue; this is the actual fix for overlap.
    HEVEmitSequence(ply, unpack(seq))
end

local function HEVApplyTemporaryBrace(state)
    if not state then return false end

    state.hevBrace = true
    state.hevBraceTimer = 45
    state.hevBraceApplied = true
    
    state.splinted = true
    state.splintItemId = "HEV_BRACE"
    state.splintDurability = 100
    if WoundSystem.Statuses then
        WoundSystem.Statuses.Set(state, "SPLINTED", 100)
    end

    if state.broken and (state.boneHealTimer or 0) > 0 then
        state.boneHealTimer = math.max(0, (state.boneHealTimer or 0) - 12)
    end

    if state.dislocated and (state.dislocationTimer or 0) > 0 then
        state.dislocationTimer = math.max(0, (state.dislocationTimer or 0) - 9)
    end

    return true
end

local function HEVRepairLimbState(state)
    if not state then return false end

    local needsRepair = state.broken or state.dislocated or ((state.bleed or 0) > 0) or ((state.infection or 0) > 0) or ((state.pain or 0) > 0)
    if not needsRepair then return false end

    local repaired = false

    if state.broken and (state.boneHealTimer or 0) > 0 then
        state.boneHealTimer = math.max(0, (state.boneHealTimer or 0) - 8)
        repaired = true
    end

    if state.dislocated and (state.dislocationTimer or 0) > 0 then
        state.dislocationTimer = math.max(0, (state.dislocationTimer or 0) - 6)
        repaired = true
    end

    if (state.bleed or 0) > 0 then
        state.bleed = math.max(0, (state.bleed or 0) - 18)
        state.blockedBleeding = true
        state.isBandaged = true
        repaired = true
    end

    if (state.infection or 0) > 0 then
        state.infection = math.max(0, (state.infection or 0) - 12)
        state.infectionSpeed = math.max(0, (state.infectionSpeed or 0) * 0.6)
        repaired = true
    end

    if (state.pain or 0) > 0 then
        state.pain = math.max(0, (state.pain or 0) - 20)
        repaired = true
    end

    state.skin = math.min(100, (state.skin or 100) + 8)
    state.muscle = math.min(100, (state.muscle or 100) + 6)
    HEVApplyTemporaryBrace(state)

    return repaired
end

local function HEVChooseSmartIssue(ply, limbs, body)
    local bestIssue = nil
    local bestScore = -1
    local issuePriority = {}

    for idx, issue in ipairs(HEV_ISSUE_ORDER) do
        issuePriority[issue] = math.max(0, 9 - idx)
    end

    local function Score(issue, value)
        if not issue then return end
        local score = (value or 0) + (issuePriority[issue] or 0)
        if score > bestScore then
            bestIssue = issue
            bestScore = score
        end
    end

    if (body.bloodVolume or 100) < 35 or ply:Health() < 18 then
        Score("critical", 40)
    end

    if (body.bloodVolume or 100) < 55 or ply:Health() < 35 then
        Score("severe", 30)
    end

    if (body.venomCurrent or 0) > 18 or (body.sicknessAmount or 0) > 25 then
        Score("toxin", 25)
    end

    for _, state in pairs(limbs or {}) do
        if state and not state.dismembered then
            if state.broken then
                Score("fracture", 36)
                Score("broken", 28)
            end

            if (state.bleed or 0) > 12 then
                Score("internal_bleeding", 34)
                Score("bleeding", 28)
            end

            if (state.bleed or 0) > 22 or (state.broken and (state.bleed or 0) > 0) then
                Score("critical", 18)
            end

            if ((state.infection or 0) > 0 or (state.infectionSpeed or 0) > 0) and not state.broken and (state.bleed or 0) <= 12 then
                Score("infection", 18)
            end

            if (state.pain or 0) > 40 then
                Score("pain", 20)
            end
        end
    end

    if (body.avgPain or 0) > 45 then
        Score("pain", 21)
    end

    if (body.shock or 0) > 25 or (body.stress or 0) > 25 then
        Score("shock", 18)
    end

    if bestIssue then return bestIssue end
    if (body.bloodVolume or 100) < 70 then return "warning" end
    return "heal"
end

local function ConsumeArmor(ply, armor, cost)
    armor = math.max(0, armor - cost)
    local newArmor = SetHEVPower(ply, armor)

    if WoundSystem and WoundSystem.DebugHEV then
        print("[WoundSystem HEV] " .. tostring(ply:Nick()) .. " spent " .. tostring(cost) .. " power; remaining=" .. tostring(newArmor))
    end

    return newArmor
end

local function DebugHEVState(ply, msg)
    if not WoundSystem or not WoundSystem.DebugHEV then return end
    print("[WoundSystem HEV] " .. tostring(ply:Nick()) .. " - " .. msg)
end

local function ProcessHEVAutoMedic()
    if not IsHEVEnabled() then return end

    if WoundSystem and WoundSystem.DebugHEV then
        print("[WoundSystem HEV] think tick")
    end

    if CurTime() < nextHevThink then return end
    nextHevThink = CurTime() + HEV_SCAN_INTERVAL

    if not IsHealthSystemEnabled() then return end

    local PlayerLimbs = WoundSystem.Health.PlayerLimbs or _G.PlayerLimbs
    local BodyState = WoundSystem.Health.BodyState or _G.BodyState
    if not PlayerLimbs or not BodyState then
        if WoundSystem and WoundSystem.DebugHEV then
            print("[WoundSystem HEV] no body tables ready yet")
        end
        return
    end

    WoundSystem.Health.PlayerLimbs = PlayerLimbs
    WoundSystem.Health.BodyState = BodyState

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end
        if not HasHEVSuit(ply) then
            HEVResetVoiceState(ply)
            DebugHEVState(ply, "no suit detected")
            continue
        end

        local armor = GetHEVPower(ply)
        DebugHEVState(ply, "suit detected; power=" .. tostring(armor))

        if armor <= 0 then
            HEVResetVoiceState(ply)
            DebugHEVState(ply, "power exhausted")
            continue
        end

        local limbs = PlayerLimbs[ply]
        local body = BodyState[ply]
        if not limbs or not body then continue end

        if not ply.WoundSystemHEVBootOnline then
            local now = CurTime()
            if (ply.WoundSystemHEVBootAt or 0) <= now - 2 then
                ply.WoundSystemHEVBootAt = now
                ply.WoundSystemHEVBootOnline = true
                ply.WoundSystemHEVIntroPlayed = true
                DebugHEVState(ply, "booting HEV automedic")
                HEVEmitSequence(ply, unpack(HEV_BOOT_SEQUENCE))
            end
        end

        local didAction = false

        local smartIssue = HEVChooseSmartIssue(ply, limbs, body)

        -- Environmental suit behavior: fix the most severe actual condition first, not just the first limb encountered.
        local limbEntries = {}
        for limbId, state in pairs(limbs) do
            if state then
                table.insert(limbEntries, {
                    id = limbId,
                    state = state,
                    score = HEVGetLimbSeverity(state)
                })
            end
        end

        table.sort(limbEntries, function(a, b)
            if (a and a.score or 0) == (b and b.score or 0) then
                return tostring(a.id) < tostring(b.id)
            end
            return (a and a.score or 0) > (b and b.score or 0)
        end)

        for _, entry in ipairs(limbEntries) do
            local limbId = entry.id
            local state = entry.state
            if state.broken and not state.dismembered and armor >= HEV_HEAL_COST_SPLINT then
                local braceApplied = HEVApplyTemporaryBrace(state)
                if braceApplied then
                    armor = ConsumeArmor(ply, armor, HEV_HEAL_COST_SPLINT)
                    HEVSmartMessage(ply, "heal", {"fvox/boop.wav", "fvox/medical_repaired.wav", "fvox/boop.wav", "fvox/immobilize.wav"})
                    didAction = true

                    if WoundSystem.Health.SendLimbUpdate then
                        WoundSystem.Health.SendLimbUpdate(ply, limbId, true)
                    end
                end
            elseif (state.bleed or 0) > 0 and not state.isBandaged and not state.blockedBleeding and not state.tourniqueted and armor >= HEV_HEAL_COST_BANDAGE then
                state.isBandaged = true
                state.blockedBleeding = true
                state.bandageSlowAmount = math.max(state.bandageSlowAmount or 0, 72)
                state.bleed = math.max(0, (state.bleed or 0) - 20)

                armor = ConsumeArmor(ply, armor, HEV_HEAL_COST_BANDAGE)
                HEVSmartMessage(ply, "bleeding", {"fvox/boop.wav", "fvox/blood_loss.wav", "fvox/pressure_point.wav", "fvox/bleeding_stopped.wav"})
                didAction = true

                if WoundSystem.Health.SendLimbUpdate then
                    WoundSystem.Health.SendLimbUpdate(ply, limbId, true)
                end
            elseif ((state.infection or 0) > 0 or (state.infectionSpeed or 0) > 0) and armor >= HEV_PASSIVE_POWER_COST then
                state.infection = math.max(0, state.infection - 2)
                if state.infectionSpeed and state.infectionSpeed > 0 then
                    state.infectionSpeed = math.max(0, state.infectionSpeed - 0.5)
                end
                state.disinfectTime = math.max(state.disinfectTime or 0, 60)

                armor = ConsumeArmor(ply, armor, HEV_PASSIVE_POWER_COST)
                HEVSmartMessage(ply, "infection", {"fvox/boop.wav", "fvox/hiss.wav", "fvox/wound_sterilized.wav"})
                didAction = true

                if WoundSystem.Health.SendLimbUpdate then
                    WoundSystem.Health.SendLimbUpdate(ply, limbId, true)
                end
            elseif (state.broken or state.dislocated or (state.bleed or 0) > 0 or (state.infection or 0) > 0) and armor >= HEV_HEAL_COST_SPLINT then
                local repaired = HEVRepairLimbState(state)
                if repaired then
                    armor = ConsumeArmor(ply, armor, HEV_HEAL_COST_SPLINT)
                    HEVSmartMessage(ply, "heal", {"fvox/boop.wav", "fvox/medical_repaired.wav", "fvox/immobilize.wav"})
                    didAction = true

                    if WoundSystem.Health.SendLimbUpdate then
                        WoundSystem.Health.SendLimbUpdate(ply, limbId, true)
                    end
                end
            end

            if didAction then break end
        end

        if didAction then continue end

        if smartIssue == "pain" and (body.avgPain or 0) > 35 and (body.opiateAmount or 0) < 60 and armor >= HEV_HEAL_COST_PAINKILLER then
            body.opiateAmount = math.min(1000, (body.opiateAmount or 0) + 50)
            body.avgPain = math.max(0, (body.avgPain or 0) - 32)

            armor = ConsumeArmor(ply, armor, HEV_HEAL_COST_PAINKILLER)
            HEVSmartMessage(ply, "pain", {"fvox/boop.wav", "fvox/morphine_shot.wav", "fvox/pain_block.wav", "fvox/seek_medic.wav"})
            didAction = true

            if WoundSystem.Health.SendCardioUpdate then
                WoundSystem.Health.SendCardioUpdate(ply, true)
            end
        end

        if didAction then continue end

        if smartIssue == "toxin" and ((body.venomCurrent or 0) > 12 or (body.sicknessAmount or 0) > 18) and armor >= HEV_HEAL_COST_ANTIDOTE then
            body.venomCurrent = math.max(0, (body.venomCurrent or 0) - 40)
            body.sicknessAmount = math.max(0, (body.sicknessAmount or 0) - 16)

            armor = ConsumeArmor(ply, armor, HEV_HEAL_COST_ANTIDOTE)
            HEVSmartMessage(ply, "toxin", {"fvox/boop.wav", "fvox/antidote_shot.wav", "fvox/contaminant_detected.wav"})
            didAction = true

            if WoundSystem.Health.SendCardioUpdate then
                WoundSystem.Health.SendCardioUpdate(ply, true)
            end
        end

        if didAction then continue end

        if smartIssue == "critical" or smartIssue == "severe" then
            HEVSmartMessage(ply, "critical", {"fvox/beep.wav", "fvox/health_critical.wav", "fvox/evacuate_area.wav"})
            didAction = true
        elseif not ply.HEV_CritWarned and ((body.bloodVolume or 100) < 60 or ply:Health() < 30) then
            ply.HEV_CritWarned = true
            HEVSmartMessage(ply, "critical", {"fvox/beep.wav", "fvox/health_critical.wav", "fvox/medical_emergency.wav"})
        elseif ply.HEV_CritWarned and (body.bloodVolume or 100) > 70 and ply:Health() > 40 then
            ply.HEV_CritWarned = false
        end
    end
end

concommand.Add("woundsys_hev_debug", function(ply, cmd, args)
    WoundSystem = WoundSystem or {}
    WoundSystem.DebugHEV = not (WoundSystem.DebugHEV == true)
    print("[WoundSystem HEV] debug=" .. tostring(WoundSystem.DebugHEV))
end)

hook.Add("PlayerSpawn", "WoundSystem_HEV_ResetOnSpawn", function(ply)
    if not IsValid(ply) then return end

    local inTransition = ply._WoundSystemInChangeLevel == true
        or (ply._WoundSystemChangeLevelTime and (CurTime() - ply._WoundSystemChangeLevelTime) < 5)

    HEVResetVoiceState(ply)

    if inTransition then
        if ply.GetSuitPower then
            local sp = tonumber(ply:GetSuitPower()) or tonumber(ply:Armor()) or 0
            if sp > 0 then
                SetHEVPower(ply, sp)
            end
        else
            local a = tonumber(ply:Armor()) or 0
            if a > 0 then
                SetHEVPower(ply, a)
            end
        end
    else
        -- On normal spawn, we don't force armor to 0 because gamemodes like HL2 campaign
        -- legitimately give players the suit and armor on spawn. We just let the gamemode handle it.
        ply.WoundSystemHEVBootOnline = false
        ply.WoundSystemHEVBootAt = 0
    end
end)

hook.Add("Think", "WoundSystem_HEV_AutoMedic", ProcessHEVAutoMedic)
