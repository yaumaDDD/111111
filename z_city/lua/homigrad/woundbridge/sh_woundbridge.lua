--[[
	Z-City <-> WoundSystem bridge (shared part)

	WoundSystem (Casualties: Unknown Health System Beta) is the ONLY health simulation when the bridge is on.
	Z-City keeps everything that is not "health": armor, bullet penetration, ragdoll physics (hg.Fake / hg.FakeUp),
	weapons, movement/inertia. The legacy `ply.organism` table stays alive as a *shadow* that is rewritten from
	WoundSystem every Org Think, so the hundreds of Z-City files that read `org.*` keep working.

	Switch: convar `zc_woundsystem_bridge` (1 = WoundSystem is the health system, 0 = legacy Z-City organism).
	When the WoundSystem addon is not installed the bridge is automatically off.
]]

hg = hg or {}
hg.WoundBridge = hg.WoundBridge or {}
local WB = hg.WoundBridge

WB.cvBridge = WB.cvBridge or (ConVarExists("zc_woundsystem_bridge") and GetConVar("zc_woundsystem_bridge")
	or CreateConVar("zc_woundsystem_bridge", "1", FCVAR_ARCHIVE + FCVAR_REPLICATED,
		"1 = WoundSystem (Casualties: Unknown Health System) replaces the Z-City organism health simulation", 0, 1))

--- Is WoundSystem the active health back-end?
function WB.IsEnabled()
	if not WB.cvBridge:GetBool() then return false end
	if not WoundSystem or not WoundSystem.Health then return false end

	if SERVER then
		if WoundSystemHealthEnabled and WoundSystemHealthEnabled() == false then return false end
		if not WoundSystem.Health.HandleDamage then return false end -- old WoundSystem build without the bridge exports
	end

	return true
end

-- ZC organ -> WoundSystem limbs (used by amputation / sync)
WB.ZLimbToWS = {
	larm = "forearm_L",
	rarm = "forearm_R",
	lleg = "crus_L",
	rleg = "crus_R",
	head = "head",
}

-- WoundSystem limb -> ZC limb (for the shadow `org.<limb>` values)
WB.WSLimbToZ = {
	arm_L = "larm", forearm_L = "larm", hand_L = "larm",
	arm_R = "rarm", forearm_R = "rarm", hand_R = "rarm",
	thigh_L = "lleg", crus_L = "lleg", foot_L = "lleg",
	thigh_R = "rleg", crus_R = "rleg", foot_R = "rleg",
}

-- Z-City hitgroup -> WoundSystem limb (fallback when the physics bone can not be resolved)
WB.HitgroupToWS = {
	[HITGROUP_HEAD] = "head",
	[HITGROUP_CHEST] = "thorax",
	[HITGROUP_STOMACH] = "abdomen",
	[HITGROUP_LEFTARM] = "forearm_L",
	[HITGROUP_RIGHTARM] = "forearm_R",
	[HITGROUP_LEFTLEG] = "thigh_L",
	[HITGROUP_RIGHTLEG] = "thigh_R",
}
