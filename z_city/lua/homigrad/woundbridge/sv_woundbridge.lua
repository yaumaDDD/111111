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
	or CreateConVar("zcity_wounds_collision_scale", "0.6", FCVAR_ARCHIVE,
		"Multiplier for ragdoll collision damage forwarded to WoundSystem", 0, 20))

WB.cvMinigame = WB.cvMinigame or (ConVarExists("zc_woundsystem_minigames") and GetConVar("zc_woundsystem_minigames")
	or CreateConVar("zc_woundsystem_minigames", "1", FCVAR_ARCHIVE,
		"1 = Z-City medical SWEPs open the WoundSystem minigame (bandage / syringe), the effect is applied only after it was completed", 0, 1))

WB.cvDebug = WB.cvDebug or (ConVarExists("zc_woundsystem_bridge_debug") and GetConVar("zc_woundsystem_bridge_debug")
	or CreateConVar("zc_woundsystem_bridge_debug", "0", FCVAR_ARCHIVE, "Print bridge debug output", 0, 1))

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
	local limb

	if bonename and bonename ~= "" and H and H.RagdollBoneNameToLimb then
		limb = H.RagdollBoneNameToLimb(bonename)
	end

	if not limb and hitgroup then
		limb = (H and H.Const and H.Const.HitgroupToLimb and H.Const.HitgroupToLimb[hitgroup]) or WB.HitgroupToWS[hitgroup]
	end

	return limb
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

--- Ragdoll collision damage (Z-City `velocityDamage`)
--- `damage` is Z-City's dmg * 20 (already scaled by the bone multiplier)
function WB.ApplyCollision(ply, damage, attacker, bonename, hitgroup, pos, force)
	if not WB.IsBridged(ply) then return false end

	local dmg = DamageInfo()
	dmg:SetDamage(damage * WB.cvCollisionScale:GetFloat())
	dmg:SetDamageType(DMG_CRUSH)
	dmg:SetAttacker(IsValid(attacker) and attacker or game.GetWorld())
	dmg:SetInflictor(IsValid(attacker) and attacker or game.GetWorld())
	if pos then dmg:SetDamagePosition(pos) end
	if force then dmg:SetDamageForce(force) end

	return WB.ApplyDamage(ply, dmg, bonename, hitgroup, dmg:GetDamage() / math.max(WB.cvDamageScale:GetFloat(), 0.0001), true)
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

	local limbId = H.RagdollBoneNameToLimb and H.RagdollBoneNameToLimb(bonename) or "thorax"
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
	org.jawdislocation = false -- (WoundSystem has no jaw)

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

--- hg_fixdislocation <1 legs | 2 arms | 3 jaw> [1 = the one the fixer looks at]. Returns true when handled by the bridge.
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
	if not groups then return true end -- (jaw: WoundSystem has none)

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

function WB.Think(owner, org, dt)
	if not IsValid(owner) or not owner:IsPlayer() or not owner:Alive() then return end

	local wasOtrub = org.otrub
	local body = WB.Sync(owner, org)
	if not body then return end

	org.timeValue = dt

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

	-- one-shot items vanish when used up
	AfterUse(swep, spec, idx)

	return true
end
