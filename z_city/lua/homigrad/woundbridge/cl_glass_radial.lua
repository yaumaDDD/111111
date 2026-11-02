-- RU: круговой селектор - выбор конечности для извлечения осколка стекла (только вручную)
-- Fixed: correct PNG handling moved to cl_glass.lua, radial now works with item-in-hands logic
if CLIENT then

local allLimbs = {
    "head","thorax","abdomen",
    "arm_L","forearm_L","hand_L",
    "arm_R","forearm_R","hand_R",
    "thigh_L","crus_L","foot_L",
    "thigh_R","crus_R","foot_R"
}

if not WoundSystemGlassMinigame then WoundSystemGlassMinigame = {} end
WoundSystemGlassMinigame._glassLimbs = WoundSystemGlassMinigame._glassLimbs or {}

net.Receive("WoundSystem_GlassSync", function()
    local cnt = net.ReadUInt(4)
    table.Empty(WoundSystemGlassMinigame._glassLimbs)
    for i=1,cnt do
        local limb = net.ReadString()
        WoundSystemGlassMinigame._glassLimbs[limb] = true
    end
end)

local function ClientHasGlassFallback(limbId)
    -- Direct check via WoundSystemClientState if available, without waiting for sync
    if WoundSystemClientState and WoundSystemClientState.PlayerLimbs and WoundSystemClientState.PlayerLimbs[limbId] then
        local st = WoundSystemClientState.PlayerLimbs[limbId]
        if st and st.customStatuses and st.customStatuses["GLASS_SHARD"] and tonumber(st.customStatuses["GLASS_SHARD"]) > 0 then return true end
        if st and (st.glassShards or 0) > 0 then return true end
    end
    return false
end

local function GetHasGlassSet()
    local has = {}
    local found = false
    for _, limb in ipairs(allLimbs) do
        if WoundSystemGlassMinigame._glassLimbs[limb] or ClientHasGlassFallback(limb) then
            has[limb] = true
            found = true
        end
    end
    return has, found
end

hook.Add("radialOptions", "WoundSystem_GlassShard", function()
    if not IsValid(LocalPlayer()) or not LocalPlayer():Alive() then return end
    if LocalPlayer().organism and LocalPlayer().organism.otrub then return end

    local hasSet, hasAny = GetHasGlassSet()
    if not hasAny then return end

    -- Add per-limb extraction options; they will be shown as separate radial slices
    for limbId,_ in pairs(hasSet) do
        local tbl = {
            function()
                RunConsoleCommand("woundsys_glass_extract", limbId)
            end,
            "Extract glass ("..limbId..")"
        }
        hg.radialOptions[#hg.radialOptions+1] = tbl
    end
end)

concommand.Add("hg_glass_limbs", function()
    PrintTable(WoundSystemGlassMinigame._glassLimbs)
    if WoundSystemClientState and WoundSystemClientState.PlayerLimbs then
        print("--- ClientState ---")
        for id, st in pairs(WoundSystemClientState.PlayerLimbs) do
            if st.customStatuses and st.customStatuses["GLASS_SHARD"] then print(id, st.customStatuses["GLASS_SHARD"]) end
        end
    end
end)

end
