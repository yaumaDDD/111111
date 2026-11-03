-- WoundSystem blood UI settings + vomit warning sounds.
-- NOTE: all decorative WoundSystem blood effects (particles, stains, trails, fur blood) were removed.
-- World / body blood is now rendered only by Z-City (organism wounds / arterial wounds, driven from the bridge).
-- The colour ConVars below only tint the health-panel icons / moodles.

if not CLIENT then return end

CreateClientConVar("woundsys_blood_color", "alien_yellow", true, false, "Health UI blood icon colour: alien_yellow or red.")
CreateClientConVar("woundsys_blood_r", "255", true, false, "Blood Red component (0-255).", 0, 255)
CreateClientConVar("woundsys_blood_g", "236", true, false, "Blood Green component (0-255).", 0, 255)
CreateClientConVar("woundsys_blood_b", "58", true, false, "Blood Blue component (0-255).", 0, 255)

local function WoundSystemClientEnabled()
    local cvar = GetConVar("woundsys_enabled")
    if cvar then return cvar:GetBool() end
    return true
end

-- the warning / gagging sounds of the WoundSystem vomit are removed (the vomit sound itself is the Z-City one, played by the server)
net.Receive("WoundSystem_BloodVomit", function() end)
net.Receive("WoundSystem_VomitWarning", function() end)
