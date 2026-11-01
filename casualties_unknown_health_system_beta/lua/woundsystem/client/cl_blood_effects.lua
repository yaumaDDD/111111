if WoundSystem and WoundSystem.BloodEffects and WoundSystem.BloodEffects._Loaded then
    hook.Remove("PostDrawTranslucentRenderables", "WoundSystem_BloodEffects_Draw")
    hook.Remove("Think", "WoundSystem_BloodEffects_Think")
    concommand.Remove("woundsys_blood_clear")
end

WoundSystem = WoundSystem or {}
WoundSystem.BloodEffects = WoundSystem.BloodEffects or {}
WoundSystem.BloodEffects._Loaded = true

local cvEnabled = CreateClientConVar("woundsys_blood_effects", "1", true, false, "Draw decorative WoundSystem blood effects.", 0, 1)
local cvColorMode = CreateClientConVar("woundsys_blood_color", "alien_yellow", true, false, "Blood effect color: alien_yellow or red.")
local cvBloodR = CreateClientConVar("woundsys_blood_r", "255", true, false, "Blood Red component (0-255).", 0, 255)
local cvBloodG = CreateClientConVar("woundsys_blood_g", "236", true, false, "Blood Green component (0-255).", 0, 255)
local cvBloodB = CreateClientConVar("woundsys_blood_b", "58", true, false, "Blood Blue component (0-255).", 0, 255)
local cvStains = CreateClientConVar("woundsys_blood_stains", "1", true, false, "Draw WoundSystem blood stains.", 0, 1)
local cvTrails = CreateClientConVar("woundsys_blood_trails", "1", true, false, "Draw WoundSystem bleeding trails.", 0, 1)
local cvMaxStains = CreateClientConVar("woundsys_blood_max_stains", "160", true, false, "Maximum decorative WoundSystem blood stains.", 0, 250)
local cvQuality = CreateClientConVar("woundsys_blood_quality", "1", true, false, "WoundSystem blood effect quality.", 0, 2)
local cvBodyFlow = CreateClientConVar("woundsys_blood_bodyflow", "1", true, false, "Draw fresh blood flowing along player and ragdoll bodies.", 0, 1)
local cvBodyFlowMax = CreateClientConVar("woundsys_blood_bodyflow_max", "0", true, false, "Maximum body-following blood streaks. 0 uses quality-based automatic limits.", 0, 96)
local cvBodyFlowAlpha = CreateClientConVar("woundsys_blood_bodyflow_alpha", "1", true, false, "Alpha multiplier for body-following blood streaks.", 0, 2)

local matYellow = Material("decals/yblood1")
local matYellowAlt = Material("decals/yblood2")
local matRed = Material("decals/blood1")
local matRedAlt = Material("decals/blood2")
local bodyFlowYellowAltTexture = matYellowAlt:IsError() and "decals/yblood1" or "decals/yblood2"
local bodyFlowRedAltTexture = matRedAlt:IsError() and "decals/blood1" or "decals/blood2"
if matYellowAlt:IsError() then matYellowAlt = matYellow end
if matRedAlt:IsError() then matRedAlt = matRed end

local function CreateBodyFlowMaterial(name, texturePath)
    return CreateMaterial(name, "UnlitGeneric", {
        ["$basetexture"] = texturePath,
        ["$translucent"] = "1",
        ["$vertexalpha"] = "1",
        ["$vertexcolor"] = "1",
        ["$nocull"] = "1",
        ["$ignorez"] = "0"
    })
end

local bodyFlowYellow = CreateBodyFlowMaterial("WoundSystem_BodyFlow_AlienYellowV2_1", "decals/yblood1")
local bodyFlowYellowAlt = CreateBodyFlowMaterial("WoundSystem_BodyFlow_AlienYellowV2_2", bodyFlowYellowAltTexture)
local bodyFlowRed = CreateBodyFlowMaterial("WoundSystem_BodyFlow_RedV2_1", "decals/blood1")
local bodyFlowRedAlt = CreateBodyFlowMaterial("WoundSystem_BodyFlow_RedV2_2", bodyFlowRedAltTexture)
if bodyFlowYellowAlt:IsError() then bodyFlowYellowAlt = bodyFlowYellow end
if bodyFlowRedAlt:IsError() then bodyFlowRedAlt = bodyFlowRed end

local stains = {}
local vomitDrops = {}
local vomitEmitters = {}
local bodyFlows = {}
local playerBloodRagdollCache = {}
local dripSounds = {
    "drip/drip2.ogg",
    "drip/drip3.ogg",
    "drip/drip4.ogg",
    "drip/drip7.ogg",
    "drip/drip11.ogg",
    "drip/drip15.ogg",
    "drip/drip16.ogg",
    "drip/drip17.ogg",
    "drip/drip18.ogg",
    "drip/drip20.ogg",
    "drip/drip21.ogg",
    "drip/drip24.ogg"
}
local dropTrace = {
    mask = MASK_SOLID_BRUSHONLY
}
local dropGravity = Vector(0, 0, -650)
local defaultDropNormal = Vector(1, 0, 0)
local defaultUpNormal = Vector(0, 0, 1)
local drawColor = Color(255, 255, 255, 255)

local PALE_YELLOW = Color(255, 236, 58, 235)
local DEEP_YELLOW = Color(205, 170, 28, 230)
local BLOOD_RED = Color(145, 0, 0, 230)
local BLOOD_RED_DARK = Color(90, 0, 0, 230)

local BODY_FLOW_ROUTES = {
    head = {"ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Neck1", "ValveBiped.Bip01_Spine2"},
    thorax = {"ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Pelvis"},
    abdomen = {"ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Pelvis"},
    arm_L = {"ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_Hand"},
    forearm_L = {"ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_Hand"},
    hand_L = {"ValveBiped.Bip01_L_Hand"},
    arm_R = {"ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Hand"},
    forearm_R = {"ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Hand"},
    hand_R = {"ValveBiped.Bip01_R_Hand"},
    thigh_L = {"ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_L_Foot"},
    crus_L = {"ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_L_Foot"},
    foot_L = {"ValveBiped.Bip01_L_Foot"},
    thigh_R = {"ValveBiped.Bip01_R_Thigh", "ValveBiped.Bip01_R_Calf", "ValveBiped.Bip01_R_Foot"},
    crus_R = {"ValveBiped.Bip01_R_Calf", "ValveBiped.Bip01_R_Foot"},
    foot_R = {"ValveBiped.Bip01_R_Foot"}
}

local function LowEndMode()
    return WoundSystem.Client
        and WoundSystem.Client.IsLowEndMode
        and WoundSystem.Client.IsLowEndMode()
end

local function WoundSystemClientEnabled()
    local client = WoundSystem and WoundSystem.Client
    if client and client.IsEnabled then
        return client.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

local function Enabled()
    return WoundSystemClientEnabled() and cvEnabled:GetBool() and not LowEndMode()
end

local function GetBloodRGB()
    local r = math.Clamp(cvBloodR:GetInt(), 0, 255)
    local g = math.Clamp(cvBloodG:GetInt(), 0, 255)
    local b = math.Clamp(cvBloodB:GetInt(), 0, 255)
    return r, g, b
end

local function IsAlienBlood()
    local mode = string.lower(string.Trim(cvColorMode:GetString() or "alien_yellow"))
    if mode == "red" then return false end
    if mode == "alien_yellow" then return true end
    local r, g, b = GetBloodRGB()
    return not (r > 130 and g < 60 and b < 60)
end

local function BloodColor(alphaScale)
    local alpha = math.Clamp(alphaScale or 1, 0, 1)
    local r, g, b = GetBloodRGB()
    return Color(r, g, b, math.floor(235 * alpha))
end

local function BloodColorDark(alphaScale)
    local alpha = math.Clamp(alphaScale or 1, 0, 1)
    local r, g, b = GetBloodRGB()
    return Color(math.floor(r * 0.7), math.floor(g * 0.7), math.floor(b * 0.7), math.floor(230 * alpha))
end

local function BloodMaterial()
    if IsAlienBlood() then
        return math.random(1, 2) == 1 and matYellow or matYellowAlt
    end

    return math.random(1, 2) == 1 and matRed or matRedAlt
end

local function BodyFlowMaterial()
    if IsAlienBlood() then
        return math.random(1, 2) == 1 and bodyFlowYellow or bodyFlowYellowAlt
    end

    return math.random(1, 2) == 1 and bodyFlowRed or bodyFlowRedAlt
end

local function TrimStains()
    local maxStains = math.Clamp(cvMaxStains:GetInt(), 0, 250)
    while #stains > maxStains do
        table.remove(stains, 1)
    end
end

local function QualityFactor()
    return math.Clamp(cvQuality:GetInt(), 0, 2)
end

local function BodyFlowMax()
    local manual = cvBodyFlowMax:GetInt()
    if manual > 0 then
        return math.Clamp(manual, 0, 96)
    end

    local quality = QualityFactor()
    if quality <= 0 then return 0 end
    return quality == 1 and 18 or 42
end

local function BodyFlowEnabled()
    return Enabled() and cvTrails:GetBool() and cvBodyFlow:GetBool() and BodyFlowMax() > 0
end

local function VisualVisible(kind, entOrPos, radius)
    if WoundSystem and WoundSystem.Client and WoundSystem.Client.IsVisualVisible then
        return WoundSystem.Client.IsVisualVisible(kind, entOrPos, radius)
    end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return false end
    if IsValid(entOrPos) then return true end
    if not isvector(entOrPos) then return false end

    local screen = entOrPos:ToScreen()
    local margin = 256 + (tonumber(radius) or 0)
    return screen.visible and screen.x >= -margin and screen.x <= ScrW() + margin and screen.y >= -margin and screen.y <= ScrH() + margin
end

local function FindPlayerBloodRagdoll(ply, nearPos)
    if not IsValid(ply) or not ply:IsPlayer() then return nil end

    local cached = playerBloodRagdollCache[ply]
    if cached and cached.nextCheck and cached.nextCheck > CurTime() and IsValid(cached.ent) then
        return cached.ent
    end

    local ragdoll = ply:GetNWEntity("WoundSystemUnconsciousRagdoll")
    if not IsValid(ragdoll) then
        ragdoll = ply:GetNWEntity("WoundSystemDeathRagdoll")
    end

    if not IsValid(ragdoll) and ply.GetRagdollEntity then
        local candidate = ply:GetRagdollEntity()
        if IsValid(candidate)
            and (candidate:GetNWBool("WoundSystemUnconsciousRagdoll", false)
                or candidate:GetNWBool("WoundSystemDeathRagdoll", false)
                or candidate:GetNWEntity("WoundSystemOwner") == ply
                or not ply:Alive()
                or ply:GetNoDraw()
                or ply:GetNWBool("WoundSystemUnconscious", false)) then
            ragdoll = candidate
        end
    end

    if not IsValid(ragdoll) and (not ply:Alive() or ply:GetNoDraw() or ply:GetNWBool("WoundSystemUnconscious", false)) then
        local best
        local bestDist = math.huge
        local wantedModel = string.lower(ply:GetModel() or "")
        local origin = nearPos or (ply.WorldSpaceCenter and ply:WorldSpaceCenter() or ply:GetPos())

        for _, className in ipairs({"prop_ragdoll", "hl2mp_ragdoll"}) do
            for _, candidate in ipairs(ents.FindByClass(className)) do
                if IsValid(candidate)
                    and candidate ~= ply
                    and (candidate:GetNWBool("WoundSystemUnconsciousRagdoll", false)
                        or candidate:GetNWBool("WoundSystemDeathRagdoll", false)
                        or candidate:GetNWEntity("WoundSystemOwner") == ply
                        or string.lower(candidate:GetModel() or "") == wantedModel) then
                    local dist = candidate:WorldSpaceCenter():DistToSqr(origin)
                    if dist < bestDist and dist <= (520 * 520) then
                        best = candidate
                        bestDist = dist
                    end
                end
            end
        end

        ragdoll = best
    end

    playerBloodRagdollCache[ply] = {
        ent = IsValid(ragdoll) and ragdoll or NULL,
        nextCheck = CurTime() + 0.15
    }

    return IsValid(ragdoll) and ragdoll or nil
end

local function FlowDrawEntity(flow)
    if not flow or not IsValid(flow.ent) then return nil end

    if flow.ent:IsPlayer() then
        local ragdoll = FindPlayerBloodRagdoll(flow.ent, flow.lastPos)
        if IsValid(ragdoll) then
            flow.ent = ragdoll
            flow.retargetedToRagdoll = true
            flow.waitForRagdollUntil = nil
            flow.localAnchor = ragdoll:WorldToLocal(flow.lastPos or ragdoll:WorldSpaceCenter())
            flow.localNormal = ragdoll:WorldToLocal((flow.lastPos or ragdoll:WorldSpaceCenter()) + (flow.worldNormal or ragdoll:GetForward())) - flow.localAnchor
            return ragdoll
        end

        if not flow.ent:Alive() or flow.ent:GetNoDraw() then
            flow.waitForRagdollUntil = flow.waitForRagdollUntil or (CurTime() + 0.75)
            return nil
        end

        if flow.ent:GetNoDraw() then
            return nil
        end
    end

    return flow.ent
end

local function TrimBodyFlows()
    local maxFlows = BodyFlowMax()
    while #bodyFlows > maxFlows do
        table.remove(bodyFlows, 1)
    end
end

local function DecalSizeFor(kind, severity)
    severity = math.Clamp(tonumber(severity) or 1, 0.05, 3)

    if kind == "pool" then
        return math.Rand(30, 48) + (severity ^ 0.75) * math.Rand(18, 34), 150
    elseif kind == "trail" then
        return math.Rand(7, 12) + severity * math.Rand(6, 10), 54
    elseif kind == "drop" then
        return math.Rand(5, 10) + severity * math.Rand(8, 14), 42
    elseif kind == "impact" or kind == "stain" then
        return math.Rand(9, 18) + severity * math.Rand(6, 12), 80
    elseif kind == "dismember" then
        return math.Rand(28, 45) + severity * math.Rand(15, 28), 140
    end

    return math.Rand(8, 16) + severity * 6, 64
end

local function FindMergeablePool(pos, normal, radius)
    local best
    local bestDist = math.huge
    radius = radius or 48

    for _, stain in ipairs(stains) do
        if not stain.ent and stain.pool and stain.pos and stain.normal then
            local distSqr = stain.pos:DistToSqr(pos)
            if distSqr < radius * radius and stain.normal:Dot(normal) > 0.72 and distSqr < bestDist then
                best = stain
                bestDist = distSqr
            end
        end
    end

    return best
end

local function IsWorldBloodHit(tr)
    return tr and tr.Hit and tr.HitWorld and not tr.HitSky
end

local function BonePos(ent, boneName)
    if not IsValid(ent) or not ent.LookupBone or not ent.GetBonePosition then return nil end

    local boneId = ent:LookupBone(boneName)
    if not boneId then return nil end

    local pos = ent:GetBonePosition(boneId)
    return pos
end

local function BuildBodyRoute(ent, limbId)
    local route = BODY_FLOW_ROUTES[limbId or ""] or BODY_FLOW_ROUTES.thorax
    local points = {}

    for _, boneName in ipairs(route) do
        local pos = BonePos(ent, boneName)
        if pos and (#points == 0 or points[#points]:DistToSqr(pos) > 1) then
            points[#points + 1] = pos
        end
    end

    if #points == 0 and IsValid(ent) then
        points[1] = ent.WorldSpaceCenter and ent:WorldSpaceCenter() or ent:GetPos()
    end

    if #points == 1 and IsValid(ent) then
        points[2] = points[1] - ent:GetUp() * 16
    end

    return points
end

local function RouteLength(points)
    local total = 0
    for i = 1, #points - 1 do
        total = total + points[i]:Distance(points[i + 1])
    end
    return total
end

local function PointOnRoute(points, frac)
    if #points <= 0 then return nil, Vector(0, 0, -1) end
    if #points == 1 then return points[1], Vector(0, 0, -1) end

    local total = RouteLength(points)
    if total <= 0.001 then return points[1], Vector(0, 0, -1) end

    local target = math.Clamp(frac or 0, 0, 1) * total
    local travelled = 0

    for i = 1, #points - 1 do
        local a = points[i]
        local b = points[i + 1]
        local seg = a:Distance(b)
        if seg > 0.001 then
            if travelled + seg >= target then
                local t = (target - travelled) / seg
                return a + (b - a) * t, (b - a):GetNormalized()
            end
            travelled = travelled + seg
        end
    end

    return points[#points], (points[#points] - points[#points - 1]):GetNormalized()
end

local function NearestRouteFrac(points, pos)
    if #points < 2 or not pos then return 0 end

    local total = RouteLength(points)
    if total <= 0.001 then return 0 end

    local bestFrac = 0
    local bestDist = math.huge
    local travelled = 0

    for i = 1, #points - 1 do
        local a = points[i]
        local b = points[i + 1]
        local ab = b - a
        local segLenSqr = ab:LengthSqr()
        local segLen = math.sqrt(segLenSqr)

        if segLenSqr > 0.001 then
            local t = math.Clamp((pos - a):Dot(ab) / segLenSqr, 0, 1)
            local closest = a + ab * t
            local dist = closest:DistToSqr(pos)
            if dist < bestDist then
                bestDist = dist
                bestFrac = (travelled + segLen * t) / total
            end
            travelled = travelled + segLen
        end
    end

    return math.Clamp(bestFrac, 0, 1)
end

local function BodyFlowNormal(flow, pos, dir)
    local ent = FlowDrawEntity(flow)
    if IsValid(ent) and flow.localAnchor and flow.localNormal then
        local anchor = ent:LocalToWorld(flow.localAnchor)
        local normal = ent:LocalToWorld(flow.localAnchor + flow.localNormal) - anchor
        if normal:LengthSqr() > 0.001 then
            return normal:GetNormalized()
        end
    end

    if IsValid(ent) then
        local center = ent.WorldSpaceCenter and ent:WorldSpaceCenter() or ent:GetPos()
        local normal = pos - center
        if normal:LengthSqr() > 0.001 then
            return normal:GetNormalized()
        end
    end

    local side = dir:Cross(Vector(0, 0, 1))
    return side:LengthSqr() > 0.001 and side:GetNormalized() or Vector(0, 1, 0)
end

local function ResolveBodyFlow(flow, frac)
    local ent = FlowDrawEntity(flow)
    if not IsValid(ent) then return nil end

    local points = BuildBodyRoute(ent, flow.limbId)
    if flow.retargetedToRagdoll then
        flow.retargetedToRagdoll = false
        local anchorPos = flow.lastPos or points[1]
        local nearestFrac = NearestRouteFrac(points, anchorPos)
        local routePos = PointOnRoute(points, nearestFrac)
        if routePos then
            flow.progress = math.Clamp(nearestFrac, 0, 0.96)
            flow.localAnchor = ent:WorldToLocal(routePos)
            local worldNormal = flow.worldNormal
            if not worldNormal or worldNormal:LengthSqr() <= 0.001 then
                worldNormal = routePos - (ent.WorldSpaceCenter and ent:WorldSpaceCenter() or ent:GetPos())
            end
            worldNormal = worldNormal:LengthSqr() > 0.001 and worldNormal:GetNormalized() or ent:GetForward()
            flow.localNormal = ent:WorldToLocal(routePos + worldNormal) - flow.localAnchor
            flow.lastPos = routePos
            frac = flow.progress
        end
    end

    local pos, dir = PointOnRoute(points, frac or flow.progress)
    if not pos then return nil end

    dir = dir:LengthSqr() > 0.001 and dir:GetNormalized() or Vector(0, 0, -1)
    local normal = BodyFlowNormal(flow, pos, dir)
    local side = dir:Cross(normal)
    if side:LengthSqr() <= 0.001 and IsValid(ent) then
        side = ent:GetRight()
    end
    side = side:LengthSqr() > 0.001 and side:GetNormalized() or Vector(1, 0, 0)

    pos = pos + normal * flow.surfaceLift + side * flow.sideOffset
    return pos, dir, normal
end

local function AddStain(pos, normal, severity, kind)
    if not cvStains:GetBool() then return end

    severity = math.Clamp(tonumber(severity) or 1, 0.05, 3)
    kind = tostring(kind or "stain")
    normal = (normal and normal:LengthSqr() > 0.001) and normal:GetNormalized() or defaultUpNormal

    local size, maxSize = DecalSizeFor(kind, severity)
    local poolLike = kind == "pool" or kind == "drop"
    local mergeRadius = math.Clamp(size * 0.85, 18, 72)
    local pool = poolLike and FindMergeablePool(pos, normal, mergeRadius)

    if pool then
        local currentTarget = pool.targetSize or pool.size or size
        pool.targetSize = math.min(pool.maxSize or maxSize or 130, math.sqrt((currentTarget * currentTarget) + (size * size * 0.42)))
        pool.size = math.min(pool.size or size, pool.targetSize)
        pool.color = math.random(1, 3) == 1 and BloodColorDark(math.Rand(0.9, 1)) or BloodColor(math.Rand(0.85, 1))
        pool.die = math.max(pool.die or 0, CurTime() + math.Rand(100, 180))
        
        local now = CurTime()
        if (WoundSystem.NextDripSound or 0) < now then
            WoundSystem.NextDripSound = now + math.Rand(0.08, 0.2)
            sound.Play(dripSounds[math.random(#dripSounds)], pos, 65, math.random(90, 110), 1)
        end
        return pool
    end

    local now = CurTime()
    if (WoundSystem.NextDripSound or 0) < now then
        WoundSystem.NextDripSound = now + math.Rand(0.08, 0.2)
        sound.Play(dripSounds[math.random(#dripSounds)], pos, 65, math.random(90, 110), 1)
    end

    stains[#stains + 1] = {
        pos = pos + normal * 0.45,
        normal = normal,
        size = poolLike and math.max(size * 0.72, 4) or size,
        targetSize = poolLike and size or nil,
        maxSize = maxSize,
        pool = poolLike,
        rot = math.Rand(0, 360),
        mat = BloodMaterial(),
        color = math.random(1, 2) == 1 and BloodColor(1) or BloodColorDark(1),
        die = CurTime() + math.Rand(poolLike and 105 or 60, poolLike and 180 or 125)
    }

    TrimStains()
end

local function AddBloodDrop(pos, normal, severity, style)
    normal = (normal and normal:LengthSqr() > 0.001) and normal:GetNormalized() or defaultDropNormal
    style = style or "bleed"
    if style ~= "vomit" then
        normal.z = 0
        normal = normal:LengthSqr() > 0.001 and normal:GetNormalized() or defaultDropNormal
    end

    severity = math.Clamp(tonumber(severity) or 1, 0.05, 3)

    local side = VectorRand() * math.Rand(style == "vomit" and 0.5 or 0.15, style == "vomit" and 4 or 2.5)
    side.z = 0
    local startPos = pos + side + Vector(0, 0, style == "bleed" and math.Rand(1, 9) or 0)
    local lateral = normal:Cross(Vector(0, 0, 1))
    lateral = lateral:LengthSqr() > 0.001 and lateral:GetNormalized() or Vector(0, 1, 0)
    local forwardSpeed = style == "vomit" and math.Rand(125, 230) or math.Rand(12, 55) * severity
    local vel = normal * forwardSpeed
        + lateral * math.Rand(style == "vomit" and -18 or -10, style == "vomit" and 18 or 10)
        + Vector(0, 0, style == "vomit" and math.Rand(-95, -35) or math.Rand(-22, 14))
    local impactSeverity = style == "vomit" and math.Clamp(severity * 0.16, 0.08, 0.55) or math.Clamp(severity * math.Rand(0.08, 0.18), 0.05, 0.65)
    local spriteSize = style == "vomit"
        and math.Rand(2.5, 5.5) + impactSeverity * 7
        or math.Rand(1.8, 4.5) + severity * math.Rand(0.8, 2.2)

    vomitDrops[#vomitDrops + 1] = {
        pos = startPos,
        lastPos = startPos,
        vel = vel,
        size = spriteSize,
        mat = BloodMaterial(),
        color = BloodColor(math.Rand(0.7, 1)),
        die = CurTime() + math.Rand(style == "vomit" and 0.45 or 0.8, style == "vomit" and 1.15 or 1.8),
        severity = impactSeverity,
        impactKind = style == "vomit" and "drop" or "drop"
    }
end

local function AddVomitDrop(pos, normal, severity)
    AddBloodDrop(pos, normal, severity, "vomit")
end

local function AddBleedDroplets(pos, normal, severity, countScale)
    if not cvTrails:GetBool() then return end
    local quality = QualityFactor()
    if quality <= 0 then return end

    severity = math.Clamp(tonumber(severity) or 1, 0.05, 3)
    local count = math.Clamp(math.ceil(severity * (quality + 1) * (countScale or 1.2)), 1, quality == 1 and 4 or 8)
    for _ = 1, count do
        AddBloodDrop(pos, normal, severity, "bleed")
    end
end

local function AddImpactBlood(pos, normal, severity, kind)
    severity = math.Clamp(tonumber(severity) or 1, 0.1, 3)
    AddBleedDroplets(pos, normal, severity, kind == "dismember" and 3.2 or 1.6)
end

local function AddBodyFlow(pos, normal, severity, ent, limbId)
    if not BodyFlowEnabled() or not IsValid(ent) then return end

    severity = math.Clamp(tonumber(severity) or 1, 0.1, 3)
    limbId = tostring(limbId or "")

    local retargetedToRagdoll = false
    if ent:IsPlayer() then
        local ragdoll = FindPlayerBloodRagdoll(ent, pos)
        if IsValid(ragdoll) then
            ent = ragdoll
            retargetedToRagdoll = true
        end
    end

    local route = BuildBodyRoute(ent, limbId)
    if #route < 2 then return end

    local startFrac = NearestRouteFrac(route, pos)
    if retargetedToRagdoll then
        local routePos = PointOnRoute(route, startFrac)
        if routePos then
            pos = routePos
        end
    end

    if normal and normal:LengthSqr() > 0.001 then
        normal = normal:GetNormalized()
    else
        normal = pos - (ent.WorldSpaceCenter and ent:WorldSpaceCenter() or ent:GetPos())
        normal = normal:LengthSqr() > 0.001 and normal:GetNormalized() or ent:GetForward()
    end

    local localAnchor = ent:WorldToLocal(pos)
    local localNormal = ent:WorldToLocal(pos + normal) - localAnchor
    local quality = QualityFactor()
    local burstCount = math.Clamp(math.ceil(severity * (quality + 1) * 0.65), 1, quality == 1 and 3 or 6)

    for _ = 1, burstCount do
        local progress = math.Clamp(startFrac + math.Rand(-0.035, 0.025), 0, 0.96)
        bodyFlows[#bodyFlows + 1] = {
            ent = ent,
            limbId = limbId,
            localAnchor = localAnchor,
            localNormal = localNormal,
            worldNormal = normal,
            progress = progress,
            length = math.Rand(0.045, 0.11) + severity * 0.018,
            speed = math.Rand(0.08, 0.18) + severity * math.Rand(0.035, 0.075),
            sideOffset = math.Rand(-2.8, 2.8),
            surfaceLift = math.Rand(0.65, 1.2),
            width = math.Rand(1.4, 2.6) + severity * math.Rand(0.35, 1.1),
            severity = severity,
            mat = BodyFlowMaterial(),
            color = math.random(1, 2) == 1 and BloodColor(1) or BloodColorDark(1),
            die = CurTime() + math.Rand(2.3, 4.6),
            lastPos = pos
        }
    end

    TrimBodyFlows()
end

local function AddVomitBlood(pos, normal, severity, ent)
    if not cvStains:GetBool() then return end

    severity = math.Clamp(tonumber(severity) or 1, 0.1, 3)
    normal = (normal and normal:LengthSqr() > 0.001) and normal:GetNormalized() or Vector(1, 0, 0)

    if IsValid(ent) then
        if ent:IsPlayer() then
            local ragdoll = FindPlayerBloodRagdoll(ent, pos)
            if IsValid(ragdoll) then
                ent = ragdoll
                local headBone = ent.LookupBone and ent:LookupBone("ValveBiped.Bip01_Head1") or nil
                if headBone and ent.GetBonePosition then
                    local headPos, headAng = ent:GetBonePosition(headBone)
                    if headPos and headAng then
                        normal = headAng:Forward()
                        pos = headPos + normal * 7 - headAng:Up() * 2
                    end
                end
            end
        end

        local bone = ent.LookupBone and ent:LookupBone("ValveBiped.Bip01_Head1") or nil
        if bone and ent.GetBonePosition then
            local bonePos, boneAng = ent:GetBonePosition(bone)
            if bonePos and boneAng then
                local localPos, localAng = WorldToLocal(pos, normal:Angle(), bonePos, boneAng)
                vomitEmitters[#vomitEmitters + 1] = {
                    ent = ent,
                    bone = bone,
                    localPos = localPos,
                    localAng = localAng,
                    severity = severity,
                    nextDrop = CurTime(),
                    die = CurTime() + 1
                }
                return
            end
        end

        vomitEmitters[#vomitEmitters + 1] = {
            ent = ent,
            localPos = ent:WorldToLocal(pos),
            localNormal = ent:WorldToLocal(pos + normal) - ent:WorldToLocal(pos),
            severity = severity,
            nextDrop = CurTime(),
            die = CurTime() + 1
        }
        return
    end

    local count = math.Clamp(math.floor(8 * severity * (QualityFactor() + 1)), 8, 34)
    for _ = 1, count do
        AddVomitDrop(pos, normal, severity)
    end
end

local function AddBloodEffect(pos, normal, severity, kind, ent, limbId)
    if not Enabled() then return end
    if (kind == "trail" or kind == "airtrail" or kind == "vomitblood" or kind == "vomit" or kind == "bleeddrop" or kind == "bodyflow") and not cvTrails:GetBool() then return end

    if kind == "vomitblood" or kind == "vomit" then
        AddVomitBlood(pos, normal, severity, ent)
    elseif kind == "bleeddrop" then
        AddBleedDroplets(pos, normal, severity, 1)
    elseif kind == "bodyflow" then
        AddBodyFlow(pos, normal, severity, ent, limbId)
    elseif kind == "airtrail" then
        AddBleedDroplets(pos, normal, severity, 0.7)
    elseif kind == "dismember" or kind == "impact" then
        AddImpactBlood(pos, normal, severity, kind)
    elseif kind == "pool" then
        AddStain(pos, normal, severity, "pool")
    elseif kind == "trail" then
        AddStain(pos, normal, severity, "trail")
    elseif kind == "stain" then
        AddStain(pos, normal, severity, kind)
    end
end

net.Receive("WoundSystem_BloodEffect", function()
    local pos = net.ReadVector()
    local normal = net.ReadNormal()
    local severity = net.ReadFloat()
    local kind = net.ReadString()
    local ent = net.ReadEntity()
    local limbId = net.ReadString()

    AddBloodEffect(pos, normal, severity, kind, ent, limbId)
end)

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

hook.Add("Think", "WoundSystem_BloodEffects_Think", function()
    if not WoundSystemClientEnabled() then
        table.Empty(stains)
        table.Empty(vomitDrops)
        table.Empty(vomitEmitters)
        table.Empty(bodyFlows)
        return
    end

    local now = CurTime()
    local dt = math.min(FrameTime(), 0.05)

    for i = #stains, 1, -1 do
        if stains[i].die <= now or (stains[i].ent and not IsValid(stains[i].ent)) then
            table.remove(stains, i)
        elseif stains[i].targetSize and stains[i].size and stains[i].size < stains[i].targetSize then
            stains[i].size = math.Approach(stains[i].size, stains[i].targetSize, math.max(8, stains[i].targetSize * 2.4) * dt)
        end
    end

    for i = #vomitEmitters, 1, -1 do
        local emitter = vomitEmitters[i]
        if emitter.die <= now or not IsValid(emitter.ent) then
            table.remove(vomitEmitters, i)
        elseif emitter.nextDrop <= now then
            local pos
            local normal

            if emitter.bone and emitter.ent.GetBonePosition then
                local bonePos, boneAng = emitter.ent:GetBonePosition(emitter.bone)
                if bonePos and boneAng then
                    local worldPos, worldAng = LocalToWorld(emitter.localPos, emitter.localAng, bonePos, boneAng)
                    pos = worldPos
                    normal = worldAng:Forward()
                end
            end

            if not pos then
                pos = emitter.ent:LocalToWorld(emitter.localPos)
                normal = emitter.ent:LocalToWorld(emitter.localPos + (emitter.localNormal or Vector(1, 0, 0))) - pos
                normal = normal:LengthSqr() > 0.001 and normal:GetNormalized() or emitter.ent:GetForward()
            end

            local burstCount = math.Clamp(math.ceil(emitter.severity * (QualityFactor() + 1) * 0.5), 1, 5)
            for _ = 1, burstCount do
                AddVomitDrop(pos, normal, emitter.severity)
            end

            emitter.nextDrop = now + math.Rand(0.035, 0.075)
        end
    end

    if not BodyFlowEnabled() then
        table.Empty(bodyFlows)
    else
        for i = #bodyFlows, 1, -1 do
            local flow = bodyFlows[i]
            if flow.die <= now or not IsValid(flow.ent) then
                if flow.lastPos and IsValid(flow.ent) then
                    AddBleedDroplets(flow.lastPos, flow.ent:GetForward(), flow.severity * 0.45, 0.55)
                end
                table.remove(bodyFlows, i)
            else
                if not IsValid(FlowDrawEntity(flow)) then
                    if flow.waitForRagdollUntil and flow.waitForRagdollUntil > now then
                        continue
                    end
                    table.remove(bodyFlows, i)
                    continue
                end

                flow.progress = math.min(1, flow.progress + dt * flow.speed)
                local pos = ResolveBodyFlow(flow, flow.progress)
                if pos then
                    flow.lastPos = pos
                end

                if flow.progress >= 0.995 then
                    if flow.lastPos then
                        local fallNormal = IsValid(flow.ent) and flow.ent:GetForward() or VectorRand()
                        AddBleedDroplets(flow.lastPos, fallNormal, flow.severity * 0.65, 0.8)
                    end
                    table.remove(bodyFlows, i)
                end
            end
        end
    end

    for i = #vomitDrops, 1, -1 do
        local drop = vomitDrops[i]
        if drop.die <= now then
            table.remove(vomitDrops, i)
        else
            drop.lastPos = drop.pos
            if not drop.noGravity then
                drop.vel = drop.vel + dropGravity * dt
            end
            drop.pos = drop.pos + drop.vel * dt

            dropTrace.start = drop.lastPos
            dropTrace.endpos = drop.pos
            local tr = util.TraceLine(dropTrace)

            if IsWorldBloodHit(tr) then
                AddStain(tr.HitPos, tr.HitNormal, drop.severity, drop.impactKind or "drop")
                table.remove(vomitDrops, i)
            end
        end
    end
end)

hook.Add("PostDrawTranslucentRenderables", "WoundSystem_BloodEffects_Draw", function()
    if not Enabled() then return end

    local now = CurTime()

    for _, stain in ipairs(stains) do
        local lifeAlpha = math.Clamp((stain.die - now) / 12, 0, 1)
        drawColor.r = stain.color.r
        drawColor.g = stain.color.g
        drawColor.b = stain.color.b
        drawColor.a = math.floor(stain.color.a * lifeAlpha)
        local pos = stain.pos
        local normal = stain.normal

        if IsValid(stain.ent) then
            pos = stain.ent:LocalToWorld(stain.localPos)
            normal = stain.ent:LocalToWorld(stain.localPos + stain.localNormal) - pos
            normal = normal:LengthSqr() > 0.001 and normal:GetNormalized() or stain.normal
            pos = pos + normal * 0.35
        end

        if not VisualVisible("blood_stain", pos, stain.size or 0) then
            continue
        end

        render.SetMaterial(stain.mat)
        render.DrawQuadEasy(pos, normal, stain.size, stain.size, drawColor, stain.rot)
        render.DrawQuadEasy(pos - normal * 0.05, -normal, stain.size, stain.size, drawColor, -stain.rot)
    end

    if BodyFlowEnabled() then
        local alphaMult = math.Clamp(cvBodyFlowAlpha:GetFloat(), 0, 2)
        for _, flow in ipairs(bodyFlows) do
            local canDraw = not (flow.ent == LocalPlayer() and not flow.ent:ShouldDrawLocalPlayer())
            local headPos, normal
            local tailPos

            if canDraw then
                headPos, _, normal = ResolveBodyFlow(flow, flow.progress)
                tailPos = ResolveBodyFlow(flow, math.max(0, flow.progress - flow.length))
            end

            if headPos and tailPos and normal then
                if not VisualVisible("blood_bodyflow", headPos, (flow.width or 0) * 4) and not VisualVisible("blood_bodyflow", tailPos, (flow.width or 0) * 4) then
                    continue
                end

                local lifeAlpha = math.Clamp((flow.die - now) / 1.2, 0, 1)
                drawColor.r = flow.color.r
                drawColor.g = flow.color.g
                drawColor.b = flow.color.b
                drawColor.a = math.Clamp(math.floor(flow.color.a * lifeAlpha * alphaMult), 0, 255)

                render.SetMaterial(flow.mat)
                render.DrawBeam(tailPos, headPos, flow.width, 0, 1, drawColor)
                render.DrawQuadEasy(headPos + normal * 0.08, normal, flow.width * 1.45, flow.width * 2.2, drawColor, flow.progress * 720)
            end
        end
    end

    for _, drop in ipairs(vomitDrops) do
        if not VisualVisible("blood_drop", drop.pos, drop.size or 0) then
            continue
        end

        local lifeAlpha = math.Clamp((drop.die - now) / 0.35, 0, 1)
        drawColor.r = drop.color.r
        drawColor.g = drop.color.g
        drawColor.b = drop.color.b
        drawColor.a = math.floor(drop.color.a * lifeAlpha)
        render.SetMaterial(drop.mat)
        render.DrawSprite(drop.pos, drop.size, drop.size, drawColor)
    end
end)

concommand.Add("woundsys_blood_clear", function()
    table.Empty(stains)
    table.Empty(vomitDrops)
    table.Empty(vomitEmitters)
    table.Empty(bodyFlows)
    print("[WoundSystem] Cleared local decorative blood effects.")
end)

WoundSystem.BloodEffects.Add = AddBloodEffect
