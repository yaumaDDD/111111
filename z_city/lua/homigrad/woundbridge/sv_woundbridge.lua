--[[
	Z-City <-> WoundSystem bridge (server)

	See sh_woundbridge.lua for the overview. Short version:

	  damage     Z-City `homigrad-damage` (armor, penetration, ragdoll redirect, blood FX, forces) ->
	             WB.ApplyDamage -> WoundSystem.Health.HandleDamage
	  health     WoundSystem only. `ply.organism` is a shadow, rewritten by WB.Sync every Org Think
	  ragdoll    Z-City physics (hg.Fake / hg.FakeUp); WoundSystem decides *when* (WB.CreateRagdoll / WB.RestoreRagdoll)
	  medicine   Z-City SWEPs -> WB.SwepHeal -> WoundSystem.Health.ApplyItemToBody
]]

hg = hg or {}
hg.WoundBridge = hg.WoundBridge or {}
local WB = hg.WoundBridge

local CurTime, IsValid, math = CurTime, IsValid, math

WB.cvDamageScale = WB.cvDamageScale or (ConVarExists("zc_wound_damage_scale") and GetConVar("zc_wound_damage_scale")
	or CreateConVar("zc_wound_damage_scale", "1", FCVAR_ARCHIVE,
		"Multiplier for the damage Z-City forwards to WoundSystem (after armor and penetration)", 0, 20))

WB.cvCollisionScale = WB.cvCollisionScale or (ConVarExists("zcity_wounds_collision_scale") and GetConVar("zcity_wounds_collision_scale")
	or CreateConVar("zcity_wounds_collision_scale", "1", FCVAR_ARCHIVE,
		"Multiplier for the impact force of ragdoll collisions fed into the WoundSystem impact model", 0, 20))

WB.cvMinigame = WB.cvMinigame or (ConVarExists("zc_woundsystem_minigames") and GetConVar("zc_woundsystem_minigames")
	or CreateConVar("zc_woundsystem_minigames", "1", FCVAR_ARCHIVE,
		"1 = Z-City medical SWEPs open the WoundSystem minigame (bandage / syringe), the effect is applied only after it was completed", 0, 1))

WB.cvDebug = WB.cvDebug or (ConVarExists("zc_woundsystem_bridge_debug") and GetConVar("zc_woundsystem_bridge_debug")
	or CreateConVar("zc_woundsystem_bridge_debug", "0", FCVAR_ARCHIVE, "Print bridge debug output", 0, 1))

-- Glass shards: only Z-City glass damage creates them (the old WoundSystem shrapnel stays removed).
WB.cvGlass = WB.cvGlass or (ConVarExists("zc_woundsystem_glass") and GetConVar("zc_woundsystem_glass")
	or CreateConVar("zc_woundsystem_glass", "1", FCVAR_ARCHIVE,
		"1 = Z-City glass damage leaves superficial cuts and glass shards in a C:U limb", 0, 1))

local function dbg(...)
	if WB.cvDebug:GetBool() then print("[ZC<->WoundSystem]", ...) end
end

local function Health() return WoundSystem and WoundSystem.Health end

-----------------------------------------------------------------------------------------------------------------------
-- helpers
-----------------------------------------------------------------------------------------------------------------------

--- WoundSystem body state of a player (cardio/brain/consciousness/...)
function WB.GetBody(ply)
	local H = Health()
	if not H or not IsValid(ply) then return end
	local states = H.BodyState
	return (states and states[ply]) or (H.GetBody and H.GetBody(ply)) or nil
end

--- WoundSystem limb table of a player
function WB.GetLimbs(ply)
	local H = Health()
	if not H or not IsValid(ply) then return end
	return (H.GetLimbs and H.GetLimbs(ply)) or (H.PlayerLimbs and H.PlayerLimbs[ply])
end

--- The living player that `ent` represents: the player himself or his Z-City fake ragdoll
function WB.GetPlayer(ent)
	if not IsValid(ent) then return end

	if ent:IsPlayer() then
		return ent:Alive() and ent or nil
	end

	if ent:IsRagdoll() and hg.RagdollOwner then
		local ply = hg.RagdollOwner(ent)
		if IsValid(ply) and ply:IsPlayer() and ply:Alive() and ply.FakeRagdoll == ent then return ply end
	end
end

--- Bridge is on AND `ply` is a living player handled by WoundSystem
function WB.IsBridged(ply)
	return WB.IsEnabled() and IsValid(ply) and ply:IsPlayer() and ply:Alive()
end

local function LimbAlive(limbs, id)
	local l = limbs and limbs[id]
	return l and not l.dismembered
end

--- Resolve the WoundSystem limb from a Z-City hit (bone name first, hitgroup as the fallback)
function WB.ResolveLimb(ply, bonename, hitgroup)
	local H = Health()
	-- exact Z-City bone -> one of the 16 C:U limbs (arm/forearm/hand, thigh/crus/foot, ...)
	local limb = WB.BoneToWS and WB.BoneToWS(bonename) or nil

	if bonename and bonename ~= "" and H and H.RagdollBoneNameToLimb then
		limb = H.RagdollBoneNameToLimb(bonename)
	end

	if not limb and hitgroup then
		limb = (H and H.Const and H.Const.HitgroupToLimb and H.Const.HitgroupToLimb[hitgroup]) or WB.HitgroupToWS[hitgroup]
	end

	return limb
end

--- C:U limb closest to a world position (standing-player hits / glass breaks), all 16 limbs.
function WB.NearestLimb(ply, pos, fallback)
	if not IsValid(ply) or not pos then return fallback end
	if pos == vector_origin or pos:DistToSqr(ply:GetPos()) > 300 * 300 then return fallback end

	local best, bestDist = nil, math.huge
	for i = 0, (ply:GetBoneCount() or 1) - 1 do
		local limb = WB.BoneToWS and WB.BoneToWS(ply:GetBoneName(i)) or nil
		if limb then
			local bonePos = ply:GetBonePosition(i)
			if bonePos then
				local dist = bonePos:DistToSqr(pos)
				if dist < bestDist then bestDist, best = dist, limb end
			end
		end
	end

	return best or fallback
end

--- Lowest bone = the exact C:U limb the player landed on.
function WB.LowestLimb(ply, fallback)
	if not IsValid(ply) then return fallback end

	local best, bestZ = nil, math.huge
	for i = 0, (ply:GetBoneCount() or 1) - 1 do
		local limb = WB.BoneToWS and WB.BoneToWS(ply:GetBoneName(i)) or nil
		if limb then
			local bonePos = ply:GetBonePosition(i)
			if bonePos and bonePos.z < bestZ then bestZ, best = bonePos.z, limb end
		end
	end

	return best or fallback
end

-----------------------------------------------------------------------------------------------------------------------
-- DAMAGE
-----------------------------------------------------------------------------------------------------------------------

local function CloneDamageInfo(src, damage)
	local dmg = DamageInfo()
	dmg:SetDamage(damage)
	dmg:SetDamageType(src:GetDamageType())

	local attacker, inflictor = src:GetAttacker(), src:GetInflictor()
	if IsValid(attacker) then dmg:SetAttacker(attacker) end
	if IsValid(inflictor) then dmg:SetInflictor(inflictor) end

	dmg:SetDamageForce(src:GetDamageForce())
	dmg:SetDamagePosition(src:GetDamagePosition())
	if src.GetReportedPosition and dmg.SetReportedPosition then dmg:SetReportedPosition(src:GetReportedPosition()) end
	if src.GetAmmoType and dmg.SetAmmoType then dmg:SetAmmoType(src:GetAmmoType()) end

	return dmg
end

--- Feed one Z-City hit into WoundSystem.
--- ply      living player (already resolved)
--- rawDamage damage after armor/penetration, BEFORE Z-City's per-bone bullet multiplier (WoundSystem has its own)
--- onRagdoll true when the hit landed on the fake ragdoll (limb from the physics bone), false for a standing player
---           (limb from the engine hitgroup: the bone of a player trace is meaningless)
--- Returns true when WoundSystem processed the hit.
function WB.ApplyDamage(ply, dmgInfo, bonename, hitgroup, rawDamage, onRagdoll)
	if not WB.IsBridged(ply) then return false end

	local H = Health()
	if not H or not H.HandleDamage then return false end
	if dmgInfo:IsDamageType(DMG_DISSOLVE) then return false end

	local damage = (rawDamage or dmgInfo:GetDamage()) * WB.cvDamageScale:GetFloat()
	if damage <= 0 then return true end

	local clone = CloneDamageInfo(dmgInfo, damage)

	-- explosions hit the whole body: let WoundSystem pick / spread, otherwise pin the exact limb that was hit
	local limb
	if not dmgInfo:IsDamageType(DMG_BLAST) then
		if onRagdoll then
			limb = WB.ResolveLimb(ply, bonename, hitgroup)
		else
			limb = hitgroup and WB.HitgroupToWS[hitgroup] or nil -- nil: WoundSystem decides (blunt/generic spreads over the body)
			-- the wound itself lands on the nearest of ALL 16 C:U limbs, not on one coarse zone
			limb = WB.NearestLimb(ply, dmgInfo:GetDamagePosition(), limb)
		end
	end

	ply._WoundBridgeLimb = limb
	WB.InDamage = true
	local ok, err = pcall(H.HandleDamage, ply, clone)
	WB.InDamage = false
	ply._WoundBridgeLimb = nil

	if not ok then
		ErrorNoHalt("[ZC<->WoundSystem] HandleDamage failed: " .. tostring(err) .. "\n")
		return false
	end

	dbg("damage", ply, limb, damage)

	-- make the result visible to Z-City at once (otrub / fake / death are evaluated from the shadow)
	if ply:Alive() and ply.organism then
		WB.Sync(ply, ply.organism)
	end

	return true
end

-----------------------------------------------------------------------------------------------------------------------
-- COLLISIONS, FALLS  (Z-City filters/structure, the damage itself is the C:U impact model)
-----------------------------------------------------------------------------------------------------------------------
--- Rough surfaces / glass cut the limb that hit them (Z-City: `bleedSurfaces`, 50%)
function WB.SurfaceCut(ply, limbId, force, surface, zcDamage)
	-- GLASS surfaces give a cut + glass shards; everything else keeps the old cut below.
	if surface and WB.GlassSurfaces[surface] then
		return WB.GlassCut(ply, limbId, zcDamage or force, surface)
	end

	local H = Health()
	local limbs = WB.GetLimbs(ply)
	local body = WB.GetBody(ply)
	local l = limbs and limbs[limbId]
	if not l or l.dismembered then return false end

	local jump = (body and body.jumpSpeed) or 6.5
	if force <= jump * 1.2 or math.random(2) ~= 1 then return false end

	l.skin = math.Clamp((l.skin or 100) - force * 0.8, 0, 100)
	l.bleed = math.Clamp((l.bleed or 0) + force * 0.2, 0, 100)
	if H.Fn and H.Fn.ClearLimbBandage then H.Fn.ClearLimbBandage(l) end
	if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end

	return true
end

--- Glass got into a C:U limb: superficial cut (Z-City AddWoundManual semantics) + 1..5 shards.
--- Damage and the limb both come from Z-City; WoundSystem only stores the result.
function WB.GlassCut(ply, limbId, zcDamage, source)
	if not WB.IsBridged(ply) then return false end
	if WB.cvGlass and not WB.cvGlass:GetBool() then return false end

	local H = Health()
	local limbs = WB.GetLimbs(ply)
	if not limbs then return false end

	limbId = limbId or "hand_R"
	if not limbs[limbId] then
		limbId = (H.Fn and H.Fn.ResolveLivingLimb and H.Fn.ResolveLivingLimb(ply, limbId)) or "thorax"
	end
	local l = limbs[limbId]
	if not l or l.dismembered then return false end

	local dmg = math.Clamp((tonumber(zcDamage) or 0) * WB.cvDamageScale:GetFloat(), 5, 100)
	l.skin = math.Clamp((l.skin or 100) - dmg * 0.6, 0, 100)
	l.bleed = math.Clamp((l.bleed or 0) + dmg * 0.25, 0, 100)
	if H.Fn and H.Fn.ClearLimbBandage then H.Fn.ClearLimbBandage(l) end
	if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end

	local count = math.Clamp(math.ceil(dmg / 30), 1, 5)
	if WB.AddGlass then WB.AddGlass(ply, limbId, count) end

	if ply.organism then WB.Sync(ply, ply.organism) end
	dbg("glass cut", ply, limbId, source, dmg, count)
	return true
end

--- Standard Z-City glass break (func_breakable_surf / MAT_GLASS, cs_office windows).
--- Only close-range breaks count; a bullet through a window from afar puts no glass in the hand.
function WB.GlassBreak(attacker, dmgInfo, glassEnt)
	if not WB.IsEnabled() then return false end

	local ply = WB.GetPlayer(attacker)
	if not ply and dmgInfo then
		local inf = dmgInfo:GetInflictor()
		ply = WB.GetPlayer(inf)
		if not ply and IsValid(inf) and inf.GetOwner then ply = WB.GetPlayer(inf:GetOwner()) end
	end
	if not WB.IsBridged(ply) then return false end

	local dmgPos = dmgInfo and dmgInfo:GetDamagePosition() or nil
	local pos = (dmgPos and dmgPos ~= vector_origin) and dmgPos
		or (IsValid(glassEnt) and glassEnt.NearestPoint and glassEnt:NearestPoint(ply:GetPos())) or nil
	if not pos or pos:DistToSqr(ply:GetPos()) > 200 * 200 then return false end

	local now = CurTime()
	ply._WBGlassBreak = ply._WBGlassBreak or {}
	local key = IsValid(glassEnt) and glassEnt:EntIndex() or 0
	if (ply._WBGlassBreak[key] or 0) + 0.6 > now then return false end
	ply._WBGlassBreak[key] = now

	local zcDamage = math.max((dmgInfo and dmgInfo:GetDamage()) or 10, 10)
	local limbId = WB.NearestLimb(ply, pos, "hand_R")
	return WB.GlassCut(ply, limbId, zcDamage, "breakable_glass")
end

--- Impact force of a ragdoll collision in C:U units (same conversion C:U uses for its own ragdoll: speed * |cos| / 50)
function WB.ImpactForce(ply, speed, dot, massK)
	local body = WB.GetBody(ply)
	local jump = (body and body.jumpSpeed) or 6.5
	return math.Clamp((speed or 0) * (dot or 1) * (massK or 1) / 50, 0, jump * 7) * WB.cvCollisionScale:GetFloat()
end

--- One impact on a limb through the C:U impact model (muscle, pain, skin, bleeding, dislocation, fracture, internal bleeding, head).
--- Returns true when the bridge handled it.
function WB.ApplyImpact(ply, limbId, force, surface, zcDamage)
	if not WB.IsBridged(ply) then return false end

	local H = Health()
	if not (H and H.ProcessImpactDamage) then return false end

	local body = WB.GetBody(ply)
	if not body then return false end
	if body.isGodMode then return true end

	local jump = body.jumpSpeed or 6.5
	if force <= jump then return true end

	limbId = limbId or "thorax"
	if H.Fn and H.Fn.ResolveLivingLimb then limbId = H.Fn.ResolveLivingLimb(ply, limbId) or limbId end

	-- the same per-limb cooldown C:U uses for physics impacts
	local now = CurTime()
	ply._nextLimbPhysicsDamage = ply._nextLimbPhysicsDamage or {}
	if (ply._nextLimbPhysicsDamage[limbId] or 0) > now then return true end
	ply._nextLimbPhysicsDamage[limbId] = now + 0.22

	H.ProcessImpactDamage(ply, limbId, force)
	if surface then WB.SurfaceCut(ply, limbId, force, surface, zcDamage) end

	if ply.organism then WB.Sync(ply, ply.organism) end
	dbg("impact", ply, limbId, force)

	return true
end

--- Ragdoll collision (Z-City `velocityDamage`, after its speed / throttling filters).
--- `dmgInfo` is Z-City's own DamageInfo: its damage / hitgroup / bone multipliers are the only source.
function WB.ApplyCollision(ply, dmgInfo, speed, dot, massK, attacker, bonename, hitgroup, surface)
	if not WB.IsBridged(ply) then return false end

	local limb = WB.ResolveLimb(ply, bonename, hitgroup)
	if IsValid(attacker) and attacker:IsPlayer() then ply._WBLastCollisionAttacker = attacker end

	local zcDamage = (dmgInfo and dmgInfo:GetDamage()) or 0
	return WB.ApplyImpact(ply, limb, WB.ImpactForce(ply, speed, dot, massK), surface, zcDamage)
end

--- Fall of a standing player (engine DMG_FALL): the C:U fall model (landing speed -> impact force on feet / shins).
--- While in the fake ragdoll the landing is already counted by the ragdoll collisions.
function WB.ApplyFall(ply, dmgInfo)
	if not WB.IsBridged(ply) then return false end
	if IsValid(ply.FakeRagdoll) then return true end

	-- no C:U fall model (it tore skin / caused fractures): only a slight bruise on the landed limb
	WB.ApplyFallBruise(ply, dmgInfo)
	return true
end

--- Trauma from a fall, using ONLY Z-City's DMG_FALL damage. No wounds, no bleeding,
--- no fractures / dislocations / internal bleeding: muscle damage + persistent pain
--- on the exact limb that hit the ground; the pain is removed only by Z-City painkillers.
function WB.ApplyFallBruise(ply, dmgInfo)
	local H = Health()
	local limbs = WB.GetLimbs(ply)
	if not limbs then return false end

	local limbId = WB.LowestLimb(ply, nil)
		or WB.ResolveLimb(ply, nil, ply.LastHitGroup and ply:LastHitGroup() or nil)
		or "foot_R"
	if H.Fn and H.Fn.ResolveLivingLimb then limbId = H.Fn.ResolveLivingLimb(ply, limbId) or limbId end

	local l = limbs[limbId]
	if not l or l.dismembered then return false end

	local zcDamage = math.Clamp((dmgInfo and dmgInfo:GetDamage() or 0) * WB.cvDamageScale:GetFloat(), 0, 100)
	local bruise = math.Clamp(zcDamage * 0.6, 4, 45)

	l.muscle = math.Clamp((l.muscle or 100) - bruise * 1.1, 0, 100)
	l.pain = math.Clamp((l.pain or 0) + bruise, 0, 100)
	WB.AddPersistentPain(ply, limbId, bruise)
	local body = WB.GetBody(ply)
	if body then body.adrenaline = math.Clamp((body.adrenaline or 0) + bruise * 0.15, 0, 100) end

	if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end
	if H.SendCardioUpdate then H.SendCardioUpdate(ply, true) end
	if ply.organism then WB.Sync(ply, ply.organism) end
	dbg("fall bruise", ply, limbId, zcDamage, bruise)
	return true
end

--- Z-City AddWoundManual (gibs, glass, explosion cuts): turn it into WoundSystem bleeding
function WB.AddWoundManual(ent, dmgBlood, bone)
	local ply = WB.GetPlayer(ent)
	if not WB.IsBridged(ply) then return false end

	local H = Health()
	local limbs = WB.GetLimbs(ply)
	if not limbs then return true end

	local bonename = bone
	if isnumber(bone) then bonename = ent:GetBoneName(bone) end

	local limbId = WB.ResolveLimb(ply, bonename, nil) or "thorax"
	local limb = limbs[limbId or "thorax"]
	if limb and not limb.dismembered then
		limb.bleed = math.Clamp((limb.bleed or 0) + (tonumber(dmgBlood) or 0) * 0.04, 0, 100)
		if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId or "thorax", true) end
	end

	return true
end

--- Z-City AmputateLimb for a living player -> WoundSystem dismemberment
function WB.Amputate(org, zlimb)
	if not WB.IsEnabled() then return false end

	local ply = org and org.owner
	if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false end

	local wsLimb = WB.ZLimbToWS[zlimb]
	if not wsLimb then return false end

	if WoundSystem.Dismember then WoundSystem.Dismember(ply, wsLimb) end
	return true -- handled (even if the limb was already gone) - do not run the legacy gore
end

-----------------------------------------------------------------------------------------------------------------------
-- SHADOW ORGANISM  (WoundSystem -> ply.organism)
-----------------------------------------------------------------------------------------------------------------------

local function Strength(H, ply, names)
	local lf = H.LimbForce
	if lf and lf.AverageGroupStrength then
		local ok, val = pcall(lf.AverageGroupStrength, ply, names)
		if ok and isnumber(val) then return math.Clamp(val, 0, 1) end
	end
	return 1
end

local armL, armR = {"arm_L", "forearm_L", "hand_L"}, {"arm_R", "forearm_R", "hand_R"}
local legL, legR = {"thigh_L", "crus_L", "foot_L"}, {"thigh_R", "crus_R", "foot_R"}

local function AnyDislocated(limbs, names)
	for _, id in ipairs(names) do
		local l = limbs[id]
		if type(l) == "table" and l.dislocated and not l.dismembered then return true end
	end
	return false
end

local function MovementMult(H, ply, body)
	local mult = 1
	local bf = H.CAS3BodyFeel
	if bf and bf.GetMovementMultipliers then
		local ok, speed = pcall(bf.GetMovementMultipliers, ply, body, WB.GetLimbs(ply), true)
		if ok and isnumber(speed) then mult = speed end
	end

	if (body.ballisticStaggerUntil or 0) > CurTime() then
		local tier = math.Clamp(tonumber(body.ballisticStaggerTier) or 1, 1, 3)
		mult = math.min(mult, tier == 1 and 0.42 or tier == 2 and 0.28 or 0.22)
	end

	return math.Clamp(mult, 0.02, 1.25)
end

--- Rewrite the legacy organism of `ply` from WoundSystem. Cheap, safe to call at any time.
function WB.Sync(ply, org)
	if not IsValid(ply) or not org then return end

	local H = Health()
	local body = WB.GetBody(ply)
	if not H or not body then return end

	local limbs = WB.GetLimbs(ply)
	ply._WBLimbSnapshot = limbs or ply._WBLimbSnapshot

	org.alive = ply:Alive()
	org.isPly = true

	local otrub = body.unconscious == true or body.brainDead == true
	org.otrub = otrub
	org.needotrub = otrub

	org.consciousness = math.Clamp((body.consciousness or 100) / 100, 0, 1)
	org.brain = math.Clamp(1 - (body.brainHealth or 100) / 100, 0, 1)
	org.pain = math.max(body.avgPain or 0, 0)
	org.blood = math.Clamp(body.bloodVolume or 100, 0, 200) / 100 * 5000
	org.pulse = body.heartRate or 70
	org.shock = math.Clamp((body.shock or 0) * 0.7, 0, 70)
	org.bleed = math.max(body.totalBleedSpeed or 0, 0)
	org.canmove = not otrub
	org.canmovehead = not otrub

	if org.stamina then
		org.stamina[1] = math.Clamp((body.stamina or 100) / 100, 0, 1) * (org.stamina.max or 180)
		org.stamina.subadd = 0 -- Z-City stamina costs are not charged to WoundSystem stamina (WoundSystem has its own)
	end

	-- limbs: show WoundSystem limb strength to the Z-City code that reads org.larm/lleg (aim sway, limp...)
	if limbs then
		org.larm = 1 - Strength(H, ply, armL)
		org.rarm = 1 - Strength(H, ply, armR)
		org.lleg = 1 - Strength(H, ply, legL)
		org.rleg = 1 - Strength(H, ply, legR)

		local la = not (LimbAlive(limbs, "forearm_L") and LimbAlive(limbs, "arm_L"))
		local ra = not (LimbAlive(limbs, "forearm_R") and LimbAlive(limbs, "arm_R"))
		local ll = not (LimbAlive(limbs, "crus_L") and LimbAlive(limbs, "thigh_L"))
		local rl = not (LimbAlive(limbs, "crus_R") and LimbAlive(limbs, "thigh_R"))
		local ha = not LimbAlive(limbs, "head")

		if la ~= org.larmamputated or ra ~= org.rarmamputated or ll ~= org.llegamputated
			or rl ~= org.rlegamputated or ha ~= org.headamputated then
			ply.fullsend = true
		end

		org.larmamputated, org.rarmamputated = la, ra
		org.llegamputated, org.rlegamputated = ll, rl
		org.headamputated = ha
	end

	-- legacy organ hits (bullet trace through the Z-City organs) must not leave anything that Z-City reads as its own health
	org.spine1, org.spine2, org.spine3 = 0, 0, 0
	org.pelvis, org.skull, org.chest = 0, 0, 0
	-- dislocations: the Z-City flags (radial "Fix dislocation", movement, pain, ragdoll arms) follow the C:U limbs
	local dl, dr, al, ar = false, false, false, false
	if limbs then
		dl, dr = AnyDislocated(limbs, legL), AnyDislocated(limbs, legR)
		al, ar = AnyDislocated(limbs, armL), AnyDislocated(limbs, armR)
	end
	if dl ~= org.llegdislocation or dr ~= org.rlegdislocation or al ~= org.larmdislocation or ar ~= org.rarmdislocation then
		ply.fullsend = true
	end
	org.llegdislocation, org.rlegdislocation = dl, dr
	org.larmdislocation, org.rarmdislocation = al, ar

	-- ragdoll decision of WoundSystem as seen by the Z-City fake code
	local needfake = body.unconscious or body.fallingRagdoll or (org.llegamputated or org.rlegamputated)
		or org.blood < 2700 or (org.stun or 0) > CurTime()
	org.needfake = needfake and true or false
	org.fake = org.needfake

	-- movement: one multiplier computed by WoundSystem, applied by Z-City's own movement code (sh_inertia.lua)
	org.wsmovemult = MovementMult(H, ply, body)

	return body
end

-----------------------------------------------------------------------------------------------------------------------
-- THINK  (replaces the legacy `Org Think` "Main" hook for players)
-----------------------------------------------------------------------------------------------------------------------

--- "Reset organism" (admin tool / console): a fresh WoundSystem body + limbs, the Z-City side state is cleared too.
--- Returns true when WoundSystem handled it (otherwise the caller falls back to the legacy hg.organism.Clear).
function WB.ResetOrganism(ent)
	if not WB.IsEnabled() then return false end

	local ply = WB.GetPlayer(ent) or (IsValid(ent) and ent:IsPlayer() and ent:Alive() and ent) or nil
	if not ply then return false end

	local H = Health()
	if not (H and H.ResetPlayer) or not H.ResetPlayer(ply) then return false end
	if WB.ClearGlass then WB.ClearGlass(ply) end
	WB.ClearPersistentPain(ply)

	local org = ply.organism
	if org then
		hg.organism.Clear(org) -- legacy hooks: handcuffs, poisons, taser, virus ...
		WB.Sync(ply, org)
		org.needotrub, org.otrub, org.needfake, org.fake = false, false, false, false
	end

	-- stand up if the old state kept him on the floor
	WB.RestoreRagdoll(ply, WB.GetBody(ply), false)

	ply.fullsend = true
	if org then
		hg.send_bareinfo(org)
		hg.send_organism(org, ply)
	end

	return true
end

-----------------------------------------------------------------------------------------------------------------------
-- DISLOCATIONS  (Z-City structure: radial "Fix dislocation" -> hg_fixdislocation, chance based, tries, pain; C:U limbs)
-----------------------------------------------------------------------------------------------------------------------
local DISLOC_GROUPS = {
	[1] = {{"thigh_L", "crus_L", "foot_L"}, {"thigh_R", "crus_R", "foot_R"}}, -- legs: left first, like Z-City
	[2] = {{"arm_L", "forearm_L", "hand_L"}, {"arm_R", "forearm_R", "hand_R"}}, -- arms
}

local unlucky_dislocations = {
	"Why can't I fix this goddamn dislocation...",
	"Please... why is it so hard.",
	"Just go back in place already...",
	"This is irritating",
	"I should try again",
}

local finally_fixed = {"Finally.", "That was harder than I thought", "One dislocation away."}

local function FixDislocatedGroup(target, names, fixer)
	local H = Health()
	local limbs = WB.GetLimbs(target)
	local body = WB.GetBody(target)
	if not (limbs and body) then return end

	local fixerOrg = fixer.organism or {}
	local self_fix = fixer == target
	local analgesia = math.Clamp((body.opiateAmount or 0) / 300, 0, 1.5) -- C:U opiates make the reduction less painful and easier

	-- same odds as Z-City's fixlimb()
	local roll = math.random(100)
	local need = 97 + (self_fix and 0 or (fixerOrg.pain or 0)) - analgesia * 50 - (self_fix and 0 or 30) - (fixer.tries or 0) * 10
		- (fixer.Profession == "doctor" and 100 or 0)
		- ((self_fix and (IsValid(target.FakeRagdoll) or (target.Crouching and target:Crouching()))) and 10 or 0)

	-- the joint that was put back (or failed to) takes the pain
	local painId = names[1]
	for _, id in ipairs(names) do
		if type(limbs[id]) == "table" and limbs[id].dislocated then painId = id break end
	end

	local function AddPain(amount)
		local l = limbs[painId]
		if type(l) ~= "table" then return end
		l.pain = math.Clamp((l.pain or 0) + amount, 0, 100)
		if H.SendLimbUpdate then H.SendLimbUpdate(target, painId, true) end
	end

	if roll > need then
		for _, id in ipairs(names) do
			if H.SetLimbDislocated and type(limbs[id]) == "table" and limbs[id].dislocated then
				H.SetLimbDislocated(target, id, false, 0, true)
			end
		end

		AddPain(5 * math.random(1, 3))
		target:EmitSound("physics/flesh/flesh_impact_hard6.wav", 65)

		if self_fix and (fixer.tries or 0) > 3 and math.random(3) == 1 and fixer.Notify then
			fixer:Notify(finally_fixed[math.random(#finally_fixed)], 1, "dislocations_unlucky", 1, nil, Color(255, 255, 255, 255))
		end
		fixer.tries = 0
	else
		fixer.tries = (fixer.tries or 0) + 1
		AddPain(12 * math.random(1, 3))
		target:EmitSound("physics/body/body_medium_impact_soft" .. math.random(7) .. ".wav", 65)

		if fixer.Profession ~= "doctor" and math.random(5) == 1 then
			AddPain(25) -- clumsy hands hurt it more (Z-City: a club hit on the limb)
		end

		if self_fix and fixer.tries > 3 and math.random(3) == 1 and fixer.Notify then
			fixer:Notify(unlucky_dislocations[math.random(#unlucky_dislocations)], 1, "dislocations_unlucky", 1, nil, Color(255, 255, 255, 255))
		end
	end

	if target.organism then WB.Sync(target, target.organism) end
end

--- hg_fixdislocation <1 legs | 2 arms> [1 = the one the fixer looks at]. Returns true when handled by the bridge.
function WB.FixDislocation(fixer, args)
	if not WB.IsEnabled() or not IsValid(fixer) or not fixer:Alive() then return false end

	local ent = fixer
	if args and args[2] and math.Round(tonumber(args[2]) or 0) == 1 then
		ent = hg.eyeTrace(fixer).Entity
	end

	local target = WB.GetPlayer(ent) or ((IsValid(ent) and ent.organism and IsValid(ent.organism.owner) and WB.GetPlayer(ent.organism.owner)) or nil)
	if not target then return false end

	local forg = fixer.organism
	if not forg or forg.otrub then return true end
	if (fixer.tried_fixing_limb or 0) > CurTime() then return true end
	if not forg.canmove or not forg.canmovehead or (forg.pain or 0) > 60 then return true end
	fixer.tried_fixing_limb = CurTime() + (forg.pain or 0) / 30

	local groups = DISLOC_GROUPS[math.Round(tonumber(args and args[1]) or 0)]
	if not groups then return true end

	local limbs = WB.GetLimbs(target)
	if not limbs then return true end

	for _, names in ipairs(groups) do
		if AnyDislocated(limbs, names) then
			FixDislocatedGroup(target, names, fixer)
			break
		end
	end

	return true
end

--- Pain that does NOT fade by itself. WoundSystem pulls limb pain back to ~15 every tick,
--- so the bridge keeps this floor. The ONLY way to remove it is a Z-City painkiller
--- (MORPHINE / FENTANYL through WB.SwepHeal).
function WB.AddPersistentPain(ply, limbId, amount)
	if not IsValid(ply) or not limbId then return end
	ply._WBPersistentPain = ply._WBPersistentPain or {}
	local t = ply._WBPersistentPain
	t[limbId] = math.Clamp((t[limbId] or 0) + (tonumber(amount) or 0), 0, 100)
end

function WB.ClearPersistentPain(ply)
	ply._WBPersistentPain = nil
end

function WB.RelievePersistentPain(ply, amount)
	local t = ply._WBPersistentPain
	if not t then return false end

	local H = Health()
	local limbs = WB.GetLimbs(ply)
	amount = math.abs(tonumber(amount) or 0)
	for limbId, value in pairs(t) do
		local left = math.max(0, value - amount)
		if left <= 0 then t[limbId] = nil else t[limbId] = left end
		local l = limbs and limbs[limbId]
		if l then
			l.pain = math.Clamp(math.min(l.pain or 0, left), 0, 100)
			if H and H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end
		end
	end
	if not next(t) then ply._WBPersistentPain = nil end
	return true
end

--- Growing pain from glass shards -> standard WoundSystem shock / unconscious ragdoll
--- (TryCreateUnconsciousRagdoll already goes through Z-City's hg.Fake).
function WB.TickPersistentPain(ply, body, dt)
	local limbs = WB.GetLimbs(ply)
	if not limbs or not body then return end
	local H = Health()

	local glass = WB.GlassShards[ply]
	if glass then
		for limbId, count in pairs(glass) do
			if count > 0 then WB.AddPersistentPain(ply, limbId, count * 0.9 * (dt or 0)) end
		end
	end

	local t = ply._WBPersistentPain
	if not t then return end

	local maxPain = 0
	for limbId, value in pairs(t) do
		if value <= 0 then t[limbId] = nil continue end
		local l = limbs[limbId]
		if not l or l.dismembered then t[limbId] = nil continue end
		if (l.pain or 0) < value then
			l.pain = value
			-- do not spam the limb packet every Org Think
			if (ply._WBNextPainSync or 0) <= CurTime() then
				ply._WBNextPainSync = CurTime() + 0.25
				if H and H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end
			end
		end
		maxPain = math.max(maxPain, value)
	end
	if not next(t) then ply._WBPersistentPain = nil return end
	if maxPain < 85 then return end

	-- «как и всегда»: боль -> шок -> бессознательное состояние, держится пока боль не снята
	body.consciousness = math.min(body.consciousness or 100, 5)
	body.unconscious = true
	body.wasUnconscious = true
	if (ply._WBNextPainKnockout or 0) <= CurTime() then
		ply._WBNextPainKnockout = CurTime() + 12
		if H and H.AddBodyShock then H.AddBodyShock(body, 100) end
		body.fallingRagdoll = true
		body.fallingRagdollWakeTime = CurTime() + 6
		body.fallingRagdollReason = "glass_pain"
		if H and H.TryCreateUnconsciousRagdoll then H.TryCreateUnconsciousRagdoll(ply, body) end
		if H and H.SendCardioUpdate then H.SendCardioUpdate(ply, true) end
		dbg("pain knockout", ply, maxPain)
	end
end

function WB.Think(owner, org, dt)
	if not IsValid(owner) or not owner:IsPlayer() or not owner:Alive() then return end

	local wasOtrub = org.otrub
	local body = WB.Sync(owner, org)
	if not body then return end

	org.timeValue = dt

	-- pain that only a Z-City painkiller can take away (falls / glass shards)
	WB.TickPersistentPain(owner, body, dt)

	-- Z-City pain of a dislocated leg (running on it writes org.painadd) becomes C:U pain of that limb
	local pa = org.painadd
	if pa and pa > 0 and (org.llegdislocation or org.rlegdislocation) then
		local limbs = WB.GetLimbs(owner)
		if limbs then
			local list = {}
			for _, names in ipairs({legL, legR}) do
				for _, id in ipairs(names) do
					if type(limbs[id]) == "table" and limbs[id].dislocated then list[#list + 1] = id end
				end
			end
			for _, id in ipairs(list) do
				limbs[id].pain = math.Clamp((limbs[id].pain or 0) + pa * 0.5 / #list, 0, 100)
			end
		end
		org.painadd = 0
	end
	org.uncon_timer = org.otrub and ((org.uncon_timer or 0) + dt) or 0

	local justWentUncon = org.otrub and not wasOtrub
	local justWoke = wasOtrub and not org.otrub

	if justWentUncon then
		hook.Run("HG_OnOtrub", owner)
		hook.Run("PlayerDropWeapon", owner)
		owner.fullsend = true
	elseif justWoke then
		hook.Run("HG_OnWakeOtrub", owner)
		owner.fullsend = true
	end

	-- both arms gone: only hands
	if org.rarmamputated and org.larmamputated then
		local hands = owner:GetWeapon("weapon_hands_sh")
		if IsValid(hands) and owner:GetActiveWeapon() ~= hands then owner:SetActiveWeapon(hands) end
	end

	-- Z-City ragdoll (the same call the legacy organism made)
	if org.otrub or org.fake then
		hg.Fake(owner, nil, true)
	end

	-- keep the vanilla HP bar sane, WoundSystem blocks the engine damage itself
	org.health = owner:Health()

	-- network the shadow organism (HUD / client prediction)
	local now = CurTime()
	local moveChanged = math.abs((org._wbSentMove or 1) - (org.wsmovemult or 1)) >= 0.05

	if justWentUncon or justWoke or (moveChanged and (org._wbNextMoveSend or 0) < now) then
		org._wbNextMoveSend = now + 0.25
		org._wbSentMove = org.wsmovemult
		org._wbNextSend = now + 1
		hg.send_bareinfo(org)
		hg.send_organism(org, owner)
	elseif (org._wbNextSend or 0) < now then
		org._wbNextSend = now + 1
		hg.send_bareinfo(org)
		hg.send_organism(org, owner)
	end
end

-----------------------------------------------------------------------------------------------------------------------
-- RAGDOLL  (called by WoundSystem instead of its own ragdoll code, see sv_health.lua)
-----------------------------------------------------------------------------------------------------------------------

--- WoundSystem asks for an unconscious/falling ragdoll -> the Z-City fake ragdoll
function WB.CreateRagdoll(ply, body)
	if not IsValid(ply) or not ply:Alive() then return false end
	if IsValid(ply.FakeRagdoll) then return true end

	hg.Fake(ply, nil, true)
	return IsValid(ply.FakeRagdoll)
end

--- WoundSystem wants the player back on his feet -> hg.FakeUp
function WB.RestoreRagdoll(ply, body, keepRagdoll, preserveTransform)
	if not IsValid(ply) then return true end

	if body then
		-- WoundSystem state that belongs to its own ragdoll implementation
		if not body.unconscious then
			body.fallingRagdoll = nil
			body.fallingRagdollWakeTime = nil
			body.fallingRagdollReason = nil
		end
		body.ragdollMoving = nil
		body.nextRagdollMotionCheck = nil
		body.nextUnconsciousRagdollRetry = nil
		body.unconsciousRagdoll = nil
	end

	if keepRagdoll or OverrideSpawn then return true end
	if not ply:Alive() or not IsValid(ply.FakeRagdoll) then return true end
	if body and (body.unconscious or body.brainDead) then return true end -- still down, nothing to do
	if ply._WBGetUpQueued then return true end

	ply._WBGetUpQueued = true
	timer.Simple(0, function()
		if not IsValid(ply) then return end
		ply._WBGetUpQueued = nil

		if not ply:Alive() or not IsValid(ply.FakeRagdoll) then return end

		local b = WB.GetBody(ply)
		if b and (b.unconscious or b.brainDead) then return end

		local org = ply.organism
		if org then
			org.fake, org.needfake = false, false
			org.stun = math.min(org.stun or 0, CurTime())
		end

		hg.FakeUp(ply, true)
	end)

	return true
end

-- dismembered limbs have to be visible on every Z-City ragdoll of the player
local function ApplyVisuals(ply, ragdoll)
	if not WB.IsEnabled() or not IsValid(ragdoll) then return end
	if not (WoundSystem and WoundSystem.ApplyDismembermentVisuals) then return end

	local limbs = WB.GetLimbs(ply) or (IsValid(ply) and ply._WBLimbSnapshot)
	if not limbs then return end

	local any = false
	for _, state in pairs(limbs) do
		if type(state) == "table" and state.dismembered then any = true break end
	end
	if not any then return end

	WoundSystem.ApplyDismembermentVisuals(ragdoll, limbs)
end

hook.Add("Fake", "ZCity_WoundBridge_Visuals", function(ply, ragdoll)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	timer.Simple(0, function() if IsValid(ply) then ApplyVisuals(ply, ragdoll) end end)
end)

hook.Add("RagdollDeath", "ZCity_WoundBridge_DeathVisuals", function(ply, ragdoll)
	ApplyVisuals(ply, ragdoll)
end)

hook.Add("WoundSystem_OnDismember", "ZCity_WoundBridge_Mirror", function(ply, limbName)
	if not WB.IsEnabled() or not IsValid(ply) then return end

	local org = ply.organism
	if not org then return end

	local z = WB.WSLimbToZ[limbName]
	if z then org[z .. "amputated"] = true end
	if limbName == "head" then org.headamputated = true end
	ply.fullsend = true

	local ragdoll = ply.FakeRagdoll
	if IsValid(ragdoll) then ApplyVisuals(ply, ragdoll) end
end)

-- real respawn: the shadow starts clean (WoundSystem re-initialises its own body in WoundSystem_SpawnSync)
hook.Add("PlayerSpawn", "ZCity_WoundBridge_Spawn", function(ply)
	if OverrideSpawn then return end
	ply._WBGetUpQueued = nil
	ply._WBLimbSnapshot = nil
end)

-----------------------------------------------------------------------------------------------------------------------
-- BLOOD BAG  (weapon_bloodbag Think)
-----------------------------------------------------------------------------------------------------------------------

local BLOOD_PER_BAG = 10 -- % of the whole blood volume in one full Z-City bag (500 of 5000)

function WB.BloodBagGive(swep, charEnt)
	local ply = WB.GetPlayer(charEnt)
	if not WB.IsBridged(ply) then return false end

	if charEnt:GetVelocity():LengthSqr() >= 1000 then return true end
	if swep.modeValues[1] <= 0 then return true end

	local org = ply.organism
	local pulse = org and org.pulse or 70
	local amount = math.min(FrameTime() * 0.5 * math.max(pulse / 70, 0.3), swep.modeValues[1])
	if amount <= 0 then return true end

	local H = Health()
	local limb = (WB.GetLimbs(ply) and LimbAlive(WB.GetLimbs(ply), "arm_R")) and "arm_R" or "thorax"

	-- 1 liter = 100 durability, Z-City bag = 500 ml = 50 durability
	local ok = H.ApplyItemToBody(ply, "BLOOD BAG", limb, amount * 50, {partial = true})
	if ok then
		swep.modeValues[1] = math.max(swep.modeValues[1] - amount, 0)
		if swep.sndcd < CurTime() then
			swep:GetOwner():EmitSound("zcity/healing/bloodbag_loop_" .. math.random(8) .. ".wav")
			swep.sndcd = CurTime() + 0.7
		end
	end

	return true
end

function WB.BloodBagTake(swep, charEnt)
	local ply = WB.GetPlayer(charEnt)
	if not WB.IsBridged(ply) then return false end

	local body = WB.GetBody(ply)
	if not body then return true end
	if charEnt:GetVelocity():LengthSqr() >= 25 or (body.bloodVolume or 0) <= 40 then return true end

	local org = ply.organism
	local pulse = org and org.pulse or 70
	local old = swep.modeValues[1]
	swep.modeValues[1] = math.min(old + FrameTime() * math.max(pulse / 70, 0.3) * 0.5, 1)
	swep.bloodtype = swep.bloodtype or "o-"

	local taken = swep.modeValues[1] - old
	if taken > 0 then
		body.bloodVolume = math.max((body.bloodVolume or 100) - taken * BLOOD_PER_BAG, 0)
		if WoundSystem.Health.SendCardioUpdate then WoundSystem.Health.SendCardioUpdate(ply) end

		if swep.sndcd < CurTime() then
			swep:GetOwner():EmitSound("zcity/healing/bloodbag_loop_" .. math.random(8) .. ".wav")
			swep.sndcd = CurTime() + 0.7
		end
	end

	return true
end

-----------------------------------------------------------------------------------------------------------------------
-- SWEPs  ("ZCity Medicine")  ->  WoundSystem medicine
-----------------------------------------------------------------------------------------------------------------------
--[[
	WB.SwepHeal(swep, ent, mode, bone) is called at the very top of every SWEP:Heal of a Z-City medical SWEP.
	It returns nil when the SWEP has to run its legacy code (bridge off, NPC / corpse target, SWEP not mapped),
	otherwise the value that Heal must return.

	Effects come from the WoundSystem item definitions, so a Z-City bandage does exactly what a WoundSystem
	gauze does. A Z-City item is "one WoundSystem item": using all of it equals the full WoundSystem effect.
]]

-- kinds:
--   bandage  continuous, `rate` = WoundSystem durability/s (item has 100). Needs a bleeding limb.
--   syringe  continuous, `rate` = Z-City units/s (legacy injection speed). Effect scales with the injected part.
--   apply    one-shot WoundSystem use.apply (tourniquet, chest drain...) on the best limb
--   body     one-shot direct body effect `fn(ply, body, H, fraction)`
-- hold: Z-City "heal animation" gate (SetHolding += hold) when healing yourself with hg_healanims on
local function AdrenalineFn(ply, body, f)
	body.adrenaline = math.Clamp((body.adrenaline or 0) + 45 * f, 0, 100)
	body.stamina = math.Clamp((body.stamina or 100) + 30 * f, 0, 100)
	body.heartRate = math.Clamp((body.heartRate or 70) + 15 * f, 0, 320)
end

local function BetablockFn(ply, body, f)
	body.adrenaline = math.Clamp((body.adrenaline or 0) - 40 * f, 0, 100)
	body.heartRate = math.Clamp((body.heartRate or 70) - 20 * f, 20, 320)
	body.shock = math.Clamp((body.shock or 0) - 5 * f, 0, 100)
end

local function MannitolFn(ply, body, f)
	body.brainHealth = math.Clamp((body.brainHealth or 100) + 8 * f, 0, 100)
	body.brainDamageBuffer = math.max((body.brainDamageBuffer or 0) - 20 * f, 0)
end

local function ThiamineFn(ply, body, f)
	body.brainHealth = math.Clamp((body.brainHealth or 100) + 4 * f, 0, 100)
end

local function Garbage(...)
	local args, n = {...}, select("#", ...)
	return function(swep)
		if swep.SpawnGarbage then swep:SpawnGarbage(unpack(args, 1, n)) end
	end
end

WB.SwepSpecs = {
	weapon_bandage_sh    = {kind = "bandage", item = "GAUZE", rate = 25, hold = 10, delete = true, mg = {kind = "bandage"}},
	weapon_bigbandage_sh = {kind = "bandage", item = "STERILIZEDBANDAGE", rate = 25, hold = 10, delete = true, mg = {kind = "bandage"}},
	weapon_tourniquet    = {kind = "apply", item = "TOURNIQUET", hold = 10, delete = true, pick = "extremity"},
	weapon_needle        = {kind = "apply", item = "INJECTION", hold = 4, delete = true, limb = "thorax",
		garbage = Garbage(nil, nil, nil, nil, "2211"), mg = {kind = "syringe", vehicle = "SALINE"}},
	weapon_morphine      = {kind = "syringe", item = "MORPHINE", rate = 0.5, holdSet = 50, mg = {kind = "syringe"}},
	weapon_fentanyl      = {kind = "syringe", item = "FENTANYL", rate = 1, holdSet = 50, mg = {kind = "syringe"}},
	weapon_naloxone      = {kind = "syringe", item = "NALOXONE", oneshot = true, hold = 4, delete = true, mg = {kind = "syringe"},
		garbage = Garbage("models/bloocobalt/l4d/items/w_eq_adrenaline.mdl", nil, nil, nil, "2211")},
	weapon_painkillers   = {kind = "syringe", item = "MORPHINE", oneshot = true, fraction = 0.25, hold = 4, delete = true,
		garbage = Garbage(nil, nil, "snd_jack_hmcd_foodbounce.wav")},
	weapon_adrenaline    = {kind = "body", fn = AdrenalineFn, hold = 4, delete = true, mg = {kind = "syringe", vehicle = "SALINE"},
		garbage = Garbage("models/bloocobalt/l4d/items/w_eq_adrenaline.mdl", nil, nil, nil, "2211")},
	weapon_betablock     = {kind = "body", fn = BetablockFn, hold = 4, delete = true, mg = {kind = "syringe", vehicle = "SALINE"},
		garbage = Garbage(nil, nil, "snd_jack_hmcd_foodbounce.wav")},
	weapon_mannitol      = {kind = "body", fn = MannitolFn, hold = 4, delete = true, mg = {kind = "syringe", vehicle = "SALINE"},
		garbage = Garbage("models/bloocobalt/l4d/items/w_eq_adrenaline.mdl", nil, nil, nil, "2211")},
	weapon_thiamine      = {kind = "body", fn = ThiamineFn, hold = 4, delete = true, mg = {kind = "syringe", vehicle = "SALINE"},
		garbage = Garbage(nil, nil, "snd_jack_hmcd_foodbounce.wav")},
}

-- weapon_medkit_sh: per-mode specs (self.mode)
WB.MedkitModes = {
	[1] = {kind = "bandage", item = "GAUZE", rate = 25, mg = {kind = "bandage"}},
	[2] = {kind = "syringe", item = "MORPHINE", oneshot = true, fraction = 0.3, mg = {kind = "syringe"}},
	[3] = {kind = "syringe", item = "BLOODCOAGULANT", oneshot = true, mg = {kind = "syringe", vehicle = "SALINE"}},
	[4] = {kind = "apply", item = "TOURNIQUET", pick = "extremity"},
	[5] = {kind = "apply", item = "INJECTION", limb = "thorax", mg = {kind = "syringe", vehicle = "SALINE"}},
}

local EXTREMITY = {
	arm_L = true, forearm_L = true, hand_L = true, arm_R = true, forearm_R = true, hand_R = true,
	thigh_L = true, crus_L = true, foot_L = true, thigh_R = true, crus_R = true, foot_R = true,
}

local INJECT_SITES = {"arm_R", "arm_L", "thigh_R", "thigh_L", "thorax"}

local hg_healanims

local function BestLimb(ply, spec, preferred)
	local limbs = WB.GetLimbs(ply)
	if not limbs then return end

	if spec.limb then
		return LimbAlive(limbs, spec.limb) and spec.limb or nil
	end

	if spec.kind == "syringe" or spec.kind == "body" then
		if preferred and LimbAlive(limbs, preferred) then return preferred end
		for _, id in ipairs(INJECT_SITES) do
			if LimbAlive(limbs, id) then return id end
		end
		return "thorax"
	end

	-- bandage / tourniquet: the worst bleeding limb (the one the player aims at wins when it bleeds too)
	local bestId, best = nil, 0.1
	for id, state in pairs(limbs) do
		if type(state) ~= "table" or state.dismembered then continue end
		if spec.pick == "extremity" and not EXTREMITY[id] then continue end
		if spec.kind == "bandage" and state.isBandaged then continue end
		if spec.pick == "extremity" and state.tourniqueted then continue end

		local score = (state.bleed or 0) + ((id == preferred) and 1000 or 0)
		if (state.bleed or 0) > 0.1 and score > best then
			bestId, best = id, score
		end
	end

	return bestId
end

-- limb the owner is looking at (when healing someone else)
local function AimedLimb(swep, target)
	local owner = swep:GetOwner()
	if not IsValid(owner) or not hg.eyeTrace then return end

	local tr = hg.eyeTrace(owner)
	if not tr or not IsValid(tr.Entity) or WB.GetPlayer(tr.Entity) ~= target then return end

	local ent = tr.Entity
	if not ent:IsRagdoll() or not tr.PhysicsBone then return end

	local H = Health()
	local bone = ent:TranslatePhysBoneToBone(tr.PhysicsBone)
	return H.RagdollBoneNameToLimb and H.RagdollBoneNameToLimb(ent:GetBoneName(bone)) or nil
end

local function HealAnimationGate(swep, ent, hold, holdSet)
	hg_healanims = hg_healanims or GetConVar("hg_healanims")
	if not (hg_healanims and hg_healanims:GetBool()) then return true end

	local owner = swep:GetOwner()
	if ent ~= hg.GetCurrentCharacter(owner) then return true end
	if not swep.GetHolding then return true end

	if holdSet then
		swep:SetHolding(math.Clamp(swep:GetHolding() + 100, 0, holdSet))
		return true
	end

	if hold then
		swep:SetHolding(math.min(swep:GetHolding() + hold, 100))
		return swep:GetHolding() >= 100
	end

	return true
end

local function Finish(swep, spec)
	local owner = swep:GetOwner()
	if spec.garbage then spec.garbage(swep) end
	if IsValid(owner) then owner:SelectWeapon("weapon_hands_sh") end
	swep:Remove()
end

local function Remaining(swep, idx) return (swep.modeValues and swep.modeValues[idx]) or 0 end

local function Consume(swep, idx, amount)
	local left = Remaining(swep, idx) - amount
	swep.modeValues[idx] = left > 0.0005 and left or 0 -- no float dust: the item must really become empty
end

-- unit conversion helper: Z-City item amount (modeValues) of a full item
local function DefOf(swep, idx, fallback)
	local d = swep.modeValuesdef and swep.modeValuesdef[idx]
	if istable(d) then d = d[1] end
	return tonumber(d) or fallback
end

-- the item (and what is left of the Z-City item) after a finished use: remove empty one-shots / medkits
local function AfterUse(swep, spec, idx)
	if spec.delete or swep:GetClass() == "weapon_medkit_sh" then
		local empty = true
		for i = 1, 5 do
			if swep:GetClass() ~= "weapon_medkit_sh" and i > 1 then break end
			if Remaining(swep, i) > 0 then empty = false break end
		end

		if swep:GetClass() == "weapon_medkit_sh" then
			if empty and swep.ShouldDeleteOnFullUse then Finish(swep, {}) end
		elseif empty then
			Finish(swep, spec)
		end
	end
end

--[[
	Minigame use.  The WoundSystem bandage / syringe minigame opens on the user's screen (WoundSystem.Health.StartExternalMinigame)
	and the Z-City item is used up WHILE the player works, exactly like the WoundSystem inventory item was:
	  bandage / syringe items / body drugs   every wrap / every push of the plunger applies its part of the effect to the
	                                         TARGET at once and takes the same part away from the Z-City item (smooth, partial use)
	  chest drain / carried items            (SALINE vehicle with a non-dividable item) applied when the minigame ends,
	                                         scaled by the dose that was pushed (the chest drain needs a full insert)
	Nothing done / death / broken needle = nothing is applied and nothing is used up.
]]
local function StartMinigame(swep, spec, idx, target, limbId)
	local H = Health()
	local owner = swep:GetOwner()
	if not (IsValid(owner) and owner:IsPlayer() and owner:Alive()) then return nil end
	if not (H.StartExternalMinigame and H.HasExternalMinigame) then return nil end

	if H.HasExternalMinigame(owner) then return true end -- already running
	if (swep._wbMgCooldown or 0) > CurTime() then return true end

	local mg = spec.mg
	local item = mg.vehicle or spec.item
	local def = DefOf(swep, idx, 1)
	local remaining = Remaining(swep, idx)
	local maxDur = (WoundSystem.Items and WoundSystem.Items.GetMax and WoundSystem.Items.GetMax(item)) or 100

	local oneDose = spec.oneshot or mg.vehicle or spec.kind == "apply" or spec.kind == "body"
	-- effect + consumption while the player works (everything that can be applied in small parts)
	local live = mg.kind == "bandage" or spec.kind == "body" or (mg.kind == "syringe" and not mg.vehicle and spec.kind ~= "apply")

	local amount
	if mg.kind == "bandage" then
		amount = remaining / math.max(def, 0.0001) * maxDur
	elseif oneDose then
		amount = maxDur * (spec.fraction or 1) -- one dose
	else
		amount = remaining / math.max(def, 0.0001) * maxDur
	end

	local appliedLive = 0

	local function Stop(reason)
		if H.StopExternalMinigame then H.StopExternalMinigame(owner, reason) end
	end

	local started = H.StartExternalMinigame(owner, {
		kind = mg.kind,
		itemId = item,
		limbId = limbId,
		amount = amount,

		-- the player did `durCost` of work (durability units of the minigame item)
		onProgress = function(ply, session, durCost)
			if not live then return end
			if not IsValid(swep) or not WB.IsBridged(target) then Stop("target_gone") return end

			local start = math.max(session.startAmount or amount, 0.0001)
			durCost = math.min(durCost, math.max(start - appliedLive, 0))
			if durCost <= 0 then return end

			local ok
			if spec.kind == "body" then
				local body = WB.GetBody(target)
				if body then
					spec.fn(target, body, durCost / start) -- the effect scales with the dose given
					if H.SendCardioUpdate then H.SendCardioUpdate(target) end
					ok = true
				end
			else
				ok = H.ApplyItemToBody(target, spec.item, limbId, durCost)
			end
			if not ok then return end

			appliedLive = appliedLive + durCost

			if oneDose then
				swep.modeValues[idx] = math.max(remaining * (1 - appliedLive / start), 0)
			else
				Consume(swep, idx, durCost / math.max(maxDur, 1) * def)
			end
		end,

		onClose = function(ply, session, reason)
			swep._wbMgCooldown = CurTime() + 0.6

			local interrupted = reason == "dead" or reason == "respawn" or reason == "disabled" or reason == "needle_break"
				or reason == "invalid_limb" or reason == "replaced" or reason == "target_gone"
			local used, start = session.deferredUsed or 0, session.startAmount or 0
			local frac = start > 0 and math.Clamp(used / start, 0, 1) or 0

			local function Nothing()
				if not interrupted and IsValid(ply) then ply:PrintMessage(HUD_PRINTCENTER, "Not completed - nothing was applied") end
			end

			if live then
				if not IsValid(swep) then return end
				if appliedLive <= 0.01 then Nothing() return end

				if oneDose and appliedLive >= start * 0.97 then swep.modeValues[idx] = 0 end
				AfterUse(swep, spec, idx)
				return
			end

			-- applied when the minigame ends
			if interrupted then return end
			if used <= 0.01 or frac <= 0.005 then Nothing() return end
			if not WB.IsBridged(target) then return end

			local ok
			if spec.item == "INJECTION" then
				-- a chest drain is not a dose: it only works when it was really inserted
				if frac >= 0.9 then ok = H.ApplyItemToBody(target, spec.item, limbId, 100) end
			else
				-- the real item is carried by a syringe: scale its per-use dose
				local itemDef = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(spec.item)
				local perUse = itemDef and itemDef.use and tonumber(itemDef.use.consumeDurability) or (itemDef and itemDef.max) or 100
				ok = H.ApplyItemToBody(target, spec.item, limbId, perUse * frac, {partial = true})
			end

			if not ok then Nothing() return end

			if IsValid(swep) then
				local left = Remaining(swep, idx) * (1 - frac)
				swep.modeValues[idx] = (frac >= 0.97 or left <= 0.0005) and 0 or left
				AfterUse(swep, spec, idx)
			end
		end,
	})

	if started then return true end
	return nil -- could not open (limb gone, ...): use the instant application
end

function WB.SwepHeal(swep, ent, mode, bone)
	if not WB.IsEnabled() or not IsValid(ent) then return end

	local target = WB.GetPlayer(ent)
	if not target then return end -- NPCs, corpses and anything WoundSystem does not own keep the legacy behaviour

	local spec, idx = WB.SwepSpecs[swep:GetClass()], 1
	if swep:GetClass() == "weapon_medkit_sh" then
		idx = swep.mode or mode or 1
		spec = WB.MedkitModes[idx]
	end
	if not spec then return end

	local H = Health()
	local owner = swep:GetOwner()
	local self_use = ent == hg.GetCurrentCharacter(owner)

	-- Z-City "using animation" gate (same numbers as the legacy Heal code)
	if swep:GetClass() == "weapon_medkit_sh" then
		if self_use then
			hg_healanims = hg_healanims or GetConVar("hg_healanims")
			if hg_healanims and hg_healanims:GetBool() then
				swep:SetHolding(math.min(swep:GetHolding() + 50, 100))
				if swep:GetHolding() < 100 then return false end
			end
		end
	elseif not HealAnimationGate(swep, ent, spec.hold, spec.holdSet) then
		return false
	end

	if Remaining(swep, idx) <= 0 and spec.kind ~= "body" then return false end

	local aimed = (not self_use) and AimedLimb(swep, target) or nil
	local done = false

	-- WoundSystem minigame (bandage / syringe) instead of an instant effect
	if spec.mg and WB.cvMinigame:GetBool() then
		local limbId
		if spec.kind == "bandage" or spec.kind == "apply" then
			limbId = BestLimb(target, spec, aimed)
			if not limbId and spec.kind == "apply" and not spec.limb and spec.pick ~= "extremity" then limbId = "thorax" end
		else
			limbId = BestLimb(target, spec, aimed)
		end

		if not limbId then return false end -- nothing to treat

		local started = StartMinigame(swep, spec, idx, target, limbId)
		if started ~= nil then return false end
	end

	if spec.kind == "bandage" then
		local limbId = BestLimb(target, spec, aimed)
		if not limbId then return false end -- nothing bleeds: nothing is used up (same as the legacy Bandage)

		local now = CurTime()
		local dt = now - (swep._wbLast or 0)
		swep._wbLast = now
		if dt <= 0 or dt > 0.3 then dt = 0.015 end

		local def = (swep.modeValuesdef and swep.modeValuesdef[idx] and (istable(swep.modeValuesdef[idx]) and swep.modeValuesdef[idx][1] or swep.modeValuesdef[idx])) or 40
		local amount = math.min(spec.rate * dt, Remaining(swep, idx) / def * 100)

		local ok, used = H.ApplyItemToBody(target, spec.item, limbId, amount)
		if ok then
			Consume(swep, idx, (used or amount) / 100 * def)
			done = true
		end

	elseif spec.kind == "syringe" then
		local limbId = BestLimb(target, spec, aimed)
		local def = (swep.modeValuesdef and swep.modeValuesdef[idx] and (istable(swep.modeValuesdef[idx]) and swep.modeValuesdef[idx][1] or swep.modeValuesdef[idx])) or 1
		local injected

		if spec.oneshot then
			injected = Remaining(swep, idx)
		else
			injected = math.min(FrameTime() * spec.rate, Remaining(swep, idx))
		end

		if injected > 0 and limbId then
			local amount = injected / math.max(def, 0.0001) * 100 * (spec.fraction or 1)
			local ok = H.ApplyItemToBody(target, spec.item, limbId, amount)
			if ok then
				Consume(swep, idx, injected)
				done = true
				if not spec.oneshot then
					owner:EmitSound("pshiksnd")
				else
					owner:EmitSound("snd_jack_hmcd_needleprick.wav", 60, math.random(95, 105))
				end
			end
		end

	elseif spec.kind == "apply" then
		local limbId = BestLimb(target, spec, aimed)
		if not limbId and spec.pick ~= "extremity" and not spec.limb then limbId = "thorax" end
		if not limbId then return false end

		local ok = H.ApplyItemToBody(target, spec.item, limbId, 100)
		if ok then
			swep.modeValues[idx] = 0
			done = true
		end

	elseif spec.kind == "body" then
		local body = WB.GetBody(target)
		if not body then return false end

		local def = (swep.modeValuesdef and swep.modeValuesdef[idx] and (istable(swep.modeValuesdef[idx]) and swep.modeValuesdef[idx][1] or swep.modeValuesdef[idx])) or 1
		local fraction = math.Clamp(Remaining(swep, idx) / math.max(def, 0.0001), 0, 1)
		if fraction <= 0 then return false end

		spec.fn(target, body, fraction)
		if H.SendCardioUpdate then H.SendCardioUpdate(target) end
		swep.modeValues[idx] = 0
		owner:EmitSound("snd_jack_hmcd_needleprick.wav", 60, math.random(95, 105))
		done = true
	end

	if not done then return false end

	-- ONLY a Z-City painkiller removes the persistent fall / glass pain
	if spec.item == "MORPHINE" or spec.item == "FENTANYL" then
		WB.RelievePersistentPain(target, 45)
	end

	-- one-shot items vanish when used up
	AfterUse(swep, spec, idx)

	return true
end

-----------------------------------------------------------------------------------------------------------------------
-- GLASS SHARDS (дополнение): счётчики и сессии мини-игры вытаскивания осколков.
-- Механики шрапнели здесь нет: нет limb.shrapnel, TWEEZERS, бонусов/штрафов к заживлению,
-- осколков от пуль, взрывов и сломанной иглы. Стекло приходит только из урона Z-City.
-- Имена WoundSystem_Shrapnel* ниже — исторические имена сообщений самой мини-игры,
-- оставлены как есть, чтобы не переписывать восстановленный клиентский файл.
-----------------------------------------------------------------------------------------------------------------------

for _, name in ipairs({
	"WoundSystem_ShrapnelOpen",
	"WoundSystem_ShrapnelState",
	"WoundSystem_ShrapnelClose",
	"WoundSystem_ShrapnelStart",
	"WoundSystem_ShrapnelInput",
	"WoundSystem_GlassStatus",
	"WoundSystem_GlassRadial",
}) do
	util.AddNetworkString(name)
end

local Clamp, Rand, Lerp = math.Clamp, math.Rand, Lerp

-----------------------------------------------------------------------------------------------------------------------
-- state
-----------------------------------------------------------------------------------------------------------------------

local PIECE_COUNT = 5
local GLASS = {
	ExtractY = -60,
	ReimpaleY = -68,
	HandStartY = -170,
	MinY = -364,
	FreeMaxY = 240,
	DragSmooth = 0.55,
	BreakVelY = 2.2,
	BreakXDist = 42,
	GrabHalfX = 75,
	GrabHalfY = 350,
	InputDelay = 0.05,
	BasePos = {
		{ x = -86, y = -214 },
		{ x = -44, y = -214 },
		{ x =   0, y = -214 },
		{ x =  44, y = -214 },
		{ x =  86, y = -214 },
	},
}

WB.GlassShards = WB.GlassShards or setmetatable({}, { __mode = "k" })
local GlassShards = WB.GlassShards

local Sessions = setmetatable({}, { __mode = "k" })
local NextSessionId = 1
local CloseGlassSession


local function GlassTable(ply)
	local t = GlassShards[ply]
	if not t then
		t = {}
		GlassShards[ply] = t
	end
	return t
end

function WB.GetGlass(ply, limbId)
	local t = GlassShards[ply]
	return (t and t[limbId]) or 0
end

--- Full mirror of the shard counters, used by the wound view ("REMOVE GLASS" action point).
function WB.SendGlassStatus(ply)
	if not IsValid(ply) then return end

	local t = GlassShards[ply] or {}
	local limbs = {}
	for limbId, count in pairs(t) do
		if count > 0 then limbs[#limbs + 1] = { limbId, Clamp(math.floor(count), 0, PIECE_COUNT) } end
	end

	net.Start("WoundSystem_GlassStatus")
		net.WriteUInt(#limbs, 5)
		for _, entry in ipairs(limbs) do
			net.WriteString(entry[1])
			net.WriteUInt(entry[2], 4)
		end
	net.Send(ply)
end

function WB.SetGlass(ply, limbId, count)
	if not limbId then return end
	count = Clamp(math.floor(tonumber(count) or 0), 0, PIECE_COUNT)
	local t = GlassTable(ply)
	if count <= 0 then t[limbId] = nil else t[limbId] = count end
	WB.SendGlassStatus(ply)
	return count
end

function WB.ClearGlass(ply)
	GlassShards[ply] = nil
	local session = Sessions[ply]
	if session then CloseGlassSession(ply, "cleared") end
	WB.SendGlassStatus(ply)
end

function WB.HasGlassMinigame(ply)
	return Sessions[ply] ~= nil
end

-----------------------------------------------------------------------------------------------------------------------
-- session (the C:U shard-pulling physics, trimmed down: no tweezers, no shrapnel field)
-----------------------------------------------------------------------------------------------------------------------

local function CountRemaining(session)
	local count = 0
	for _, piece in ipairs(session.pieces) do
		if piece.active and piece.embedded ~= false then count = count + 1 end
	end
	return count
end

local function WritePieces(session)
	for i = 1, PIECE_COUNT do
		local piece = session.pieces[i]
		net.WriteFloat(piece.x)
		net.WriteFloat(piece.y)
		net.WriteBool(piece.active)
	end
end

local function WriteEmbedded(session)
	for i = 1, PIECE_COUNT do
		local piece = session.pieces[i]
		net.WriteBool(piece and piece.embedded ~= false)
	end
end

local function BuildGlassSession(limbId, count, external)
	local session = {
		id = NextSessionId,
		limbId = limbId,
		external = external == true,
		pieces = {},
		heldIndex = nil,
		grabArmed = false,
		holdSource = nil,
		holdOffsetX = 0,
		holdOffsetY = 0,
		lastInputAt = CurTime() - GLASS.InputDelay,
		lastAckSeq = 0,
		lastRemaining = nil,
	}

	NextSessionId = NextSessionId + 1
	if NextSessionId > 16000000 then NextSessionId = 1 end

	local activePieces = Clamp(math.floor(count), 0, PIECE_COUNT)
	local hiddenPieces = PIECE_COUNT - activePieces

	for i = 1, PIECE_COUNT do
		local base = GLASS.BasePos[i]
		local angle = Rand(0, math.pi * 2)
		local radius = math.sqrt(Rand(0, 1)) * 20
		local piece = {
			x = base.x + math.cos(angle) * radius,
			y = base.y + math.sin(angle) * radius,
			active = true,
			embedded = true,
		}

		if i <= hiddenPieces then
			piece.y = piece.y + 8000
			piece.active = false
			piece.embedded = false
		end

		session.pieces[i] = piece
	end

	return session
end

local function SendGlassOpen(ply, session)
	net.Start("WoundSystem_ShrapnelOpen")
		net.WriteUInt(session.id, 24)
		net.WriteString(session.limbId)
		net.WriteBool(false) -- no tweezers / tool: glass is pulled out by hand
		WritePieces(session)
		net.WriteUInt(CountRemaining(session), 4)
		WriteEmbedded(session)
		net.WriteUInt(session.lastAckSeq or 0, 24)
		net.WriteBool(session.external == true)
	net.Send(ply)
end

local function SendGlassState(ply, session)
	net.Start("WoundSystem_ShrapnelState")
		net.WriteUInt(session.id, 24)
		WritePieces(session)
		net.WriteUInt(CountRemaining(session), 4)
		WriteEmbedded(session)
		net.WriteUInt(session.lastAckSeq or 0, 24)
	net.Send(ply)
end

function CloseGlassSession(ply, reason)
	local session = Sessions[ply]
	if not session then return end
	Sessions[ply] = nil

	net.Start("WoundSystem_ShrapnelClose")
		net.WriteUInt(session.id, 24)
		net.WriteString(reason or "closed")
	net.Send(ply)
end

--- Open the glass minigame for a limb. `external` = opened by Z-City damage (no health HUD needed).
function WB.StartGlassMinigame(ply, limbId, external)
	if not WB.IsBridged(ply) then return false end
	local H = Health()
	if not H or not H.GetLimbState then return false end
	if not limbId or not H.GetLimbState(ply, limbId) then return false end
	if WB.GetGlass(ply, limbId) <= 0 then return false end

	local existing = Sessions[ply]
	if existing then
		if existing.limbId == limbId then
			SendGlassOpen(ply, existing)
			return true
		end
		return false -- one minigame at a time: the wound view can reopen it later
	end

	-- never interrupt a Z-City SWEP minigame (bandage / syringe)
	if external and H.HasExternalMinigame and H.HasExternalMinigame(ply) then return false end

	local session = BuildGlassSession(limbId, WB.GetGlass(ply, limbId), external)
	session.lastRemaining = CountRemaining(session)
	Sessions[ply] = session
	SendGlassOpen(ply, session)
	dbg("glass open", ply, limbId, session.lastRemaining, external)
	return true
end

function WB.AddGlass(ply, limbId, count)
	if not WB.IsBridged(ply) then return false end
	count = math.floor(tonumber(count) or 0)
	if count <= 0 or not limbId then return false end

	local newCount = WB.SetGlass(ply, limbId, WB.GetGlass(ply, limbId) + count)
	-- NEVER auto-start: only the player himself opens the minigame (radial submenu / wound view)
	return newCount
end

--- True when another WoundSystem minigame (or a glass session) owns the player.
function WB.IsMinigameBusy(ply)
	local H = Health()
	return (H and H.HasExternalMinigame and H.HasExternalMinigame(ply)) or Sessions[ply] ~= nil or false
end

-----------------------------------------------------------------------------------------------------------------------
-- glass-pulling physics
-----------------------------------------------------------------------------------------------------------------------

local function BreakGlassGrasp(ply, session)
	session.heldIndex = nil
	session.grabArmed = false
	session.holdSource = nil

	local H = Health()
	local state = H and H.GetLimbState and H.GetLimbState(ply, session.limbId)
	if not state then return end

	state.skin = Clamp((state.skin or 100) - Rand(4, 6), 0, 100)
	state.bleed = Clamp((state.bleed or 0) + Rand(0.4, 1.0), 0, 100)
	state.pain = Clamp((state.pain or 0) + Rand(9, 16), 0, 100)
	if H.Fn and H.Fn.ClearLimbBandage then H.Fn.ClearLimbBandage(state) end
	if H.SendLimbUpdate then H.SendLimbUpdate(ply, session.limbId, true) end
end

local function ReadOptionalInputSeq()
	if not net.BytesLeft then return 0 end
	local bytesLeft, bitsLeft = net.BytesLeft()
	if (bitsLeft or 0) >= 24 or (bytesLeft or 0) >= 3 then return net.ReadUInt(24) end
	return 0
end

net.Receive("WoundSystem_ShrapnelStart", function(_, ply)
	if not WB.IsBridged(ply) then return end

	local limbId = net.ReadString()
	local slotIdx = 0
	if net.BytesLeft then
		local bytesLeft, bitsLeft = net.BytesLeft()
		if (bitsLeft or 0) >= 3 or (bytesLeft or 0) >= 1 then slotIdx = net.ReadUInt(3) end
	end

	WB.StartGlassMinigame(ply, limbId, false)
end)

-- radial "Remove glass" -> the player picked a limb himself; no health HUD needed
net.Receive("WoundSystem_GlassRadial", function(_, ply)
	if not WB.IsBridged(ply) then return end
	WB.StartGlassMinigame(ply, net.ReadString(), true)
end)

net.Receive("WoundSystem_ShrapnelClose", function(_, ply)
	local session = Sessions[ply]
	if not session then return end

	local sessionId = net.ReadUInt(24)
	local reason = net.ReadString()
	if sessionId ~= session.id then return end

	CloseGlassSession(ply, reason ~= "" and reason or "client_close")
end)

net.Receive("WoundSystem_ShrapnelInput", function(_, ply)
	local session = Sessions[ply]
	if not session then return end

	local sessionId = net.ReadUInt(24)
	local handX = net.ReadFloat()
	local handY = net.ReadFloat()
	local handVelY = net.ReadFloat()
	local startedClick = net.ReadBool()
	local holdingClick = net.ReadBool()
	local stoppedClick = net.ReadBool()
	local handBaseX, handBaseY = handX, handY

	if net.BytesLeft then
		local bytesLeft, bitsLeft = net.BytesLeft()
		if (bitsLeft or 0) >= 64 or (bytesLeft or 0) >= 8 then
			handBaseX = net.ReadFloat()
			handBaseY = net.ReadFloat()
		end
	end
	local inputSeq = ReadOptionalInputSeq()

	if sessionId ~= session.id then return end
	if not IsValid(ply) or not ply:Alive() then
		CloseGlassSession(ply, "dead")
		return
	end

	local now = CurTime()
	local clickEdge = startedClick or stoppedClick
	if now - (session.lastInputAt or 0) < GLASS.InputDelay and not clickEdge then return end
	session.lastInputAt = now
	session.lastAckSeq = inputSeq

	local H = Health()
	local state = H and H.GetLimbState and H.GetLimbState(ply, session.limbId)
	if not state then
		CloseGlassSession(ply, "invalid_limb")
		return
	end

	local clickStartedInPullArea = startedClick
		and (handY > GLASS.HandStartY or handBaseY > GLASS.HandStartY)

	if clickStartedInPullArea then
		session.grabArmed = true
	elseif not holdingClick then
		session.grabArmed = false
	end

	-- The hand can lag behind the cursor: allow a held click to latch once the grip/base
	-- actually reaches a shard.
	if not session.heldIndex and holdingClick and session.grabArmed then
		local closestDist, closestIdx = math.huge, nil
		local closestSource, closestHandX, closestHandY = nil, handX, handY
		local candidates = {
			{ x = handX, y = handY, source = "grip" },
			{ x = handBaseX, y = handBaseY, source = "base" },
		}

		for idx, piece in ipairs(session.pieces) do
			if piece.active then
				for _, candidate in ipairs(candidates) do
					local dx = math.abs(candidate.x - piece.x)
					local dy = math.abs(candidate.y - piece.y)
					if dx <= GLASS.GrabHalfX and dy <= GLASS.GrabHalfY then
						local dist = dx * dx + dy * dy
						if dist < closestDist then
							closestDist = dist
							closestIdx = idx
							closestSource = candidate.source
							closestHandX, closestHandY = candidate.x, candidate.y
						end
					end
				end
			end
		end

		if closestIdx then
			session.heldIndex = closestIdx
			session.holdSource = closestSource
			session.holdOffsetX = session.pieces[closestIdx].x - closestHandX
			session.holdOffsetY = session.pieces[closestIdx].y - closestHandY
		end
	end

	local shouldRelease = stoppedClick or (not holdingClick and not startedClick)

	local heldIndex = session.heldIndex
	if heldIndex and session.pieces[heldIndex] and session.pieces[heldIndex].active then
		local heldPiece = session.pieces[heldIndex]
		local dragHandX = session.holdSource == "base" and handBaseX or handX
		local dragHandY = session.holdSource == "base" and handBaseY or handY
		local targetX = dragHandX + session.holdOffsetX
		local targetY = dragHandY + session.holdOffsetY

		if heldPiece.embedded == false then
			heldPiece.x = Lerp(GLASS.DragSmooth, heldPiece.x, targetX)
			heldPiece.y = Lerp(GLASS.DragSmooth, heldPiece.y, targetY)
			heldPiece.y = Clamp(heldPiece.y, GLASS.MinY, GLASS.FreeMaxY)
			if heldPiece.y <= GLASS.ReimpaleY then heldPiece.embedded = true end
		else
			heldPiece.y = Lerp(GLASS.DragSmooth, heldPiece.y, targetY)
			heldPiece.y = Clamp(heldPiece.y, GLASS.MinY, GLASS.ExtractY)
			if heldPiece.y >= GLASS.ExtractY then
				heldPiece.y = GLASS.ExtractY
				heldPiece.embedded = false
			end

			-- pulling too fast / sideways tears the skin (no tweezers in this build)
			if heldPiece.embedded ~= false then
				if math.abs(handVelY) > GLASS.BreakVelY
					or math.abs(heldPiece.x - targetX) > GLASS.BreakXDist then
					BreakGlassGrasp(ply, session)
					SendGlassState(ply, session)
					return
				end
			end
		end
	end

	if shouldRelease then
		session.heldIndex = nil
		session.grabArmed = false
		session.holdSource = nil
	end

	local remaining = CountRemaining(session)
	if remaining ~= session.lastRemaining then
		session.lastRemaining = remaining
		WB.SetGlass(ply, session.limbId, remaining)
	end

	if remaining <= 0 and not holdingClick then
		SendGlassState(ply, session)
		CloseGlassSession(ply, "complete")
		return
	end

	SendGlassState(ply, session)
end)

-----------------------------------------------------------------------------------------------------------------------
-- lifecycle
-----------------------------------------------------------------------------------------------------------------------

hook.Add("PlayerSpawn", "WoundBridge_GlassSpawn", function(ply)
	GlassShards[ply] = nil
	WB.ClearPersistentPain(ply)
	CloseGlassSession(ply, "respawn")
	WB.SendGlassStatus(ply)
end)

hook.Add("PostPlayerDeath", "WoundBridge_GlassDeath", function(ply)
	CloseGlassSession(ply, "dead")
	WB.ClearPersistentPain(ply)
end)

hook.Add("PlayerDisconnected", "WoundBridge_GlassDisconnect", function(ply)
	GlassShards[ply] = nil
	Sessions[ply] = nil
end)
