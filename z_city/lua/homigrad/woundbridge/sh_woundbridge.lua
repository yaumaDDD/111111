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

-- Z-City hitgroup -> WoundSystem limb (coarse fallback when no bone could be resolved)
WB.HitgroupToWS = {
	[HITGROUP_HEAD] = "head",
	[HITGROUP_CHEST] = "thorax",
	[HITGROUP_STOMACH] = "abdomen",
	[HITGROUP_LEFTARM] = "forearm_L",
	[HITGROUP_RIGHTARM] = "forearm_R",
	[HITGROUP_LEFTLEG] = "thigh_L",
	[HITGROUP_RIGHTLEG] = "thigh_R",
}

-- Every C:U limb (16), addressed by the exact Z-City / ValveBiped bone name.
-- Z-City keeps its own hitgroup + bone multipliers; this table only says WHERE the wound lands.
WB.ZBoneToWS = {
	["ValveBiped.Bip01_Head1"] = "head",
	["ValveBiped.Bip01_Neck1"] = "head",
	["ValveBiped.Bip01_L_UpperArm"] = "arm_L",
	["ValveBiped.Bip01_L_Forearm"] = "forearm_L",
	["ValveBiped.Bip01_L_Hand"] = "hand_L",
	["ValveBiped.Bip01_R_UpperArm"] = "arm_R",
	["ValveBiped.Bip01_R_Forearm"] = "forearm_R",
	["ValveBiped.Bip01_R_Hand"] = "hand_R",
	["ValveBiped.Bip01_L_Thigh"] = "thigh_L",
	["ValveBiped.Bip01_L_Calf"] = "crus_L",
	["ValveBiped.Bip01_L_Foot"] = "foot_L",
	["ValveBiped.Bip01_R_Thigh"] = "thigh_R",
	["ValveBiped.Bip01_R_Calf"] = "crus_R",
	["ValveBiped.Bip01_R_Foot"] = "foot_R",
	["ValveBiped.Bip01_Spine2"] = "thorax",
	["ValveBiped.Bip01_Spine4"] = "thorax",
	["ValveBiped.Bip01_Spine"] = "abdomen",
	["ValveBiped.Bip01_Spine1"] = "abdomen",
	["ValveBiped.Bip01_Pelvis"] = "abdomen",
}

-- All C:U limbs, used to iterate / validate glass and surface cuts on any part of the body.
WB.WSLimbs = {
	"head", "thorax", "abdomen",
	"arm_L", "forearm_L", "hand_L",
	"arm_R", "forearm_R", "hand_R",
	"thigh_L", "crus_L", "foot_L",
	"thigh_R", "crus_R", "foot_R",
}

-- Z-City surface props that mean GLASS (a subset of `bleedSurfaces` in sv_input.lua).
-- Glass gives a superficial cut AND glass shards; the other rough surfaces only give a cut.
WB.GlassSurfaces = {
	["glass"] = true,
	["glassbottle"] = true,
	["glassfloor"] = true,
	["brokenglass"] = true,
	["glass_breakable"] = true,
}

--- Exact Z-City bone -> C:U limb (case-insensitive, also accepts "bip01_l_hand" style names).
function WB.BoneToWS(bonename)
	if not bonename or bonename == "" then return end
	local name = string.lower(tostring(bonename))

	local exact = WB.ZBoneToWS[tostring(bonename)]
	if exact then return exact end
	for bone, limb in pairs(WB.ZBoneToWS) do
		if string.lower(bone) == name then return limb end
	end

	-- ragdoll / non ValveBiped bone naming
	local patterns = {
		{ "l_upperarm", "arm_L" }, { "r_upperarm", "arm_R" },
		{ "l_forearm", "forearm_L" }, { "r_forearm", "forearm_R" },
		{ "l_hand", "hand_L" }, { "r_hand", "hand_R" },
		{ "l_thigh", "thigh_L" }, { "r_thigh", "thigh_R" },
		{ "l_calf", "crus_L" }, { "r_calf", "crus_R" },
		{ "l_foot", "foot_L" }, { "r_foot", "foot_R" },
		{ "spine2", "thorax" }, { "spine4", "thorax" },
		{ "spine1", "abdomen" }, { "pelvis", "abdomen" },
		{ "head", "head" },
	}
	for _, entry in ipairs(patterns) do
		if string.find(name, entry[1], 1, true) then return entry[2] end
	end
end
