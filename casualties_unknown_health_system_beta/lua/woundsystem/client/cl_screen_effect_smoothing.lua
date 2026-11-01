WoundSystem = WoundSystem or {}
WoundSystemScreenFX = WoundSystemScreenFX or {}

WoundSystemScreenFX._OriginalUpdateDrawChannels = nil
WoundSystemScreenFX._TailSmoothingWrappedFunction = nil

local function SmoothTail(field, target, riseSpeed, fallSpeed)
    local current = WoundSystemScreenFX[field] or target or 0
    local nextValue = WoundSystemScreenFX.Smooth(current, target or 0, riseSpeed, fallSpeed)

    if math.abs(nextValue) <= 0.0000001 then
        nextValue = 0
    end

    WoundSystemScreenFX[field] = nextValue
    return nextValue
end

function WoundSystemScreenFX.UpdateDrawChannels(painPulse, painDistortion, lowOxygen, bloodLoss, consciousnessBlur, opiateVisual, withdrawalVisual)
    local frameNumber = FrameNumber and FrameNumber() or -1
    if frameNumber == WoundSystemScreenFX._TailSmoothingFrame then
        return WoundSystemScreenFX._TailPainPulse or 0,
            WoundSystemScreenFX._TailPainDistortion or 0,
            WoundSystemScreenFX._TailLowOxygen or 0,
            WoundSystemScreenFX._TailBloodLoss or 0,
            WoundSystemScreenFX._TailConsciousnessBlur or 0,
            WoundSystemScreenFX._TailOpiateVisual or 0,
            WoundSystemScreenFX._TailWithdrawalVisual or 0,
            WoundSystemScreenFX._TailPixelStatic or 0
    end

    WoundSystemScreenFX._TailSmoothingFrame = frameNumber
    WoundSystemScreenFX.lastDrawChannelFrame = frameNumber

    WoundSystemScreenFX.drawPainPulse = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawPainPulse, painPulse or 0, 5.2, 3.1)
    WoundSystemScreenFX.drawPainDistortion = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawPainDistortion, painDistortion or 0, 3.4, 2.2)
    WoundSystemScreenFX.drawLowOxygen = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawLowOxygen, lowOxygen or 0, 2.0, 1.35)
    WoundSystemScreenFX.drawBloodLoss = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawBloodLoss, bloodLoss or 0, 1.75, 1.15)
    WoundSystemScreenFX.drawConsciousnessBlur = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawConsciousnessBlur, consciousnessBlur or 0, 2.15, 1.45)
    WoundSystemScreenFX.drawOpiateVisual = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawOpiateVisual, opiateVisual or 0, 1.65, 1.05)
    WoundSystemScreenFX.drawWithdrawalVisual = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawWithdrawalVisual, withdrawalVisual or 0, 2.1, 1.2)

    local staticTarget = math.max(math.Clamp(((painPulse or 0) - 0.28) / 0.72, 0, 1), (withdrawalVisual or 0) * 0.55)
    staticTarget = staticTarget * staticTarget * (3 - 2 * staticTarget)
    WoundSystemScreenFX.pixelVignetteSmooth = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.pixelVignetteSmooth, staticTarget, 2.0, 1.35)
    WoundSystemScreenFX.drawPixelStatic = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawPixelStatic, WoundSystemScreenFX.pixelVignetteSmooth, 2.6, 1.7)

    WoundSystemScreenFX._TailPainPulse = SmoothTail("_TailPainPulse", WoundSystemScreenFX.drawPainPulse, 10.0, 1.15)
    WoundSystemScreenFX._TailPainDistortion = SmoothTail("_TailPainDistortion", WoundSystemScreenFX.drawPainDistortion, 8.0, 0.95)
    WoundSystemScreenFX._TailLowOxygen = SmoothTail("_TailLowOxygen", WoundSystemScreenFX.drawLowOxygen, 8.0, 0.55)
    WoundSystemScreenFX._TailBloodLoss = SmoothTail("_TailBloodLoss", WoundSystemScreenFX.drawBloodLoss, 7.0, 0.50)
    WoundSystemScreenFX._TailConsciousnessBlur = SmoothTail("_TailConsciousnessBlur", WoundSystemScreenFX.drawConsciousnessBlur, 8.0, 0.58)
    WoundSystemScreenFX._TailOpiateVisual = SmoothTail("_TailOpiateVisual", WoundSystemScreenFX.drawOpiateVisual, 7.0, 0.24)
    WoundSystemScreenFX._TailWithdrawalVisual = SmoothTail("_TailWithdrawalVisual", WoundSystemScreenFX.drawWithdrawalVisual, 8.0, 0.42)
    WoundSystemScreenFX._TailPixelStatic = SmoothTail("_TailPixelStatic", WoundSystemScreenFX.drawPixelStatic, 9.0, 0.48)

    return WoundSystemScreenFX._TailPainPulse,
        WoundSystemScreenFX._TailPainDistortion,
        WoundSystemScreenFX._TailLowOxygen,
        WoundSystemScreenFX._TailBloodLoss,
        WoundSystemScreenFX._TailConsciousnessBlur,
        WoundSystemScreenFX._TailOpiateVisual,
        WoundSystemScreenFX._TailWithdrawalVisual,
        WoundSystemScreenFX._TailPixelStatic
end

local cvNauseaEnabled = CreateClientConVar("woundsys_nausea_enabled", "1", true, false, "Enable POV spinning/shaking motion nausea and disorientation.", 0, 1)
local cvNauseaSensitivity = CreateClientConVar("woundsys_nausea_sensitivity", "1.0", true, false, "Sensitivity multiplier for POV motion nausea.", 0.2, 3.0)

local lastEyeAngles = nil
WoundSystemSpinNauseaIntensity = WoundSystemSpinNauseaIntensity or 0

local sustainedSpinTime = 0

hook.Add("Think", "WoundSystem_SpinNauseaThink", function()
    if not cvNauseaEnabled:GetBool() then
        sustainedSpinTime = 0
        WoundSystemSpinNauseaIntensity = math.max(0, WoundSystemSpinNauseaIntensity - FrameTime() * 1.5)
        return
    end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then
        sustainedSpinTime = 0
        WoundSystemSpinNauseaIntensity = 0
        lastEyeAngles = nil
        return
    end

    local curAng = ply:EyeAngles()
    if not lastEyeAngles then
        lastEyeAngles = Angle(curAng.p, curAng.y, curAng.r)
        return
    end

    local dt = math.max(RealFrameTime(), 0.001)
    local diffPitch = math.abs(math.AngleDifference(curAng.p, lastEyeAngles.p)) / dt
    local diffYaw = math.abs(math.AngleDifference(curAng.y, lastEyeAngles.y)) / dt
    lastEyeAngles = Angle(curAng.p, curAng.y, curAng.r)

    local sensitivity = math.max(cvNauseaSensitivity:GetFloat() or 1.0, 0.1)
    local angularVel = (diffPitch + diffYaw) * sensitivity

    -- REALISTIC VESTIBULAR ACCUMULATION:
    -- Quick mouse flicks (< 1.2s) do NOT make you motion sick.
    -- Continuous sustained spinning (> 1.2s+) gradually builds up motion nausea.
    if angularVel > 260 then
        sustainedSpinTime = math.min(5.0, sustainedSpinTime + dt)
    else
        sustainedSpinTime = math.max(0, sustainedSpinTime - dt * 2.5)
    end

    if sustainedSpinTime > 1.2 then
        local spinFactor = (sustainedSpinTime - 1.2) / 3.8
        local speedMult = math.Clamp(angularVel / 600, 0.5, 2.0)
        local targetNausea = math.Clamp(spinFactor * speedMult, 0, 1.0)
        
        WoundSystemSpinNauseaIntensity = WoundSystemScreenFX.Smooth(WoundSystemSpinNauseaIntensity or 0, targetNausea, 0.8 * sensitivity, 0.5)
    else
        WoundSystemSpinNauseaIntensity = math.max(0, (WoundSystemSpinNauseaIntensity or 0) - dt * 0.22)
    end
end)

hook.Add("CalcView", "WoundSystem_SpinNauseaCalcView", function(ply, pos, angles, fov)
    if not cvNauseaEnabled:GetBool() or not WoundSystemSpinNauseaIntensity or WoundSystemSpinNauseaIntensity <= 0.05 then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local intensity = WoundSystemSpinNauseaIntensity
    local t = RealTime() * 3.8
    local rollTilt = math.sin(t) * intensity * 7.5
    local pitchWobble = math.cos(t * 1.4) * intensity * 2.8

    angles.r = angles.r + rollTilt
    angles.p = angles.p + pitchWobble
end)

hook.Add("RenderScreenspaceEffects", "WoundSystem_SpinNauseaRenderFX", function()
    if not cvNauseaEnabled:GetBool() or not WoundSystemSpinNauseaIntensity or WoundSystemSpinNauseaIntensity <= 0.12 then return end

    local intensity = WoundSystemSpinNauseaIntensity
    if DrawMotionBlur then
        DrawMotionBlur(0.08, math.Clamp(intensity * 0.55, 0.05, 0.75), 0.02)
    end
end)
