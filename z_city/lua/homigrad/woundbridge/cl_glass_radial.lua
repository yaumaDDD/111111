-- RU: круговой селектор - выбор конечности для извлечения осколка стекла (только вручную)
-- Мини-игра стартует исключительно после того как человек запустил её сам
if CLIENT then

local function HasGlassOnLimb(limbId)
    -- try to read from WoundSystem local limb cache if available
    -- fallback via organism flag? We store via net var from bridge
    -- Simple check: if local player organism sync had glass? Instead we check via NW or via C:U HUD data
    -- Instead we expose via net message query? For radial we just check if any limb known to have glass via local table
    if WoundSystemGlassMinigame and WoundSystemGlassMinigame._glassLimbs then
        return WoundSystemGlassMinigame._glassLimbs[limbId]
    end
    -- fallback: check BodyState via C:U client if exposed
    if LocalPlayer().organism and LocalPlayer().organism._glassLimb then return true end
    return false
end

-- Listen for shard updates from server
net.Receive("WoundSystem_GlassStart", function()
    -- handled in cl_glass.lua, this file just adds radial
end)

hook.Add("Initialize", "WoundSystem_GlassRadial_Init", function()
    hook.Remove("radialOptions", "WoundSystem_GlassShard")
end)

-- Build list of limbs that have glass: query server? For now we offer limb selector always if player has any glass
-- Server will validate, so radial can show all glass-bearing limbs
local allLimbs = {
    "head","thorax","abdomen",
    "arm_L","forearm_L","hand_L",
    "arm_R","forearm_R","hand_R",
    "thigh_L","crus_L","foot_L",
    "thigh_R","crus_R","foot_R"
}

local function PlayerHasAnyGlass()
    -- Check via WoundSystem client data via cl_health_gui? Use net request polling
    -- We can store latest server push via net
    return true -- we let server validate; show selector if we have at least 1 shard known? For MVP show always when player can have glass
end

-- Maintain known glass limbs via sync from server (we push on embed)
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

hook.Add("radialOptions", "WoundSystem_GlassShard", function()
    if not IsValid(LocalPlayer()) or not LocalPlayer():Alive() or (LocalPlayer().organism and LocalPlayer().organism.otrub) then return end

    -- Check if we have any glass shards locally; if not, skip to avoid spam
    local hasAny = false
    for _, limb in ipairs(allLimbs) do
        if WoundSystemGlassMinigame._glassLimbs[limb] then hasAny = true break end
    end
    -- If we don't know yet, ask server via small throttle
    if not hasAny then
        -- fallback: if player recently had glass embedding, still show selector for all limbs (server will reject if no glass)
        -- To avoid empty radial spam, we check if any limb pain high? Instead just show generic option
        -- Show generic extract option that opens limb chooser
        if table.Count(WoundSystemGlassMinigame._glassLimbs) == 0 then
            -- we haven't received sync yet, don't spam radial; allow manual command via console
            return
        end
    end

    -- Primary radial option: opens sub-menu to choose limb
    -- For simplicity, add per-limb options directly to radial
    for limbId,_ in pairs(WoundSystemGlassMinigame._glassLimbs) do
        local tbl = {
            function()
                RunConsoleCommand("woundsys_glass_extract", limbId)
            end,
            "Extract glass ("..limbId..")"
        }
        hg.radialOptions[#hg.radialOptions+1] = tbl
    end
end)

-- Fallback generic option when we don't have precise sync but player knows they have glass (e.g., HUD icon)
-- Also add console helper
concommand.Add("hg_glass_limbs", function()
    PrintTable(WoundSystemGlassMinigame._glassLimbs)
end)

end
