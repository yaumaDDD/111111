--[[
	Z-City <-> WoundSystem bridge (client)

	* "Examine Body" button in the Z-City radial menu: opens the WoundSystem wound view whether or not
	  the player has taken damage (the button is always there).
	* On the client WB.IsEnabled() (sh_woundbridge.lua) is used by the Z-City HUD code to hide the legacy
	  organism visuals (pain/blood vignette, afflictions list, dislocation options...) that WoundSystem replaces.
]]

hg = hg or {}
hg.WoundBridge = hg.WoundBridge or {}
local WB = hg.WoundBridge

function WB.OpenWoundView()
	if not WoundSystem then return end

	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then return end

	-- let the radial menu fade out first, the wound view grabs the mouse as well
	timer.Simple(0.12, function()
		if not IsValid(ply) or not ply:Alive() then return end

		if WoundSystem.ToggleHealthHUD then
			WoundSystem.ToggleHealthHUD()
		elseif WoundSystem.OpenHealthHUD then
			WoundSystem.OpenHealthHUD()
		else
			RunConsoleCommand("woundsys_open_panel")
		end
	end)
end

hook.Add("radialOptions", "ZCity_WoundBridge_Inspect", function()
	if not (WB.IsEnabled and WB.IsEnabled()) then return end

	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then return end

	hg.radialOptions[#hg.radialOptions + 1] = {function() WB.OpenWoundView() end, "Examine Body"}
end)
