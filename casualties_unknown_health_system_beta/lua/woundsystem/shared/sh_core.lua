WoundSystem = WoundSystem or {}

WoundSystem.Name = WoundSystem.Name or "Casualties: Unknown"
WoundSystem.Version = WoundSystem.Version or "modular"

WoundSystem.NetStrings = WoundSystem.NetStrings or {
    "WoundSystem_UpdateLimb",
    "WoundSystem_UpdateCardio",
    "WoundSystem_ShrapnelStart",
    "WoundSystem_ShrapnelOpen",
    "WoundSystem_ShrapnelInput",
    "WoundSystem_ShrapnelState",
    "WoundSystem_ShrapnelClose",
    "WoundSystem_DislocationStart",
    "WoundSystem_DislocationOpen",
    "WoundSystem_DislocationInput",
    "WoundSystem_DislocationState",
    "WoundSystem_DislocationClose",
    "WoundSystem_DislocationDebug",
    "WoundSystem_BandageStart",
    "WoundSystem_BandageOpen",
    "WoundSystem_BandageInput",
    "WoundSystem_BandageClose",
    "WoundSystem_SyringeStart",
    "WoundSystem_SyringeOpen",
    "WoundSystem_SyringeInput",
    "WoundSystem_SyringeState",
    "WoundSystem_SyringeClose",
    "WoundSystem_AEDStart",
    "WoundSystem_AEDOpen",
    "WoundSystem_AEDInput",
    "WoundSystem_AEDState",
    "WoundSystem_AEDClose",
    "WoundSystem_MinigameAck",
    "WoundSystem_UnconsciousRagdoll",
    "WoundSystem_ResetRagdollCamera",
    "WoundSystem_WorldItemDrop",
    "WoundSystem_SpawnMedicalItem",
    "WoundSystem_WorldItemPickup",
    "WoundSystem_RequestRagdoll",
    "WoundSystem_SyncInventory",
    "WoundSystem_InventoryMove",
    "WoundSystem_UseMedicalItem",
    "WoundSystem_UseWorldMedicalItem",
    "WoundSystem_RemoveLimbStatus",
    "WoundSystem_HudMinigame",
    "WoundSystem_DismemberVisuals",
    "WoundSystem_ResetDismemberVisuals",
    "WoundSystem_BloodVomit",
    "WoundSystem_VomitWarning",
    "WoundSystem_LobotomyEffect",
    "WoundSystem_DamageFeedback",
    "WoundSystem_BallisticStagger",
    "WoundSystem_RagdollState",
    "WoundSystem_SkillLevelUp",
    "WoundSystem_SetServerConVar",
    "WoundSystem_AdminDebugAction"
}

function WoundSystem.NormalizeItemId(itemId)
    return string.upper(string.Trim(tostring(itemId or "")))
end

function WoundSystem.PoolNetStrings()
    if not SERVER then return end
    if not util or not util.AddNetworkString then return end

    WoundSystem._PooledNetStringSet = WoundSystem._PooledNetStringSet or {}

    for _, name in ipairs(WoundSystem.NetStrings) do
        if not WoundSystem._PooledNetStringSet[name] then
            util.AddNetworkString(name)
            WoundSystem._PooledNetStringSet[name] = true
        end
    end

    WoundSystem._PooledNetStrings = true
end

function WoundSystem.SafeInclude(path)
    if file and file.Exists and not file.Exists(path, "LUA") then
        MsgC(Color(255, 120, 80), "[Casualties: Unknown] Missing Lua file: " .. path .. "\n")
        return false
    end

    include(path)
    return true
end
