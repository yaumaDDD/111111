-- Deprecated: radial heal moved to unit menu (Examine Body) per request
-- Kept for backward compatibility of console commands; no radialOptions hook
if CLIENT then
concommand.Add("woundsys_radial_heal", function(ply, cmd, args)
    local limb = args[1]
    if not limb or limb == "" then return end
    net.Start("WoundSystem_RadialHeal")
        net.WriteString(limb)
    net.SendToServer()
end)
end
