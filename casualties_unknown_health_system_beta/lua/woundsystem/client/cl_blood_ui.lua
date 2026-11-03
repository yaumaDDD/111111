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

net.Receive("WoundSystem_BloodVomit", function()
    if not WoundSystemClientEnabled() then return end

    sound.PlayFile("sound/bloodvomitwarning.ogg", "noblock noplay 2d", function(station)
        if IsValid(station) then
            station:SetVolume(3.6)
            station:Play()
        else
            surface.PlaySound("bloodvomitwarning.ogg")
        end
    end)
end)

net.Receive("WoundSystem_VomitWarning", function()
    if not WoundSystemClientEnabled() then return end

    sound.PlayFile("sound/vomitwarning.ogg", "noblock noplay 2d", function(station)
        if IsValid(station) then
            station:SetVolume(2.4)
            station:Play()
        else
            surface.PlaySound("vomitwarning.ogg")
        end
    end)
end)
