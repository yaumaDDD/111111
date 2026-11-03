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

WB.cvEyeChance = WB.cvEyeChance or (ConVarExists("zc_wound_eye_chance") and GetConVar("zc_wound_eye_chance")
	or CreateConVar("zc_wound_eye_chance", "0.04", FCVAR_ARCHIVE,
		"Chance (0..1) that a weapon hit (any firearm, blade, blunt, fists) on the head destroys an eye (2 eyes -> 1 -> blind); 0 = off", 0, 1))

WB.cvDebug = WB.cvDebug or (ConVarExists("zc_woundsystem_bridge_debug") and GetConVar("zc_woundsystem_bridge_debug")
	or CreateConVar("zc_woundsystem_bridge_debug", "0", FCVAR_ARCHIVE, "Print bridge debug output", 0, 1))

-- height (Source units) of a fall from which the legs start to get hurt (dislocation begins, a bit higher it is a fracture).
-- 330 u is about the 3rd balcony of a city block (~6 m). Landing speed = sqrt(2 * sv_gravity * height).
WB.cvFallHeight = WB.cvFallHeight or (ConVarExists("zc_fall_injury_height") and GetConVar("zc_fall_injury_height")
	or CreateConVar("zc_fall_injury_height", "330", FCVAR_ARCHIVE,
		"Fall height (Source units, 52 u = 1 m) from which a landing dislocates / breaks the legs; ~330 = 3rd balcony", 60, 5000))

--- Landing speeds: `safe` = nothing happens up to it, `injury` = bone damage 0.7 (dislocation starts), a bit above it a fracture
function WB.FallSpeeds()
	local g = GetConVar("sv_gravity") and GetConVar("sv_gravity"):GetFloat() or 600
	local injury = math.sqrt(2 * math.max(g, 1) * WB.cvFallHeight:GetFloat())
	local safe = math.min(526.5, injury * 0.85)
	return safe, injury
end

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

local GLASS_SURFACES = {glass = true, glassbottle = true, glassfloor = true, brokenglass = true, glass_breakable = true}
local GLASS_WEAPONS = {weapon_hg_glassshard = true, weapon_hg_glassshard_taped = true, weapon_hg_bottlebroken = true}

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

--- Head hit by any weapon: small chance (zc_wound_eye_chance) to lose an eye. The WoundSystem head.eyes value
--- (2 = both eyes, 1 = one eye gone, 0 = blind) drives its blind screen / moodle / facial expression.
--- A shotgun shot is several pellet hits at once, so there is a short per-player cooldown between rolls.
WB.EyeImmuneDamage = DMG_FALL + DMG_CRUSH + DMG_NERVEGAS + DMG_POISON + DMG_BURN + DMG_SLOWBURN + DMG_DROWN + DMG_RADIATION + DMG_ACID + DMG_SHOCK + DMG_PARALYZE + DMG_DISSOLVE

function WB.EyeHit(ply, limbId, chance)
	if limbId ~= "head" then return false end
	if (ply._WBNextEyeRoll or 0) > CurTime() then return false end
	ply._WBNextEyeRoll = CurTime() + 0.25

	if math.Rand(0, 1) >= (chance or WB.cvEyeChance:GetFloat()) then return false end

	local limbs = WB.GetLimbs(ply)
	local head = limbs and limbs.head
	if not head or head.dismembered then return false end

	local eyes = tonumber(head.eyes) or 2
	if eyes <= 0 then return false end
	head.eyes = eyes - 1

	local H = Health()
	if H and H.SendLimbUpdate then H.SendLimbUpdate(ply, "head", true) end
	dbg("eye lost", ply, head.eyes)

	return true
end

-----------------------------------------------------------------------------------------------------------------------
-- BONES: skull / neck / spine / pelvis
-- WoundSystem has no limb for them, so the bridge keeps the Z-City bone values (0..1) per player (ply._wbBones) and shows
-- them to the Z-City code through the shadow organism (WB.Sync): spine1/2 >= 1 and spine3 >= 0.5 = paralysis (ragdoll,
-- can't move / turn the head), spine3 >= 0.8 = broken neck = instant death (hg.BreakNeck). They do not heal.
-- Direct hits (bullets, blades, blunt) accumulate like Z-City damageBone(); impacts (falls, ragdoll collisions) break the
-- bone when the force passes a random threshold (like the C:U fracture check).
-----------------------------------------------------------------------------------------------------------------------

WB.BoneImmuneDamage = DMG_FALL + DMG_NERVEGAS + DMG_POISON + DMG_BURN + DMG_SLOWBURN + DMG_DROWN + DMG_RADIATION + DMG_ACID + DMG_SHOCK + DMG_PARALYZE + DMG_DISSOLVE

local BONE_TEXT = {
	spine1 = "I don't feel anything below my hips.",
	spine2 = "I cant't feel or move anything below my torso.",
	spine3 = "I can't move at all. I can barely even breathe.",
}

function WB.GetBones(ply)
	ply._wbBones = ply._wbBones or {skull = 0, spine1 = 0, spine2 = 0, spine3 = 0, pelvis = 0}
	return ply._wbBones
end

--- true when the spine / neck stops the player from standing (Z-City: fake_spine1/2 = 1, fake_spine3 = 0.5)
function WB.BonesParalyzed(bones)
	return bones ~= nil and (bones.spine1 >= 1 or bones.spine2 >= 1 or bones.spine3 >= 0.5)
end

--- Z-City damageBone(): crush damage is divided down, the value only grows. Returns the added amount.
local function AddBone(bones, key, bone, dmg, crush)
	if crush then
		local c = math.min((1 - bones[key]) / 0.5, 1) -- util.halfValue2(1 - value, 1, 0.5)
		dmg = dmg / math.max(10 * c * bone, 1)
	end
	local old = bones[key]
	bones[key] = math.min(old + dmg, 1)
	return bones[key] - old
end

--- Consequences of a bone that has just broken (`old` = the values before the hit)
local function BoneEffects(ply, bones, old)
	local H = Health()
	local body = WB.GetBody(ply)
	local broke = false

	for _, key in ipairs({"spine1", "spine2", "spine3"}) do
		local fake = (key == "spine3") and 0.5 or 1
		if old[key] < fake and bones[key] >= fake then
			broke = true
			if ply.Notify then ply:Notify(BONE_TEXT[key], true, key, 2) end
			if body and H and H.Fn and H.Fn.AddBodyShock then H.Fn.AddBodyShock(body, 15) end
		end
	end

	if old.skull < 1 and bones.skull >= 1 then
		broke = true
		if body then
			body.consciousness = math.max((body.consciousness or 100) - 60, 0)
			body.brainHealth = math.max((body.brainHealth or 100) - 8, 0)
			if H and H.Fn and H.Fn.AddBodyShock then H.Fn.AddBodyShock(body, 25) end
		end
	end

	if old.pelvis < 1 and bones.pelvis >= 1 then
		broke = true
		if body and H and H.Fn and H.Fn.AddBodyShock then H.Fn.AddBodyShock(body, 10) end
	end

	if broke then
		ply:EmitSound("bones/bone" .. math.random(8) .. ".mp3", 75, 100, 1, CHAN_AUTO)
		if hg.LightStunPlayer then timer.Simple(0, function() if IsValid(ply) then hg.LightStunPlayer(ply, 2) end end) end
	end

	-- broken neck: dies at once (Z-City: spine3 >= 0.8)
	if old.spine3 < 0.8 and bones.spine3 >= 0.8 and ply:Alive() and hg.BreakNeck then
		hg.BreakNeck(ply)
		return
	end

	if broke then WB.Sync(ply, ply.organism) end
end

--- One hit on the head / torso / abdomen.
---   kind "hit"    amount = damage of the hit (bullets, blades, blunt, fists ...), dmgInfo = its DamageInfo
---   kind "impact" amount = C:U impact force (fall, ragdoll collision), dmgInfo = nil
function WB.BoneHit(ply, limbId, kind, amount, dmgInfo)
	if limbId ~= "head" and limbId ~= "thorax" and limbId ~= "abdomen" then return false end
	if not ply:Alive() or not ply.organism then return false end

	local body, limbs = WB.GetBody(ply), WB.GetLimbs(ply)
	if body and body.isGodMode then return false end
	local l = limbs and limbs[limbId]
	if l and l.dismembered then return false end

	local bones = WB.GetBones(ply)
	local old = table.Copy(bones)
	local blast = dmgInfo and dmgInfo:IsDamageType(DMG_BLAST)
	local crush = not (dmgInfo and dmgInfo:IsDamageType(DMG_BULLET + DMG_BUCKSHOT + DMG_BLAST))

	if kind == "hit" then
		local d = (amount or 0) / 25 -- Z-City: organism damage = damage / 25
		if d <= 0 then return false end

		if limbId == "head" then
			local helmet = ply.armors and ply.armors["head"] ~= nil
			AddBone(bones, "skull", 0.25, d * (helmet and 0.2 or 1), crush)
			if math.Rand(0, 1) < math.Clamp(d * 0.08, 0, 0.35) * (helmet and 0.5 or 1) then
				AddBone(bones, "spine3", 0.1, d * 2 * (helmet and 0.5 or 1), crush)
			end
		elseif limbId == "thorax" then
			if math.Rand(0, 1) < math.Clamp(d * 0.05, 0, 0.25) then
				AddBone(bones, "spine2", 0.1, d * 2 / (blast and 3 or 1), crush)
			end
		else -- abdomen
			AddBone(bones, "pelvis", 1, d * 0.5, crush)
			if math.Rand(0, 1) < math.Clamp(d * 0.05, 0, 0.25) then
				AddBone(bones, "spine1", 0.1, d * 2 / (blast and 3 or 1), crush)
			end
		end
	else
		local jump = (body and body.jumpSpeed) or 6.5
		local force = amount or 0
		if limbId == "head" then
			if force > math.Rand(jump * 4.5, jump * 7) then bones.skull = 1 end
			if force > math.Rand(jump * 6, jump * 9) then bones.spine3 = 1 end
		elseif limbId == "thorax" then
			if force > math.Rand(jump * 5.5, jump * 8.5) then bones.spine2 = 1 end
		else
			if force > math.Rand(jump * 4.5, jump * 7.5) then bones.pelvis = 1 end
			if force > math.Rand(jump * 5.5, jump * 8.5) then bones.spine1 = 1 end
		end
	end

	local changed = false
	for k, v in pairs(bones) do if v ~= old[k] then changed = true break end end
	if not changed then return false end

	dbg("bones", ply, limbId, kind, bones.skull, bones.spine1, bones.spine2, bones.spine3, bones.pelvis)
	BoneEffects(ply, bones, old)

	return true
end

--- Feed one Z-City hit into WoundSystem.
--- ply      living player (already resolved)
--- rawDamage damage after armor/penetration, BEFORE Z-City's per-bone bullet multiplier (WoundSystem has its own)
--- onRagdoll true when the hit landed on the fake ragdoll (limb from the physics bone), false for a standing player
---           (limb from the engine hitgroup: the bone of a player trace is meaningless)
--- Returns true when WoundSystem processed the hit.
--- Fall guard. A fall makes no blood (Z-City dmgBlood = 0): for a few seconds after a landing nothing may open a wound on the
--- player except a real weapon hit or glass. Whatever else tries (ragdoll bounces, rough surfaces, side effects of the knockdown)
--- is undone in WB.Sync, and the limb it happened on is printed with zc_woundsystem_bridge_debug 1.
function WB.StartFallGuard(ply)
	local limbs = WB.GetLimbs(ply)
	if not limbs then return end
	local g = {till = CurTime() + 4, bleed = {}, skin = {}, muscle = {}}
	for id, l in pairs(limbs) do
		g.bleed[id] = l.bleed or 0
		g.skin[id] = l.skin or 100
		g.muscle[id] = l.muscle or 100
	end
	ply._wbFallGuard = g
end

function WB.RunFallGuard(ply, limbs)
	local g = ply._wbFallGuard
	if not g then return end
	if CurTime() > g.till then ply._wbFallGuard = nil return end

	local H = Health()
	for id, l in pairs(limbs) do
		local b, base = l.bleed or 0, g.bleed[id] or 0
		if b > base + 0.01 then
			dbg("fall guard: undone bleeding", ply, id, "+" .. string.format("%.2f", b - base))
			l.bleed = base
			if H and H.SendLimbUpdate then H.SendLimbUpdate(ply, id, true) end
		elseif b < base then
			g.bleed[id] = b -- it was healed meanwhile
		end
		local mu, mbase = l.muscle or 100, g.muscle[id] or 100
		if mu < mbase - 2 and not (string.find(id, "^crus_") or string.find(id, "^foot_")) then
			dbg("fall guard: undone muscle damage", ply, id, "-" .. string.format("%.1f", mbase - mu))
			l.muscle = mbase
			if H and H.SendLimbUpdate then H.SendLimbUpdate(ply, id, true) end
		elseif mu > mbase then
			g.muscle[id] = mu
		end
		local sk, sbase = l.skin or 100, g.skin[id] or 100
		if sk < sbase - 0.01 then
			l.skin = sbase
			if H and H.SendLimbUpdate then H.SendLimbUpdate(ply, id, true) end
		elseif sk > sbase then
			g.skin[id] = sk
		end
	end
end

function WB.ApplyDamage(ply, dmgInfo, bonename, hitgroup, rawDamage, onRagdoll)
	if not WB.IsBridged(ply) then return false end

	local H = Health()
	if not H or not H.HandleDamage then return false end
	if dmgInfo:IsDamageType(DMG_DISSOLVE) then return false end

	local damage = (rawDamage or dmgInfo:GetDamage()) * WB.cvDamageScale:GetFloat()
	if damage <= 0 then return true end

	-- nerve gas: Z-City gives it no wound, only the lung damage (hg.organism.GasDamage -> WB.SyncToxins)
	if dmgInfo:IsDamageType(DMG_NERVEGAS) and not dmgInfo:IsDamageType(DMG_BULLET + DMG_BLAST + DMG_SLASH + DMG_CLUB + DMG_BUCKSHOT) then return true end

	-- a real hit (not a fall): the fall guard is over
	if ply._wbFallGuard and not dmgInfo:IsDamageType(DMG_FALL + DMG_CRUSH) then ply._wbFallGuard = nil end

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

	-- skull / neck / spine / pelvis (bones WoundSystem has no limb for)
	if ply:Alive() and not dmgInfo:IsDamageType(WB.BoneImmuneDamage) then
		WB.BoneHit(ply, limb or (hitgroup and WB.HitgroupToWS[hitgroup]), "hit", damage, dmgInfo)
	end

	-- any weapon hit on the head (firearm, blade, blunt, fists, shrapnel ...): small chance to destroy an eye.
	-- Not weapons: falls, prop crush, gas / poison, fire, drowning, radiation, acid, shock.
	if ply:Alive() and not dmgInfo:IsDamageType(WB.EyeImmuneDamage) then
		WB.EyeHit(ply, limb or (hitgroup and WB.HitgroupToWS[hitgroup]))
	end

	-- hit with a glass shard / broken bottle: pieces stay in the wound
	local inf = dmgInfo:GetInflictor()
	if IsValid(inf) and GLASS_WEAPONS[inf:GetClass()] and not dmgInfo:IsDamageType(DMG_BULLET + DMG_BLAST) then
		WB.GlassShards(ply, limb or (hitgroup and WB.HitgroupToWS[hitgroup]) or "thorax", 0.5)
	end

	-- make the result visible to Z-City at once (otrub / fake / death are evaluated from the shadow)
	if ply:Alive() and ply.organism then
		WB.Sync(ply, ply.organism)
	end

	return true
end

-----------------------------------------------------------------------------------------------------------------------
-- COLLISIONS, FALLS, GLASS  (Z-City filters/structure, the damage itself is the C:U impact model)
-----------------------------------------------------------------------------------------------------------------------
--- Embed `count` C:U shrapnel pieces (glass) into a limb: they are pulled out with the C:U shrapnel minigame
function WB.AddShards(ply, limbId, count)
	local H = Health()
	if not (WB.IsBridged(ply) and H and H.AddLimbShrapnel) then return false end
	return H.AddLimbShrapnel(ply, limbId, count or 1)
end

--- Glass leaves 3, 4 or 5 shards in the limb, with the given chance
function WB.GlassShards(ply, limbId, chance)
	if math.random() > (chance or 1) then return false end
	return WB.AddShards(ply, limbId or "thorax", math.random(3, 5))
end

--- Only arms and legs count for glass hits of a ragdoll (hands, feet, shins, forearms, ...)
function WB.IsExtremity(limbId)
	return limbId ~= nil and limbId ~= "head" and limbId ~= "thorax" and limbId ~= "abdomen"
end

--- A kick through a window: the kicking foot gets shards
function WB.KickGlass(ply, right)
	return WB.GlassShards(ply, right and "foot_R" or "foot_L", 0.6)
end

--- Rough surfaces / glass cut the limb that hit them (Z-City: `bleedSurfaces`, 50%)
function WB.SurfaceCut(ply, limbId, force, surface)
	local H = Health()
	local limbs = WB.GetLimbs(ply)
	local body = WB.GetBody(ply)
	local l = limbs and limbs[limbId]
	if not l or l.dismembered then return false end

	local jump = (body and body.jumpSpeed) or 6.5
	if force <= jump * 1.2 or math.random(2) ~= 1 then return false end
	ply._wbFallGuard = nil -- a cut by glass is allowed

	l.skin = math.Clamp((l.skin or 100) - force * 0.8, 0, 100)
	l.bleed = math.Clamp((l.bleed or 0) + force * 0.2, 0, 100)
	if H.Fn and H.Fn.ClearLimbBandage then H.Fn.ClearLimbBandage(l) end
	if H.SendLimbUpdate then H.SendLimbUpdate(ply, limbId, true) end

	return true
end

--- Impact force of a ragdoll collision in C:U units (same conversion C:U uses for its own ragdoll: speed * |cos| / 50)
function WB.ImpactForce(ply, speed, dot, massK)
	local body = WB.GetBody(ply)
	local jump = (body and body.jumpSpeed) or 6.5
	return math.Clamp((speed or 0) * (dot or 1) * (massK or 1) / 50, 0, jump * 7) * WB.cvCollisionScale:GetFloat()
end

--- One impact on a limb through the C:U impact model (muscle, pain, skin, bleeding, dislocation, fracture, internal bleeding, head).
--- Returns true when the bridge handled it.
function WB.ApplyImpact(ply, limbId, force, surface)
	if not WB.IsBridged(ply) then return false end

	local H = Health()
	if not (H and H.ProcessImpactDamage) then return false end

	local body = WB.GetBody(ply)
	if not body then return false end
	if body.isGodMode then return true end

	local jump = body.jumpSpeed or 6.5

	limbId = limbId or "thorax"
	if H.Fn and H.Fn.ResolveLivingLimb then limbId = H.Fn.ResolveLivingLimb(ply, limbId) or limbId end

	-- glass: an arm or a leg that hit it picks up shards (3-5), whatever the force of the impact
	if surface and GLASS_SURFACES[surface] and WB.IsExtremity(limbId) then
		ply._wbGlassCd = ply._wbGlassCd or {}
		if (ply._wbGlassCd[limbId] or 0) < CurTime() then
			ply._wbGlassCd[limbId] = CurTime() + 0.5
			WB.GlassShards(ply, limbId, 0.6)
		end
	end

	if force <= jump then return true end

	-- the same per-limb cooldown C:U uses for physics impacts
	local now = CurTime()
	ply._nextLimbPhysicsDamage = ply._nextLimbPhysicsDamage or {}
	if (ply._nextLimbPhysicsDamage[limbId] or 0) > now then return true end
	ply._nextLimbPhysicsDamage[limbId] = now + 0.22

	H.ProcessImpactDamage(ply, limbId, force)
	-- falls / ragdoll hits make no blood (Z-City dmgBlood = 0): only broken glass cuts
	if surface and GLASS_SURFACES[surface] then WB.SurfaceCut(ply, limbId, force, surface) end
	WB.BoneHit(ply, limbId, "impact", force)

	if ply.organism then WB.Sync(ply, ply.organism) end
	dbg("impact", ply, limbId, force)

	return true
end

--- Ragdoll collision (Z-City `velocityDamage`, after its speed / throttling filters).
function WB.ApplyCollision(ply, speed, dot, massK, attacker, bonename, hitgroup, surface)
	if not WB.IsBridged(ply) then return false end

	local limb = WB.ResolveLimb(ply, bonename, hitgroup)
	if IsValid(attacker) and attacker:IsPlayer() then ply._WBLastCollisionAttacker = attacker end

	return WB.ApplyImpact(ply, limb, WB.ImpactForce(ply, speed, dot, massK), surface)
end

--- The landing of a standing player is processed from its real speed in WB.LandingHit (OnPlayerHitGround). The engine DMG_FALL
--- damage only comes as a fallback: with mp_falldamage 0 it is a flat 10, and the order of the two events is not defined, so it is
--- postponed by a moment and dropped if the landing hook did the job.
function WB.ApplyFall(ply, dmgInfo)
	if not WB.IsBridged(ply) then return false end

	local engineDamage = dmgInfo:GetDamage()
	local askedAt = CurTime()
	timer.Simple(0.05, function()
		if not IsValid(ply) or not ply:Alive() then return end
		if (ply._wbFallHookAt or 0) >= askedAt - 0.3 then return end -- the landing hook has handled it
		if IsValid(ply.FakeRagdoll) then return end -- ragdoll: the collisions are counted by WB.ApplyCollision

		local dmg = DamageInfo()
		dmg:SetDamage(engineDamage)
		dmg:SetDamageType(DMG_FALL)
		dmg:SetAttacker(game.GetWorld())
		dmg:SetInflictor(game.GetWorld())
		WB.ApplyDamage(ply, dmg, nil, nil, engineDamage, false)
	end)
	return true
end

--- Landing of a standing player: the real landing speed gives the fall damage, WoundSystem turns it into leg bone damage
--- (fracture / dislocation, no blood). Z-City's own `fallStun` hook may already have knocked the player into a ragdoll in the same
--- tick (hg.LightStunPlayer is synchronous and the hook order is undefined), so a ragdoll made just now does not count as "in ragdoll".
function WB.LandingHit(ply, inWater, onFloater, speed)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
	if inWater or onFloater or not WB.IsBridged(ply) then return end

	if (ply._wbFallHookAt or 0) > CurTime() - 0.3 then return end -- this landing was already handled (engine hook / tracker)

	local rag = ply.FakeRagdoll
	if IsValid(rag) and rag:GetCreationTime() < CurTime() - 0.2 then
		dbg("landing ignored: already in a ragdoll", ply, nil, "speed " .. math.floor(tonumber(speed) or 0))
		return -- really in a ragdoll already
	end

	speed = tonumber(speed) or 0
	local safe, injury = WB.FallSpeeds()
	dbg("landing", ply, nil, "speed " .. math.floor(speed) .. " (injury from " .. math.floor(injury) .. ")")
	if speed <= safe then return end

	ply._wbFallHookAt = CurTime()
	-- hand the exact landing speed to WoundSystem (its own hook may run later in the same tick)
	ply._woundSystemLastFallSpeed = speed
	ply._woundSystemLastFallSpeedTime = CurTime()
	ply._woundSystemLastFallOnFloater = false

	WB.StartFallGuard(ply)

	local dmg = DamageInfo()
	dmg:SetDamage(math.max((speed - 526.5) / 3.96, 0.01))
	dmg:SetDamageType(DMG_FALL)
	dmg:SetAttacker(game.GetWorld())
	dmg:SetInflictor(game.GetWorld())
	WB.ApplyDamage(ply, dmg, nil, nil, dmg:GetDamage(), false)
end

--- Own landing detector: the engine hook is not reliable (hook order, other addons that return a value from it, noclip -> walk
--- switch ...), so the fall speed is also tracked from the player's velocity. Whichever notices the landing first handles it.
hook.Add("Move", "ZCity_WoundBridge_FallTrack", function(ply, mv)
	if not IsValid(ply) or not ply:Alive() then return end

	local air = (not ply:IsOnGround()) and ply:GetMoveType() == MOVETYPE_WALK and not IsValid(ply.FakeRagdoll)
		and ply:WaterLevel() < 2 and not ply:InVehicle()
	if air then
		local vz = -mv:GetVelocity().z
		if vz > (ply._wbAirSpeed or 0) then ply._wbAirSpeed = vz end
		ply._wbWasAir = true
		return
	end

	if ply._wbWasAir then
		local speed = ply._wbAirSpeed or 0
		ply._wbWasAir = nil
		ply._wbAirSpeed = nil
		if ply:IsOnGround() and speed > 300 then
			dbg("tracker landing", ply, nil, "speed " .. math.floor(speed))
			WB.LandingHit(ply, false, false, speed)
		end
	else
		ply._wbAirSpeed = nil
	end
end)

-- diagnostics for the leg bone damage of a fall (zc_woundsystem_bridge_debug 1)
local function hookFallDebug()
	local H = Health()
	if H then H.FallDebug = function(ply, limb, force, bone) dbg("fall bone", ply, limb, "force " .. string.format("%.1f", force) .. " bone " .. string.format("%.2f", bone)) end end
end
hookFallDebug()
hook.Add("InitPostEntity", "ZCity_WoundBridge_FallDebug", hookFallDebug)

hook.Add("OnPlayerHitGround", "ZCity_WoundBridge_Fall", function(ply, inWater, onFloater, speed)
	WB.LandingHit(ply, inWater, onFloater, speed)
end)

--- Z-City legs(): a broken / dislocated leg stuns the player (hg.LightStunPlayer(owner, 2))
local function LegStun(ply, limbName)
	if not IsValid(ply) or not WB.IsBridged(ply) or not hg.LightStunPlayer then return end
	if not (string.find(limbName, "^thigh_") or string.find(limbName, "^crus_") or string.find(limbName, "^foot_")) then return end
	timer.Simple(0, function() if IsValid(ply) and ply:Alive() then hg.LightStunPlayer(ply, 2) end end)
end
hook.Add("WoundSystem_OnFracture", "ZCity_WoundBridge_LegStun", LegStun)
hook.Add("WoundSystem_OnDislocate", "ZCity_WoundBridge_LegStun", LegStun)

--- Z-City AddWoundManual (gibs, glass, explosion cuts): turn it into WoundSystem bleeding
function WB.AddWoundManual(ent, dmgBlood, bone, glass)
	local ply = WB.GetPlayer(ent)
	if not WB.IsBridged(ply) then return false end

	local H = Health()
	local limbs = WB.GetLimbs(ply)
	if not limbs then return true end

	if ply._wbFallGuard then
		if not glass then
			dbg("fall guard: wound ignored", ply, tostring(bone), tonumber(dmgBlood))
			return true
		end
		ply._wbFallGuard = nil
	end

	local bonename = bone
	if isnumber(bone) then bonename = ent:GetBoneName(bone) end

	local limbId = H.RagdollBoneNameToLimb and H.RagdollBoneNameToLimb(bonename) or "thorax"
	local limb = limbs[limbId or "thorax"]
	if limb and not limb.dismembered then
		limb.bleed = math.Clamp((limb.bleed or 0) + (tonumber(dmgBlood) or 0) * 0.04, 0, 100)
		if glass then
			-- broken glass: a deeper cut and shards left in the wound (pulled out with the C:U shrapnel minigame)
			limb.skin = math.Clamp((limb.skin or 100) - (tonumber(dmgBlood) or 0) * 0.5, 0, 100)
			WB.GlassShards(ply, limbId or "thorax", 0.75)
		end
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

--- a fracture nobody set yet (Z-City bone = 1): the shadow organism shows it as 1 so the Z-City bandage code accepts the patient
local function AnyUnsetFracture(limbs, names)
	for _, id in ipairs(names) do
		local l = limbs[id]
		if type(l) == "table" and l.broken and not l.dismembered and (tonumber(l.boneHealTimer) or 100) > 95 then return true end
	end
	return false
end

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
	if limbs and ply._wbFallGuard then WB.RunFallGuard(ply, limbs) end

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
	local bones = WB.GetBones(ply)
	org.canmove = not otrub and bones.spine2 < 1 and bones.spine3 < 0.5
	org.canmovehead = not otrub and bones.spine3 < 0.5

	if org.stamina then
		org.stamina[1] = math.Clamp((body.stamina or 100) / 100, 0, 1) * (org.stamina.max or 180)
		org.stamina.subadd = 0 -- Z-City stamina costs are not charged to WoundSystem stamina (WoundSystem has its own)
	end

	-- limbs: show WoundSystem limb strength to the Z-City code that reads org.larm/lleg (aim sway, limp...)
	if limbs then
		org.larm = AnyUnsetFracture(limbs, armL) and 1 or 1 - Strength(H, ply, armL)
		org.rarm = AnyUnsetFracture(limbs, armR) and 1 or 1 - Strength(H, ply, armR)
		org.lleg = AnyUnsetFracture(limbs, legL) and 1 or 1 - Strength(H, ply, legL)
		org.rleg = AnyUnsetFracture(limbs, legR) and 1 or 1 - Strength(H, ply, legR)

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
	-- (the bone values are the bridge ones: WB.BoneHit)
	org.spine1, org.spine2, org.spine3 = bones.spine1, bones.spine2, bones.spine3
	org.pelvis, org.skull = bones.pelvis, bones.skull
	org.chest = (limbs and AnyUnsetFracture(limbs, {"thorax"})) and 1 or 0
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
	local needfake = body.unconscious or body.fallingRagdoll or WB.BonesParalyzed(bones) or (org.llegamputated or org.rlegamputated)
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
	ply._wbBones = nil -- broken skull / neck / spine heal with the reset

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
-- BLOOD  (WoundSystem limb bleeding -> Z-City wounds / arterial wounds)
--
-- WoundSystem's own blood effects are gone. The blood the player sees is Z-City's: the client `organism-think-client-blood`
-- think draws droplets / streams / fountains for every entry of `ply.wounds` and `ply.arterialwounds` (bone-local
-- positions, so the blood follows the limb, in the fake ragdoll too). Those lists are rebuilt here from the bleeding
-- of the WoundSystem limbs, i.e. per limb, like in the original Z-City.
-----------------------------------------------------------------------------------------------------------------------

local B_HEAD, B_NECK = "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Neck1"
local B_CLAV = "ValveBiped.Bip01_Spine2"
local B_PELVIS = "ValveBiped.Bip01_Pelvis"

local WoundBones, StumpBones, WoundOrder = {head = B_HEAD, thorax = B_CLAV, abdomen = "ValveBiped.Bip01_Spine1"}, {head = B_NECK}, {"head", "thorax", "abdomen"}

for _, side in ipairs({"L", "R"}) do
	local pre = "ValveBiped.Bip01_" .. side .. "_"
	WoundBones["arm_" .. side], StumpBones["arm_" .. side] = pre .. "UpperArm", B_CLAV
	WoundBones["forearm_" .. side], StumpBones["forearm_" .. side] = pre .. "Forearm", pre .. "UpperArm"
	WoundBones["hand_" .. side], StumpBones["hand_" .. side] = pre .. "Hand", pre .. "Forearm"
	WoundBones["thigh_" .. side], StumpBones["thigh_" .. side] = pre .. "Thigh", B_PELVIS
	WoundBones["crus_" .. side], StumpBones["crus_" .. side] = pre .. "Calf", pre .. "Thigh"
	WoundBones["foot_" .. side], StumpBones["foot_" .. side] = pre .. "Foot", pre .. "Calf"
	for _, base in ipairs({"arm_", "forearm_", "hand_", "thigh_", "crus_", "foot_"}) do
		WoundOrder[#WoundOrder + 1] = base .. side
	end
end

local ARTERY_DIR = Vector(-100, 0, 0)

--- effective bleeding of a WoundSystem limb (0 when the tourniquet holds it)
local function LimbBleed(l)
	if type(l) ~= "table" or l.blockedBleeding then return 0 end
	local b = tonumber(l.bleed) or 0
	if l.isBandaged then b = b * 0.5 end
	return b
end

function WB.SyncWounds(ply, org, limbs)
	if not IsValid(ply) or not org or type(limbs) ~= "table" then return end

	local now = CurTime()
	if (ply._wbWoundNext or 0) > now then return end
	ply._wbWoundNext = now + 0.25

	local geo = ply._wbWoundGeo
	if not geo then geo = {} ply._wbWoundGeo = geo end

	local wounds, arterial, sig = {}, {}, {}

	for _, id in ipairs(WoundOrder) do
		local l = limbs[id]
		local bleed = LimbBleed(l)

		if bleed >= 0.5 then
			local stump = l.dismembered and true or false
			local bone = (stump and StumpBones[id]) or WoundBones[id]
			local n = (bleed < 25 and 1) or (bleed < 60 and 2) or 3
			-- quantised so the lists are not re-sent for every tiny change of the bleeding
			local sev = math.Clamp(math.Round(bleed / 4 / n * 2) / 2, 0.5, 25)

			local g = geo[id]
			if not g then g = {} geo[id] = g end

			for i = 1, n do
				local e = g[i]
				if not e or e.bone ~= bone then
					e = {
						bone = bone,
						pos = VectorRand(-2.5, 2.5),
						ang = Angle(math.Rand(-180, 180), math.Rand(-180, 180), 0),
						time = now + math.Rand(0, 1),
					}
					if stump then e.pos = Vector(0, 0, 0) + VectorRand(-1.5, 1.5) end
					g[i] = e
				end
				wounds[#wounds + 1] = {sev, e.pos, e.ang, bone, e.time}
			end

			local art = (stump and bleed >= 2) or bleed >= 55
			if art then
				local asev = math.Clamp(math.Round(bleed / 20), 1, 6)
				local key = id .. "artery"
				local e = g.artery
				if not e or e.bone ~= bone then
					e = {bone = bone, pos = stump and Vector(0, 0, 0) or VectorRand(-1.5, 1.5), time = now}
					g.artery = e
				end
				arterial[#arterial + 1] = {asev, e.pos, Angle(), bone, e.time, ARTERY_DIR, key}
				sig[#sig + 1] = id .. ":" .. n .. ":" .. sev .. ":" .. asev
			else
				sig[#sig + 1] = id .. ":" .. n .. ":" .. sev
			end
		else
			geo[id] = nil
		end
	end

	local sigStr = table.concat(sig, "|")

	-- rebuild when the bleeding changed, or when something else (legacy code, Clear, spawn) replaced the lists
	if ply._wbWoundSig == sigStr and org.wounds == ply._wbWounds and org.arterialwounds == ply._wbArterial
		and #org.wounds == #wounds and #org.arterialwounds == #arterial then return end

	ply._wbWoundSig, ply._wbWounds, ply._wbArterial = sigStr, wounds, arterial
	org.wounds, org.arterialwounds = wounds, arterial
	ply:SetNetVar("wounds", wounds)
	ply:SetNetVar("arterialwounds", arterial)
end

-- blood vomit of WoundSystem: only the Z-City blood spray of hg.organism.Vomit (no sound / state, WoundSystem has its own)
hook.Add("WoundSystem_BloodVomitVisual", "ZCity_WoundBridge_BloodVomit", function(ply, body)
	if not WB.IsBridged(ply) then return end

	local ent = hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply) or ply
	if not IsValid(ent) then return end

	local bon = "ValveBiped.Bip01_Head1"
	local bone = ent:LookupBone(bon)
	local mat = bone and ent:GetBoneMatrix(bone)
	if not mat then return end

	local org = ply.organism
	local pulse = org and org.pulse or 70

	net.Start("bloodsquirt2")
	net.WriteEntity(ent)
	net.WriteString(bon)
	net.WriteMatrix(mat)
	net.WriteVector(mat:GetTranslation() + mat:GetAngles():Right() * 6 + mat:GetAngles():Forward() * 1)
	net.WriteVector(mat:GetAngles():Right() * 2 * math.Clamp(pulse / 70, 0.4, 1))
	net.Broadcast()
end)

-----------------------------------------------------------------------------------------------------------------------
-- BANDAGES ON THE BODY  (WoundSystem limb.isBandaged -> Z-City `bandaged_limbs` netvar, drawn by hg.RenderBandages)
-----------------------------------------------------------------------------------------------------------------------
local BandageBones = {
	thorax = "ValveBiped.Bip01_Spine2", abdomen = "ValveBiped.Bip01_Spine1",
}
for _, side in ipairs({"L", "R"}) do
	local pre = "ValveBiped.Bip01_" .. side .. "_"
	BandageBones["arm_" .. side], BandageBones["forearm_" .. side], BandageBones["hand_" .. side] = pre .. "UpperArm", pre .. "Forearm", pre .. "Hand"
	BandageBones["thigh_" .. side], BandageBones["crus_" .. side], BandageBones["foot_" .. side] = pre .. "Thigh", pre .. "Calf", pre .. "Calf"
end

function WB.SyncBandages(ply, limbs)
	if not IsValid(ply) or type(limbs) ~= "table" then return end

	local now = CurTime()
	if (ply._wbBandNext or 0) > now then return end
	ply._wbBandNext = now + 0.3

	local set, keys = {}, {}
	for id, l in pairs(limbs) do
		local bone = BandageBones[id]
		if bone and type(l) == "table" and l.isBandaged and not l.dismembered and not set[bone] then
			set[bone] = true
			keys[#keys + 1] = bone
		end
	end
	table.sort(keys)
	local sig = table.concat(keys, "|")

	-- same bandages and nobody else replaced the list (Z-City clears it on spawn / death)
	if ply._wbBandSig == sig and ply.bandaged_limbs == ply._wbBand then return end

	ply._wbBandSig, ply._wbBand = sig, set
	ply.bandaged_limbs = set
	ply:SetNetVar("bandaged_limbs", set)

	local rag = ply.FakeRagdoll
	if IsValid(rag) then
		rag.bandaged_limbs = table.Copy(set)
		rag:SetNetVar("bandaged_limbs", rag.bandaged_limbs)
	end
end

-----------------------------------------------------------------------------------------------------------------------
-- POISON / GAS  (Z-City structure, the oxygen itself is the WoundSystem blood oxygen)
--   gas          hg.organism.GasDamage -> org.wbLungs (lung damage). Damaged lungs lower the breathing efficiency (Z-City:
--                OxygenateBlood), 100% = no oxygen intake at all -> blood oxygen falls -> brain damage -> death
--   poison1/2/3  tetrodotoxin / contact poison / cyanide gas: 30 s after the dose the oxygen regeneration stops (org.o2.regen = 0)
--   Poison_KCN   cyanide capsule: after 22/potency s stamina and oxygen are capped, after 90/potency s regeneration stops
--   held breath  (Z-City key) no intake while held, released at low oxygen like the Z-City lungs module
-----------------------------------------------------------------------------------------------------------------------
local POISON_DELAY = 30        -- s from the dose until the oxygen regeneration stops (poison1/2/3)
local POISON_O2_DRAIN = 1.0    -- extra blood oxygen loss (%/s) while the regeneration is stopped
local HOLD_O2_DRAIN = 0.7      -- extra blood oxygen loss (%/s) while the breath is held
local HOLD_RELEASE_O2 = 70     -- the breath is released below this blood oxygen
local LUNG_HEAL_TIME = 1800    -- s for lungs to recover fully (Z-City: 30 minutes)

local function SendHoldBreath(org)
	net.Start("organism_send")
	net.WriteTable({holdingbreath = org.holdingbreath, owner = org.owner})
	net.WriteBool(true)
	net.WriteBool(false)
	net.WriteBool(false)
	net.WriteBool(true)
	net.Send(org.owner)
end

function WB.SyncToxins(owner, org, body, dt)
	local now = CurTime()

	-- lungs (gas)
	local lungs = math.Clamp(org.wbLungs or 0, 0, 1)
	if lungs > 0 and (body.brainHealth or 100) > 60 then
		lungs = math.max(lungs - dt / ((org.thiamine or 0) > 0 and LUNG_HEAL_TIME / 3.75 or LUNG_HEAL_TIME), 0)
	end
	org.wbLungs = lungs > 0 and lungs or nil
	if org.lungsL and org.lungsR then
		-- legacy organ hits do not count: the lungs of the shadow are the gas damage only
		org.lungsL[1], org.lungsR[1] = lungs, lungs
	end

	local intake = math.Clamp((1 - lungs) * (1 - (org.trachea or 0)), 0, 1)

	-- poisons: the regeneration of the oxygen stops
	local noRegen = false
	for _, key in ipairs({"poison1", "poison2", "poison3"}) do
		local t = org[key]
		if t and now - t > POISON_DELAY then noRegen = true end
	end

	local o2Cap, staminaCap
	local kcn = org.Poison_KCN
	if kcn and kcn.StartTime then
		local potency = math.max(kcn.Potency or 1, 0.1)
		local el = now - kcn.StartTime
		if el > 22 / potency then
			staminaCap = 50 / potency
			o2Cap = 100 / potency
		end
		if el > 90 / potency then noRegen = true end
	end

	-- extinguisher powder in the face: no intake for a moment
	local sprayed = org.is_sprayed_at
	org.is_sprayed_at = nil

	local holding = org.holdingbreath and true or false
	if holding and (body.bloodOxygen or 100) < HOLD_RELEASE_O2 then
		holding = false
		org.holdingbreath = false
		owner.releasebreathe = nil
		owner:EmitSound(ThatPlyIsFemale and ThatPlyIsFemale(owner) and ("breathing/exhale/female/exhale_0" .. math.random(5) .. ".wav")
			or ("breathing/exhale/male/exhale_0" .. math.random(5) .. ".wav"), 65)
		SendHoldBreath(org)
	end

	local penalty = 100 * (1 - intake)
	if noRegen or sprayed then penalty = 100 end

	body.zcRespPenalty = penalty > 0 and penalty or nil
	body.zcOxygenDrain = (noRegen and POISON_O2_DRAIN or 0) + (holding and HOLD_O2_DRAIN or 0)
	body.zcHoldBreath = holding or nil
	body.zcOxygenCap = o2Cap

	if staminaCap then body.stamina = math.min(body.stamina or 100, staminaCap) end

	-- the Z-City side (breathing sounds, moodles, screen) reads the shadow oxygen
	if org.o2 then
		org.o2[1] = math.Clamp((body.bloodOxygen or 100) / 100, 0, 1) * (org.o2.range or 30)
	end
end

hook.Add("Org Clear", "ZCity_WoundBridge_Toxins", function(org)
	org.wbLungs = nil
end)

function WB.Think(owner, org, dt)
	if not IsValid(owner) or not owner:IsPlayer() or not owner:Alive() then return end

	local wasOtrub = org.otrub
	local body = WB.Sync(owner, org)
	if not body then return end

	WB.SyncWounds(owner, org, WB.GetLimbs(owner))
	WB.SyncBandages(owner, WB.GetLimbs(owner))
	WB.SyncToxins(owner, org, body, dt)

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
	ply._wbBones = nil
	ply._WBLimbSnapshot = nil
	ply._wbWoundSig, ply._wbWounds, ply._wbArterial, ply._wbWoundGeo, ply._wbWoundNext = nil, nil, nil, nil, nil
	ply._wbBandSig, ply._wbBand, ply._wbBandNext = nil, nil, nil
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

		-- an unset fracture also wants a bandage (Z-City: the bandage sets the bone)
		local fracture = spec.kind == "bandage" and state.broken and (state.boneHealTimer or 100) > 95
		local score = (state.bleed or 0) + (fracture and 0.2 or 0) + ((id == preferred) and 1000 or 0)
		if ((state.bleed or 0) > 0.1 or fracture) and score > best then
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

			local function Nothing() end -- nothing applied: silently, the sweep is not spent

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

-----------------------------------------------------------------------------------------------------------------------
-- WOUND VIEW (HUD) MINIGAMES WITH A CARRIED ITEM
--   The wound view asks for a minigame that needs a medical item: the Z-City item the player carries is used up exactly
--   as when it is used from the hands (same specs, same smooth partial use).
-----------------------------------------------------------------------------------------------------------------------
local HudBandagePriority = {weapon_bandage_sh = 1, weapon_bigbandage_sh = 2, weapon_medkit_sh = 3}

function WB.StartHud(ply, kind, limbId)
	if not WB.IsBridged(ply) or not WB.cvMinigame:GetBool() then return false end

	local limbs = WB.GetLimbs(ply)
	local l = limbs and limbs[limbId]
	if type(l) ~= "table" or l.dismembered then return false end

	if kind == "bandage" then
		-- only where something bleeds (a bandage over shrapnel / glass is allowed: it will infect, see WoundSystem)
		if l.isBandaged then return false end
		if (tonumber(l.bleed) or 0) <= 0.1 and (tonumber(l.shrapnel) or 0) <= 0
			and not (l.broken and (tonumber(l.boneHealTimer) or 100) > 95) then return false end

		local best, bestSpec, bestIdx, bestRank
		for _, w in ipairs(ply:GetWeapons()) do
			local rank = HudBandagePriority[w:GetClass()]
			if rank and (not bestRank or rank < bestRank) then
				local idx = 1
				local spec = (w:GetClass() == "weapon_medkit_sh") and WB.MedkitModes[1] or WB.SwepSpecs[w:GetClass()]
				if spec and spec.kind == "bandage" and Remaining(w, idx) > 0 then
					best, bestSpec, bestIdx, bestRank = w, spec, idx, rank
				end
			end
		end

		if not best then return false end
		return StartMinigame(best, bestSpec, bestIdx, ply, limbId) ~= nil
	end

	return false
end

hook.Add("WoundSystem_HudMinigame", "ZCity_WoundBridge_Hud", function(ply, kind, limbId)
	WB.StartHud(ply, kind, limbId)
end)
