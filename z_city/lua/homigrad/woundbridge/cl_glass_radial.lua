-- RU: glass sync for unit menu (Examine Body) - radial removed per request, now in HUD action point
if CLIENT then
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
