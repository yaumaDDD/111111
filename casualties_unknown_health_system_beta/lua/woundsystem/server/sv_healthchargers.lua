if not SERVER then return end

local CHARGER_USE_INTERVAL  = 0.15
local CHARGER_JUICE_PER_TICK = 2
local INJECT_FRAC_PER_TICK = 0.04

local INJECTABLE_MEDICINES = {
    "MORPHINE", "FENTANYL", "ANTIBIOTICS", "CEFTRIAXONE",
    "BLOOD BAG", "SALINE", "NALOXONE", "PAINCREAM",
    "ANTIDEPRESSANTS", "INJECTION",
}

local cvChargerMed = GetConVar("woundsystem_charger_medicine")
    or CreateConVar("woundsystem_charger_medicine", "MORPHINE", FCVAR_ARCHIVE, "Medicine injected by HL2 health stations.")

local function IsHealthSystemEnabled()
    return not WoundSystemHealthEnabled or WoundSystemHealthEnabled()
end

local function GetChargerMedicine(charger)
    if IsValid(charger) then
        local override = charger:GetNWString("WoundSystem_ChargerMedicine", "")
        if override ~= "" then return string.upper(string.Trim(override)) end
    end
    local val = cvChargerMed and cvChargerMed:GetString() or "MORPHINE"
    return string.upper(string.Trim(val))
end

local function GetChargerJuice(charger)
    if not IsValid(charger) then return 0 end
    local juice = charger.GetInternalVariable and charger:GetInternalVariable("m_iJuice")
    if juice ~= nil then return tonumber(juice) or 0 end
    if not charger.WoundSystemMedicalJuiceInitialized then
        charger.WoundSystemMedicalJuiceInitialized = true
        charger:SetNWInt("WoundSystemMedicalJuice", 25)
    end
    return charger:GetNWInt("WoundSystemMedicalJuice", 0)
end

local function SetChargerJuice(charger, juice)
    if not IsValid(charger) then return end
    juice = math.max(math.floor(tonumber(juice) or 0), 0)
    if charger.SetSaveValue then charger:SetSaveValue("m_iJuice", juice) end
    charger:SetNWInt("WoundSystemMedicalJuice", juice)
end


-- returns 0-100 representing how much of this medicine the player actually needs right now
local function ComputeSmartJuice(ply, itemId)
    local body = WoundSystem.Health and WoundSystem.Health.BodyState and WoundSystem.Health.BodyState[ply]
    local limbs = WoundSystem.Health and WoundSystem.Health.PlayerLimbs and WoundSystem.Health.PlayerLimbs[ply]

    if not body then return 100 end

    if itemId == "MORPHINE" or itemId == "FENTANYL" or itemId == "PAINCREAM" then
        return math.Clamp(body.avgPain or 0, 0, 100)

    elseif itemId == "BLOOD BAG" then
        return math.Clamp(100 - (body.bloodVolume or 100), 0, 100)

    elseif itemId == "SALINE" then
        local vol = body.bloodVolume or 100
        local pressure = body.bloodPressure or 100
        return math.Clamp(math.max(100 - vol, 100 - pressure), 0, 100)

    elseif itemId == "ANTIBIOTICS" or itemId == "CEFTRIAXONE" then
        local worst = 0
        if limbs then
            for _, state in pairs(limbs) do
                worst = math.max(worst, state.infection or 0)
            end
        end
        return math.Clamp(worst, 0, 100)

    elseif itemId == "NALOXONE" or itemId == "NALTREXONE" then
        return math.Clamp((body.toxins or 0) * 1.5, 0, 100)

    elseif itemId == "ANTIDEPRESSANTS" then
        return math.Clamp(100 - (body.happiness or 50), 0, 100)

    elseif itemId == "INJECTION" then
        return math.Clamp(100 - (body.consciousness or 100), 0, 100)

    elseif itemId == "SLEEPINGPILLS" then
        return math.Clamp(100 - (body.tiredness or 0), 0, 100)
    end

    return 100
end
local function InjectPlayerFromCharger(ply, charger)
    if not IsHealthSystemEnabled() then return false end
    if not IsValid(charger) or not IsValid(ply) or not ply:Alive() then return false end

    local juice = ComputeSmartJuice(ply, GetChargerMedicine(charger))
    if juice <= 0 then return false end

    local itemId = GetChargerMedicine(charger)
    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    if not item then return false end

    local maxDur = WoundSystem.Items.GetMax and WoundSystem.Items.GetMax(itemId) or 100
    local juiceFrac = math.Clamp(juice / 100, 0, 1)
    local doseDurability = math.max(maxDur * INJECT_FRAC_PER_TICK * juiceFrac, 0.5)

    local fakeSlot = { type = "tool", toolName = itemId, durability = doseDurability }

    local use = item.use
    if use and type(use.canUse) == "function" then
        local ctx = { ply = ply, item = item, limb = "thorax", slot = fakeSlot }
        if use.canUse(ctx) == false then return false end
    end

    local applied = WoundSystem.UseMedicalItem and WoundSystem.UseMedicalItem(ply, itemId, "thorax", nil, fakeSlot)
    if applied == false then return false end

    -- juice is dynamic, no manual drain needed (it decreases naturally as player recovers)
    charger:EmitSound("items/medshot4.wav", 65, 100, 0.5, CHAN_ITEM)
    return true
end

hook.Add("PlayerUse", "WoundSystem_HealthCharger_Inject", function(ply, ent)
    if not IsValid(ent) or not IsValid(ply) or not ply:IsPlayer() then return end
    local class = ent:GetClass()
    if class ~= "item_healthcharger" and class ~= "func_healthcharger" then return end
    if not IsHealthSystemEnabled() then return end

    local now = CurTime()
    ent.WoundSystemNextMedicalRefill = ent.WoundSystemNextMedicalRefill or {}
    if (ent.WoundSystemNextMedicalRefill[ply] or 0) > now then return false end
    ent.WoundSystemNextMedicalRefill[ply] = now + CHARGER_USE_INTERVAL

    InjectPlayerFromCharger(ply, ent)
    return false
end)

concommand.Add("woundsys_set_charger_medicine", function(ply, _, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local medicine = args[1] and string.upper(string.Trim(args[1])) or ""
    if medicine == "" then return end
    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) then return end
    local class = ent:GetClass()
    if class ~= "item_healthcharger" and class ~= "func_healthcharger" then return end
    ent:SetNWString("WoundSystem_ChargerMedicine", medicine)
    if ent.SetSaveValue then ent:SetSaveValue("WoundSystem_ChargerMedicine", medicine) end
    ply:ChatPrint("[WoundSystem] Charger medicine set to: " .. medicine)
end)

WoundSystem.Charger = WoundSystem.Charger or {}
WoundSystem.Charger.InjectableMedicines = INJECTABLE_MEDICINES
WoundSystem.Charger.InjectPlayerFromCharger = InjectPlayerFromCharger

