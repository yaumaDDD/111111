WoundSystem = WoundSystem or {}
WoundSystem.Health = WoundSystem.Health or {}
WoundSystem.Health.WakePositions = WoundSystem.Health.WakePositions or {}

local WakePositions = WoundSystem.Health.WakePositions

local WAKE_SEARCH_RADII = { 0, 18, 32, 48, 72, 96, 128, 160, 208, 256 }
local WAKE_SEARCH_DIRECTIONS = {
    Vector(1, 0, 0),
    Vector(-1, 0, 0),
    Vector(0, 1, 0),
    Vector(0, -1, 0),
    Vector(0.707, 0.707, 0),
    Vector(-0.707, 0.707, 0),
    Vector(0.707, -0.707, 0),
    Vector(-0.707, -0.707, 0),
    Vector(0.924, 0.383, 0),
    Vector(-0.924, 0.383, 0),
    Vector(0.924, -0.383, 0),
    Vector(-0.924, -0.383, 0),
    Vector(0.383, 0.924, 0),
    Vector(-0.383, 0.924, 0),
    Vector(0.383, -0.924, 0),
    Vector(-0.383, -0.924, 0)
}

local WAKE_GROUND_TRACE_UP = 192
local WAKE_GROUND_TRACE_DOWN = 384
local WAKE_HULL_FLOOR_CLEARANCE = 0
local WAKE_VERTICAL_CLEAR_STEPS = { 0, 4, 8, 12, 16, 24, 32, 48, 64 }
local cvWakePerfDebug = CreateConVar("woundsys_wake_perf_debug", "0", FCVAR_ARCHIVE, "Print slow WoundSystem wake-position solves.", 0, 1)
local cvWakePerfThresholdMs = CreateConVar("woundsys_wake_perf_threshold_ms", "4", FCVAR_ARCHIVE, "Milliseconds before wake-position debug prints.", 0, 100)

function WakePositions.GetRagdollHeadPos(ragdoll)
    if not IsValid(ragdoll) then return nil end

    local headBone = ragdoll:LookupBone("ValveBiped.Bip01_Head1")
    if headBone then
        local headPos = ragdoll:GetBonePosition(headBone)
        if headPos then return headPos end
    end

    local eyeAttachment = ragdoll:LookupAttachment("eyes")
    if eyeAttachment and eyeAttachment > 0 then
        local attachData = ragdoll:GetAttachment(eyeAttachment)
        if attachData and attachData.Pos then
            return attachData.Pos
        end
    end

    return ragdoll:GetPos() + Vector(0, 0, 8)
end

function WakePositions.GetRagdollPelvisPos(ragdoll)
    if not IsValid(ragdoll) then return nil end

    if ragdoll.SetupBones then
        ragdoll:SetupBones()
    end

    for _, boneName in ipairs({"ValveBiped.Bip01_Pelvis", "Bip01 Pelvis", "ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1"}) do
        local bone = ragdoll:LookupBone(boneName)
        if bone then
            local pos = ragdoll:GetBonePosition(bone)
            if pos then return pos end
        end
    end

    local phys = ragdoll.GetPhysicsObjectNum and ragdoll:GetPhysicsObjectNum(0)
    if IsValid(phys) then
        return phys:GetPos()
    end

    return ragdoll.WorldSpaceCenter and ragdoll:WorldSpaceCenter() or ragdoll:GetPos()
end

function WakePositions.GetRandomWakeEyeAngles()
    return Angle(math.Rand(-8, 6), math.Rand(-180, 180), 0)
end

local function GetPlayerWakeHull(ply)
    if IsValid(ply) and ply.GetHull then
        local mins, maxs = ply:GetHull()
        if mins and maxs then
            mins = Vector(mins.x, mins.y, mins.z)
            maxs = Vector(maxs.x, maxs.y, maxs.z)

            if ply.GetHullDuck then
                local duckMins, duckMaxs = ply:GetHullDuck()
                if duckMins and duckMaxs then
                    mins.x = math.min(mins.x, duckMins.x)
                    mins.y = math.min(mins.y, duckMins.y)
                    mins.z = math.min(mins.z, duckMins.z)
                    maxs.x = math.max(maxs.x, duckMaxs.x)
                    maxs.y = math.max(maxs.y, duckMaxs.y)
                    maxs.z = math.max(maxs.z, duckMaxs.z)
                end
            end

            return mins, maxs
        end
    end

    return Vector(-16, -16, 0), Vector(16, 16, 72)
end

local function CreateWakeTraceFilter(ply, ragdoll)
    return function(ent)
        if ent == ply or ent == ragdoll then return false end
        if IsValid(ent) and ent.WoundSystemOwner == ply and (ent.WoundSystemUnconsciousRagdoll or ent.WoundSystemDeadUnconsciousBody) then
            return false
        end
        if IsValid(ent) and ent.WoundSystemRecoverableDrop and ent.WoundSystemDroppedBy == ply then
            return false
        end

        return true
    end
end

local function IsWakeHullClear(pos, mins, maxs, filter)
    local tr = util.TraceHull({
        start = pos,
        endpos = pos,
        mins = mins,
        maxs = maxs,
        filter = filter,
        mask = MASK_PLAYERSOLID,
        collisiongroup = COLLISION_GROUP_PLAYER
    })

    return not tr.StartSolid and not tr.AllSolid and not tr.Hit
end

local function TraceWakeGroundAt(pos, filter)
    local tr = util.TraceLine({
        start = pos + Vector(0, 0, WAKE_GROUND_TRACE_UP),
        endpos = pos - Vector(0, 0, WAKE_GROUND_TRACE_DOWN),
        filter = filter,
        mask = MASK_PLAYERSOLID,
        collisiongroup = COLLISION_GROUP_PLAYER
    })

    if tr.StartSolid or tr.AllSolid or not tr.Hit then return nil end
    if tr.HitNormal and tr.HitNormal.z < 0.55 then return nil end
    if tr.HitSky then return nil end

    return tr
end

local function BuildWakeFootprintOffsets(mins, maxs)
    local minX = mins.x or -16
    local maxX = maxs.x or 16
    local minY = mins.y or -16
    local maxY = maxs.y or 16
    local midX = (minX + maxX) * 0.5
    local midY = (minY + maxY) * 0.5
    local edgeInset = 2

    minX = minX + edgeInset
    maxX = maxX - edgeInset
    minY = minY + edgeInset
    maxY = maxY - edgeInset

    return {
        Vector(0, 0, 0),
        Vector(minX, minY, 0),
        Vector(minX, maxY, 0),
        Vector(maxX, minY, 0),
        Vector(maxX, maxY, 0),
        Vector(midX, minY, 0),
        Vector(midX, maxY, 0),
        Vector(minX, midY, 0),
        Vector(maxX, midY, 0)
    }
end

local function FindWakeFootprintGround(candidate, filter, offsets)
    local highestHit
    local centerHit

    for index, offset in ipairs(offsets) do
        local tr = TraceWakeGroundAt(candidate + offset, filter)
        if tr then
            if index == 1 then
                centerHit = tr
            end

            if not highestHit or tr.HitPos.z > highestHit.HitPos.z then
                highestHit = tr
            end
        end
    end

    return highestHit, centerHit
end

local function WakeVerticalAllowed(pos, anchor, maxVerticalDistance)
    if not pos or not anchor then return true end
    maxVerticalDistance = tonumber(maxVerticalDistance) or 0
    if maxVerticalDistance <= 0 then return true end

    return math.abs((pos.z or 0) - (anchor.z or 0)) <= maxVerticalDistance
end

local function TryFindWakeGround(candidate, mins, maxs, filter, anchor, maxVerticalDistance, offsets)
    local highestHit, centerHit = FindWakeFootprintGround(candidate, filter, offsets)
    if not highestHit then return nil end

    local originLift = math.max(WAKE_HULL_FLOOR_CLEARANCE, -(mins.z or 0) + WAKE_HULL_FLOOR_CLEARANCE)
    local basePos = Vector(candidate.x, candidate.y, highestHit.HitPos.z + originLift)

    for _, stepUp in ipairs(WAKE_VERTICAL_CLEAR_STEPS) do
        local pos = basePos + Vector(0, 0, stepUp)
        if WakeVerticalAllowed(pos, anchor, maxVerticalDistance) and IsWakeHullClear(pos, mins, maxs, filter) then
            return pos
        end
    end

    if centerHit and centerHit ~= highestHit then
        basePos = Vector(candidate.x, candidate.y, centerHit.HitPos.z + originLift)
        for _, stepUp in ipairs(WAKE_VERTICAL_CLEAR_STEPS) do
            local pos = basePos + Vector(0, 0, stepUp)
            if WakeVerticalAllowed(pos, anchor, maxVerticalDistance) and IsWakeHullClear(pos, mins, maxs, filter) then
                return pos
            end
        end
    end

    return nil
end

local function AddWakeBase(bases, pos)
    if not pos then return end

    for _, existing in ipairs(bases) do
        if existing:DistToSqr(pos) < 16 then return end
    end

    bases[#bases + 1] = pos
end

local function WakeDistance2DSqr(a, b)
    if not a or not b then return math.huge end

    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    return dx * dx + dy * dy
end

local function WakeCandidateAllowed(pos, anchor, maxDistance, maxVerticalDistance)
    if not pos then return false end
    maxDistance = tonumber(maxDistance) or 0
    if not anchor then return true end

    if maxDistance > 0 and WakeDistance2DSqr(pos, anchor) > maxDistance * maxDistance then
        return false
    end

    if not WakeVerticalAllowed(pos, anchor, maxVerticalDistance) then
        return false
    end

    return true
end

local function ConsiderWakeCandidate(best, pos, anchor, maxDistance, maxVerticalDistance)
    if not WakeCandidateAllowed(pos, anchor, maxDistance, maxVerticalDistance) then return best end

    local distSqr = WakeDistance2DSqr(pos, anchor)
    if not best or distSqr < best.distSqr then
        return {
            pos = pos,
            distSqr = distSqr
        }
    end

    return best
end

local function AddRagdollWakeBases(bases, ragdoll)
    if not IsValid(ragdoll) then return end

    AddWakeBase(bases, ragdoll:GetPos())

    if ragdoll.WorldSpaceCenter then
        AddWakeBase(bases, ragdoll:WorldSpaceCenter())
    end

    if ragdoll.GetPhysicsObjectNum then
        local phys = ragdoll:GetPhysicsObjectNum(0)
        if IsValid(phys) then
            AddWakeBase(bases, phys:GetPos())
        end
    end
end

function WakePositions.IsPlayerWakePosClear(ply, ragdoll, pos)
    if not pos then return false end

    local mins, maxs = GetPlayerWakeHull(ply)
    local filter = CreateWakeTraceFilter(ply, ragdoll)
    return IsWakeHullClear(pos, mins, maxs, filter)
end

function WakePositions.FindSafePlayerWakePos(ply, ragdoll, desiredPos, options)
    if not desiredPos then return nil end

    options = istable(options) and options or {}
    local debugPerf = cvWakePerfDebug:GetBool()
    local started = debugPerf and SysTime() or 0
    local testedCandidates = 0

    local mins, maxs = GetPlayerWakeHull(ply)
    local filter = CreateWakeTraceFilter(ply, ragdoll)
    local footprintOffsets = BuildWakeFootprintOffsets(mins, maxs)
    local bases = {}
    local anchor = options.anchorPos or desiredPos
    local maxDistance = tonumber(options.maxDistance) or 0
    local maxVerticalDistance = tonumber(options.maxVerticalDistance) or (maxDistance > 0 and 96 or 0)
    local preferClosest = options.preferClosest ~= false and (options.preferClosest == true or maxDistance > 0)

    AddWakeBase(bases, desiredPos)
    if IsValid(ragdoll) then
        AddRagdollWakeBases(bases, ragdoll)
    end

    if options.includePlayerBase ~= false and IsValid(ply) then
        AddWakeBase(bases, ply:GetPos())
        if ply.WorldSpaceCenter then
            AddWakeBase(bases, ply:WorldSpaceCenter())
        end
    end

    local best
    local function Finish(pos)
        if debugPerf then
            local elapsedMs = (SysTime() - started) * 1000
            if elapsedMs >= cvWakePerfThresholdMs:GetFloat() then
                print(string.format(
                    "[WoundSystem wake perf] ply=%s ms=%.2f candidates=%d bases=%d found=%s ragdoll=%s",
                    IsValid(ply) and ply:Nick() or "NULL",
                    elapsedMs,
                    testedCandidates,
                    #bases,
                    tostring(pos ~= nil),
                    IsValid(ragdoll) and tostring(ragdoll:EntIndex()) or "NULL"
                ))
            end
        end

        return pos
    end

    for _, base in ipairs(bases) do
        for _, radius in ipairs(WAKE_SEARCH_RADII) do
            if radius == 0 then
                if WakeCandidateAllowed(base, anchor, maxDistance, maxVerticalDistance) then
                    testedCandidates = testedCandidates + 1
                    local pos = TryFindWakeGround(base, mins, maxs, filter, anchor, maxVerticalDistance, footprintOffsets)
                    if pos then
                        if preferClosest then
                            best = ConsiderWakeCandidate(best, pos, anchor, maxDistance, maxVerticalDistance)
                        elseif WakeCandidateAllowed(pos, anchor, maxDistance, maxVerticalDistance) then
                            return Finish(pos)
                        end
                    end
                end
            else
                for _, dir in ipairs(WAKE_SEARCH_DIRECTIONS) do
                    local candidate = base + dir * radius
                    if not WakeCandidateAllowed(candidate, anchor, maxDistance, maxVerticalDistance) then
                        continue
                    end

                    testedCandidates = testedCandidates + 1
                    local pos = TryFindWakeGround(candidate, mins, maxs, filter, anchor, maxVerticalDistance, footprintOffsets)
                    if pos then
                        if preferClosest then
                            best = ConsiderWakeCandidate(best, pos, anchor, maxDistance, maxVerticalDistance)
                        elseif WakeCandidateAllowed(pos, anchor, maxDistance, maxVerticalDistance) then
                            return Finish(pos)
                        end
                    end
                end
            end
        end
    end

    return Finish(best and best.pos or nil)
end

WoundSystem.Health.GetRagdollHeadPos = WakePositions.GetRagdollHeadPos
WoundSystem.Health.GetRagdollPelvisPos = WakePositions.GetRagdollPelvisPos
WoundSystem.Health.GetRandomWakeEyeAngles = WakePositions.GetRandomWakeEyeAngles
WoundSystem.Health.FindSafePlayerWakePos = WakePositions.FindSafePlayerWakePos
WoundSystem.Health.IsPlayerWakePosClear = WakePositions.IsPlayerWakePosClear
