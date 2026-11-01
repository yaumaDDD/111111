WoundSystem = WoundSystem or {}
WoundSystem.MultiplayerFeedback = WoundSystem.MultiplayerFeedback or {}

local Feedback = WoundSystem.MultiplayerFeedback

local function WoundSystemClientEnabled()
    local client = WoundSystem and WoundSystem.Client
    if client and client.IsEnabled then
        return client.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

Feedback.damageSeq = Feedback.damageSeq or 0
Feedback.ragdollSeq = Feedback.ragdollSeq or 0
Feedback.ragdollPendingUntil = Feedback.ragdollPendingUntil or 0
Feedback.transientPain = Feedback.transientPain or 0
Feedback.transientShock = Feedback.transientShock or 0
Feedback.transientBleed = Feedback.transientBleed or 0
Feedback.lastDamageAt = Feedback.lastDamageAt or 0
Feedback.aimKick = Feedback.aimKick or nil

local function ReadOptionalUInt(bits, fallback)
    if not net.BytesLeft then return fallback end

    local bytesLeft, bitsLeft = net.BytesLeft()
    if (bitsLeft or 0) >= bits or (bytesLeft or 0) * 8 >= bits then
        return net.ReadUInt(bits)
    end

    return fallback
end

local function Smooth(current, target, riseSpeed, fallSpeed)
    local speed = target > current and riseSpeed or fallSpeed
    local dt = RealFrameTime and RealFrameTime() or FrameTime()
    return Lerp(1 - math.exp(-math.max(dt, 0) * speed), current, target)
end

function Feedback.GetPainBoost()
    local now = CurTime()
    local age = now - (Feedback.lastDamageAt or 0)
    local decay = math.Clamp(1 - (age / 1.35), 0, 1)
    return math.max(Feedback.transientPain or 0, 0) * decay
end

function Feedback.GetRagdollPending()
    return CurTime() < (Feedback.ragdollPendingUntil or 0)
end

hook.Add("Think", "WoundSystem_MultiplayerFeedbackDecay", function()
    if not WoundSystemClientEnabled() then
        Feedback.transientPain = 0
        Feedback.transientShock = 0
        Feedback.transientBleed = 0
        Feedback.aimKick = nil
        return
    end

    Feedback.transientPain = Smooth(Feedback.transientPain or 0, 0, 20, 2.4)
    Feedback.transientShock = Smooth(Feedback.transientShock or 0, 0, 20, 2.0)
    Feedback.transientBleed = Smooth(Feedback.transientBleed or 0, 0, 20, 2.0)
end)

net.Receive("WoundSystem_DamageFeedback", function()
    if not WoundSystemClientEnabled() then return end

    local seq = net.ReadUInt(24)
    local limbId = net.ReadString()
    local damageKind = net.ReadUInt(8)
    local painSeverity = net.ReadFloat()
    local bleedSeverity = net.ReadFloat()
    local shockSeverity = net.ReadFloat()
    local willRagdoll = net.ReadBool()

    if seq <= (Feedback.damageSeq or 0) then return end

    Feedback.damageSeq = seq
    Feedback.lastDamageAt = CurTime()
    Feedback.lastLimbId = limbId
    Feedback.lastDamageKind = damageKind
    Feedback.transientPain = math.max(Feedback.transientPain or 0, math.Clamp(painSeverity, 0, 1) * 100)
    Feedback.transientShock = math.max(Feedback.transientShock or 0, math.Clamp(shockSeverity, 0, 1))
    Feedback.transientBleed = math.max(Feedback.transientBleed or 0, math.Clamp(bleedSeverity, 0, 1))

    if willRagdoll then
        Feedback.ragdollPendingUntil = CurTime() + 1.5
    end

    local ply = LocalPlayer()
    local ragdollActive = WoundSystem and WoundSystem.IsRagdollCameraActiveClient and WoundSystem.IsRagdollCameraActiveClient(ply)
    if IsValid(ply) and ply.ViewPunch and not ragdollActive then
        local kick = math.Clamp((painSeverity * 2.5) + (shockSeverity * 3.5), 0.4, 6)
        ply:ViewPunch(Angle(-kick, math.Rand(-kick * 0.35, kick * 0.35), 0))
    end
end)

net.Receive("WoundSystem_BallisticStagger", function()
    if not WoundSystemClientEnabled() then return end

    local tier = math.Clamp(net.ReadUInt(3) or 1, 1, 3)
    local severity = math.Clamp(net.ReadFloat() or 0, 0, 1)

    local ply = LocalPlayer()
    local ragdollActive = WoundSystem and WoundSystem.IsRagdollCameraActiveClient and WoundSystem.IsRagdollCameraActiveClient(ply)
    if not IsValid(ply) or ragdollActive then return end

    local base = tier == 1 and 1.0 or tier == 2 and 2.2 or 4.1
    local kick = base * Lerp(severity, 0.75, 1.35)
    local pitch = math.Rand(-kick, kick)
    local yaw = math.Rand(-kick * 0.8, kick * 0.8)

    if math.abs(pitch) < kick * 0.25 then
        pitch = (pitch < 0 and -1 or 1) * kick * 0.25
    end
    if math.abs(yaw) < kick * 0.2 then
        yaw = (yaw < 0 and -1 or 1) * kick * 0.2
    end

    Feedback.aimKick = {
        pitch = pitch,
        yaw = yaw,
        roll = math.Rand(-kick * 0.25, kick * 0.25),
        start = CurTime(),
        duration = tier == 1 and 0.12 or tier == 2 and 0.18 or 0.24,
        appliedPitch = 0,
        appliedYaw = 0,
        appliedRoll = 0
    }

    if ply.ViewPunch then
        ply:ViewPunch(Angle(pitch * 0.35, yaw * 0.25, 0))
    end
end)

hook.Add("CreateMove", "WoundSystem_BallisticAimKick", function(cmd)
    if not WoundSystemClientEnabled() then
        Feedback.aimKick = nil
        return
    end

    local kick = Feedback.aimKick
    if not kick then return end

    local now = CurTime()
    local duration = math.max(kick.duration or 0.15, 0.01)
    local frac = math.Clamp((now - (kick.start or now)) / duration, 0, 1)
    local eased = 1 - ((1 - frac) * (1 - frac))

    local targetPitch = (kick.pitch or 0) * eased
    local targetYaw = (kick.yaw or 0) * eased
    local targetRoll = (kick.roll or 0) * eased
    local deltaPitch = targetPitch - (kick.appliedPitch or 0)
    local deltaYaw = targetYaw - (kick.appliedYaw or 0)
    local deltaRoll = targetRoll - (kick.appliedRoll or 0)

    if math.abs(deltaPitch) > 0.0001 or math.abs(deltaYaw) > 0.0001 or math.abs(deltaRoll) > 0.0001 then
        local ang = cmd:GetViewAngles()
        ang.p = math.Clamp(ang.p + deltaPitch, -89, 89)
        ang.y = ang.y + deltaYaw
        ang.r = ang.r + deltaRoll
        cmd:SetViewAngles(ang)
    end

    kick.appliedPitch = targetPitch
    kick.appliedYaw = targetYaw
    kick.appliedRoll = targetRoll

    if frac >= 1 then
        Feedback.aimKick = nil
    end
end)

net.Receive("WoundSystem_RagdollState", function()
    local seq = net.ReadUInt(24)
    local active = net.ReadBool()
    local ragdoll = net.ReadEntity()
    local lifecycleSeq = ReadOptionalUInt(24, nil)

    if not WoundSystemClientEnabled() then
        Feedback.ragdollActive = false
        Feedback.ragdollEntity = NULL
        Feedback.ragdollPendingUntil = 0
        if WoundSystem and WoundSystem.ReceiveRagdollState then
            WoundSystem.ReceiveRagdollState(seq, false, NULL)
        end
        return
    end

    if seq < (Feedback.ragdollSeq or 0) then return end
    if WoundSystem and WoundSystem.HealthGUI and WoundSystem.HealthGUI.ShouldIgnoreLifecycleMessage
        and WoundSystem.HealthGUI.ShouldIgnoreLifecycleMessage(lifecycleSeq, active) then
        return
    end

    Feedback.ragdollSeq = seq
    Feedback.ragdollActive = active
    Feedback.ragdollEntity = IsValid(ragdoll) and ragdoll or NULL
    Feedback.ragdollPendingUntil = active and (CurTime() + 1.5) or 0

    if WoundSystem and WoundSystem.ReceiveRagdollState then
        WoundSystem.ReceiveRagdollState(seq, active, Feedback.ragdollEntity)
    end
end)

function WoundSystem.MinigameNextInputSeq(mg)
    if not mg then return 0 end

    mg.inputSeq = ((mg.inputSeq or 0) + 1) % 16777216
    if mg.inputSeq <= 0 then mg.inputSeq = 1 end
    return mg.inputSeq
end

function WoundSystem.MinigameReadAck(defaultValue)
    return ReadOptionalUInt(24, defaultValue or 0)
end

function WoundSystem.MinigameAck(mg, ackSeq)
    if not mg or not ackSeq then return end
    mg.ackSeq = math.max(mg.ackSeq or 0, ackSeq or 0)
end

local ACK_TARGETS = {
    [1] = function() return WoundSystemBandageMinigame end,
    [2] = function() return WoundSystemSyringeMinigame end,
    [3] = function() return WoundSystemAEDMinigame end
}

net.Receive("WoundSystem_MinigameAck", function()
    local gameId = net.ReadUInt(3)
    local sessionId = net.ReadUInt(24)
    local ackSeq = net.ReadUInt(24)
    local resolver = ACK_TARGETS[gameId]
    local mg = resolver and resolver()

    if not mg or not mg.active or mg.sessionId ~= sessionId then return end
    WoundSystem.MinigameAck(mg, ackSeq)
end)
