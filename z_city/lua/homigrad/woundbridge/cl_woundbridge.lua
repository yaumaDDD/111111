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

	-- Glass shards: the player HIMSELF opens the minigame and picks the limb in a radial submenu.
	local shards = WoundSystemGlassShards or {}
	local total = 0
	for _, n in pairs(shards) do total = total + (n or 0) end
	if total > 0 then
		hg.radialOptions[#hg.radialOptions + 1] = {function()
			local current = WoundSystemGlassShards or {}
			local commands = {}
			for _, limbId in ipairs(WB.WSLimbs or {}) do
				local n = current[limbId] or 0
				if n > 0 then
					local id = limbId
					commands[#commands + 1] = {function()
						net.Start("WoundSystem_GlassRadial")
							net.WriteString(id)
						net.SendToServer()
					end, (WB.LimbNames and WB.LimbNames[id] or id) .. " (" .. n .. ")"}
				end
			end
			if #commands > 0 and hg.CreateRadialMenu then hg.CreateRadialMenu(commands) end
		end, "Remove glass"}
	end
end)
