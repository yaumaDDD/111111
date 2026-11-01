WoundSystem = WoundSystem or {}
WoundSystemScreenFX = WoundSystemScreenFX or {}

local ScreenFX = WoundSystemScreenFX

local function EnsureClientConVar(name, defaultValue, helpText, minValue, maxValue, archive)
    local existing = GetConVar(name)
    if existing then return existing end

    if archive == nil then archive = true end
    return CreateClientConVar(name, defaultValue, archive, false, helpText, minValue, maxValue)
end

local cvPainShaderEnabled = EnsureClientConVar("woundsys_pain_shader_enabled", "1", "Use the WoundSystem custom pain pixel shader when available.", 0, 1)
local cvPainShaderStrength = EnsureClientConVar("woundsys_pain_shader_strength", "1", "Scale the custom pain pixel shader blend.", 0, 2)
local cvPainShaderDistortion = EnsureClientConVar("woundsys_pain_shader_distortion", "1", "Scale pain pixel shader mask distortion.", 0, 2)
local cvConditionShaderEnabled = EnsureClientConVar("woundsys_condition_shader_enabled", "1", "Use the WoundSystem condition pixel shader for depression and dirt.", 0, 1)
local cvAberrationShaderEnabled = EnsureClientConVar("woundsys_aberration_shader_enabled", "1", "Use the WoundSystem aberration/distortion pixel shader.", 0, 1)
local cvScreenPassDebug = EnsureClientConVar("woundsys_screenpass_debug", "0", "Debug WoundSystem CAS3-style screen pass layers.", 0, 5, false)

local PAIN_SHADER_ACTIVATION = 0.02
local PAIN_SHADER_FULL = 0.50
local CAS3_CAPTURE_PAIN_MASK = 0.74994
local CAS3_CAPTURE_DESATURATION = 0.82661
local CAS3_CAPTURE_DISTORTION = 0.10407
local CAS3_CAPTURE_OVERLAY_BLEND = 0.10835
local CAS3_CAPTURE_SATURATION = 1.0
local CAS3_CAPTURE_QUANTIZE = 0.25134
local CAS3_CAPTURE_NOISE_DRIFT = 0.01766

ScreenFX.Smooth = ScreenFX.Smooth or function(current, target, riseSpeed, fallSpeed)
    local speed = ((target or 0) > (current or 0)) and riseSpeed or fallSpeed
    local dt = RealFrameTime and RealFrameTime() or FrameTime()
    return Lerp(1 - math.exp(-math.max(dt, 0) * speed), current or 0, target or 0)
end

local function Number(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value then return fallback or 0 end

    return value
end

local function SmoothField(field, target, riseSpeed, fallSpeed)
    ScreenFX[field] = ScreenFX.Smooth(ScreenFX[field] or 0, target or 0, riseSpeed, fallSpeed)
    return ScreenFX[field]
end

local function SmoothStep01(value)
    value = math.Clamp(value or 0, 0, 1)
    return value * value * (3 - 2 * value)
end

local function IsMaterialError(mat)
    return not mat or (mat.IsError and mat:IsError())
end

local function BindTextureSlot(mat, slotName, materialPath)
    if not mat or not mat.SetTexture then return end

    local sourceMat = Material(materialPath, "smooth")
    if IsMaterialError(sourceMat) or not sourceMat.GetTexture then return end

    local texture = sourceMat:GetTexture("$basetexture")
    if texture then
        mat:SetTexture(slotName, texture)
    end
end

local function GetPainShaderMaterial()
    if ScreenFX._PainShaderUnavailable then return nil end

    if not ScreenFX._PainShaderMaterial then
        ScreenFX._PainShaderMaterial = CreateMaterial("woundsystem_pain_composite_runtime_v7", "screenspace_general", {
            ["$pixshader"] = "woundsystem_pain_ps20b",
            ["$basetexture"] = "_rt_FullFrameFB",
            ["$texture1"] = "casunknown-images/screen/painimage",
            ["$texture2"] = "casunknown-images/screen/painnoise",
            ["$texture3"] = "casunknown-images/screen/paingrain",
            ["$ignorez"] = 1,
            ["$vertexcolor"] = 1,
            ["$vertextransform"] = 1,
            ["$copyalpha"] = 1,
            ["$alpha_blend_color_overlay"] = 0,
            ["$alpha_blend"] = 1,
            ["$linearwrite"] = 1,
            ["$linearread_basetexture"] = 1,
            ["$linearread_texture1"] = 1,
            ["$linearread_texture2"] = 1,
            ["$linearread_texture3"] = 1
        })
        ScreenFX._PainShaderTexturesBound = false
    end

    local mat = ScreenFX._PainShaderMaterial
    if IsMaterialError(mat) then
        ScreenFX._PainShaderUnavailable = true
        return nil
    end

    if not ScreenFX._PainShaderTexturesBound then
        BindTextureSlot(mat, "$texture1", "casunknown-images/screen/painimage")
        BindTextureSlot(mat, "$texture2", "casunknown-images/screen/painnoise")
        BindTextureSlot(mat, "$texture3", "casunknown-images/screen/paingrain")
        ScreenFX._PainShaderTexturesBound = true
    end

    return mat
end

local function GetConditionShaderMaterial()
    if ScreenFX._ConditionShaderUnavailable then return nil end

    if not ScreenFX._ConditionShaderMaterial then
        ScreenFX._ConditionShaderMaterial = CreateMaterial("woundsystem_condition_composite_runtime_v2", "screenspace_general", {
            ["$pixshader"] = "woundsystem_condition_ps20b",
            ["$basetexture"] = "_rt_FullFrameFB",
            ["$texture1"] = "casunknown-images/screen/depressionoverlay",
            ["$texture2"] = "casunknown-images/screen/dirtcolor",
            ["$texture3"] = "casunknown-images/screen/dirtopacity",
            ["$ignorez"] = 1,
            ["$vertexcolor"] = 1,
            ["$vertextransform"] = 1,
            ["$copyalpha"] = 1,
            ["$alpha_blend_color_overlay"] = 0,
            ["$alpha_blend"] = 1,
            ["$linearwrite"] = 1,
            ["$linearread_basetexture"] = 1,
            ["$linearread_texture1"] = 1,
            ["$linearread_texture2"] = 1,
            ["$linearread_texture3"] = 1
        })
        ScreenFX._ConditionShaderTexturesBound = false
    end

    local mat = ScreenFX._ConditionShaderMaterial
    if IsMaterialError(mat) then
        ScreenFX._ConditionShaderUnavailable = true
        return nil
    end

    if not ScreenFX._ConditionShaderTexturesBound then
        BindTextureSlot(mat, "$texture1", "casunknown-images/screen/depressionoverlay")
        BindTextureSlot(mat, "$texture2", "casunknown-images/screen/dirtcolor")
        BindTextureSlot(mat, "$texture3", "casunknown-images/screen/dirtopacity")
        ScreenFX._ConditionShaderTexturesBound = true
    end

    return mat
end

local function GetAberrationShaderMaterial()
    if ScreenFX._AberrationShaderUnavailable then return nil end

    if not ScreenFX._AberrationShaderMaterial then
        ScreenFX._AberrationShaderMaterial = CreateMaterial("woundsystem_aberration_composite_runtime_v1", "screenspace_general", {
            ["$pixshader"] = "woundsystem_aberration_ps20b",
            ["$basetexture"] = "_rt_FullFrameFB",
            ["$texture1"] = "casunknown-images/screen/aberrationtex",
            ["$ignorez"] = 1,
            ["$vertexcolor"] = 1,
            ["$vertextransform"] = 1,
            ["$copyalpha"] = 1,
            ["$alpha_blend_color_overlay"] = 0,
            ["$alpha_blend"] = 1,
            ["$linearwrite"] = 1,
            ["$linearread_basetexture"] = 1,
            ["$linearread_texture1"] = 1
        })
        ScreenFX._AberrationShaderTexturesBound = false
    end

    local mat = ScreenFX._AberrationShaderMaterial
    if IsMaterialError(mat) then
        ScreenFX._AberrationShaderUnavailable = true
        return nil
    end

    if not ScreenFX._AberrationShaderTexturesBound then
        BindTextureSlot(mat, "$texture1", "casunknown-images/screen/aberrationtex")
        ScreenFX._AberrationShaderTexturesBound = true
    end

    return mat
end

function ScreenFX.UpdateAberrationShaderVisuals(painDistortion, lowOxygen)
    local c = (WoundSystemClientState and WoundSystemClientState.Cardio) or {}
    local actualOpiate = Number(c.actualOpiateReception or c.opiateReception, 0)
    local withdrawal = 0
    if actualOpiate < 0 then
        withdrawal = (0 - actualOpiate) * 0.05
        if actualOpiate < -30 then
            withdrawal = withdrawal + (0 - (actualOpiate + 30))
        end
    end

    local intensityTarget = math.Clamp(withdrawal, 0, 1)
    local oxygen = math.Clamp(Number(c.bloodOxygen, 100), 0, 100)
    local opiateHelp = math.max(actualOpiate * 0.015, 0)
    local lowOxyDistort = math.max(1 - ((oxygen * 0.01 - 0.3) / 0.5), opiateHelp)
    local distortTarget = -math.Clamp(Number(painDistortion, 0), 0, 1) - math.Clamp(lowOxyDistort, 0, 1) * 0.1 - math.Clamp(Number(lowOxygen, 0), 0, 1) * 0.05

    local reverseActive = c.reversedControls or ScreenFX.brainReverseActive
    local shaderFlipActive = reverseActive and not ScreenFX.brainReverseFlipDrawsScreen

    ScreenFX.aberrationIntensity = SmoothField("_AberrationIntensity", intensityTarget, 3.5, 1.6)
    ScreenFX.aberrationDistort = SmoothField("_AberrationDistort", distortTarget, 3.8, 2.2)
    ScreenFX.aberrationFlip = SmoothField("_AberrationFlip", shaderFlipActive and 1 or 0, 8, 8)

    return ScreenFX.aberrationIntensity, ScreenFX.aberrationDistort, ScreenFX.aberrationFlip
end

function ScreenFX.DrawAberrationCompositeShader(intensity, distort, flip)
    ScreenFX._AberrationCompositeShaderFrame = -1
    if not render or not cvAberrationShaderEnabled:GetBool() then return false end

    intensity = math.Clamp(Number(intensity, 0), 0, 1)
    distort = math.Clamp(Number(distort, 0), -1, 1)
    flip = math.Clamp(Number(flip, 0), 0, 1)
    if intensity <= 0.00005 and math.abs(distort) <= 0.00005 and flip <= 0.00005 then return false end

    local mat = GetAberrationShaderMaterial()
    if not mat then return false end

    if render.UpdateScreenEffectTexture then
        render.UpdateScreenEffectTexture()
    end

    mat:SetFloat("$c0_x", intensity)
    mat:SetFloat("$c0_y", distort)
    mat:SetFloat("$c0_z", flip)
    mat:SetFloat("$c0_w", CurTime())
    mat:SetFloat("$c1_x", math.Clamp(cvScreenPassDebug:GetInt(), 0, 5))
    mat:SetFloat("$c1_y", 1)
    mat:SetFloat("$c1_z", 1)

    if render.SetScissorRect then
        render.SetScissorRect(0, 0, 0, 0, false)
    end

    render.SetMaterial(mat)
    render.DrawScreenQuad()

    ScreenFX._AberrationCompositeShaderFrame = FrameNumber and FrameNumber() or -1
    return true
end

function ScreenFX.DrawConditionCompositeShader(depression, dirtyness)
    ScreenFX._ConditionCompositeShaderFrame = -1
    if not render or not cvConditionShaderEnabled:GetBool() then return false end

    depression = math.Clamp(Number(depression, 0), 0, 1)
    dirtyness = math.Clamp(Number(dirtyness, 0), 0, 1)
    local debugMode = math.Clamp(cvScreenPassDebug:GetInt(), 0, 5)
    if depression <= 0.00005 and dirtyness <= 0.00005 then return false end

    local mat = GetConditionShaderMaterial()
    if not mat then return false end

    if render.UpdateScreenEffectTexture then
        render.UpdateScreenEffectTexture()
    end

    mat:SetFloat("$c0_x", depression)
    mat:SetFloat("$c0_y", dirtyness)
    mat:SetFloat("$c0_z", CurTime())
    mat:SetFloat("$c0_w", debugMode)
    mat:SetFloat("$c1_x", 1)
    mat:SetFloat("$c1_y", 1)
    mat:SetFloat("$c1_z", CAS3_CAPTURE_DESATURATION)

    if render.SetScissorRect then
        render.SetScissorRect(0, 0, 0, 0, false)
    end

    render.SetMaterial(mat)
    render.DrawScreenQuad()

    ScreenFX._ConditionCompositeShaderFrame = FrameNumber and FrameNumber() or -1
    return true
end

function ScreenFX.DrawPainCompositeShader(painPulse, painDistortion, focusPain, lowOxygen, bloodLoss, consciousnessBlur, opiateVisual, withdrawalVisual, depression, dirtyness)
    ScreenFX._PainCompositeShaderFrame = -1
    if not render or not cvPainShaderEnabled:GetBool() then return false end

    local rawPain = math.Clamp(Number(painPulse, 0), 0, 1)
    local pain = math.Clamp((rawPain - PAIN_SHADER_ACTIVATION) / (PAIN_SHADER_FULL - PAIN_SHADER_ACTIVATION), 0, 1)
    pain = SmoothStep01(pain)

    lowOxygen = math.Clamp(Number(lowOxygen, 0), 0, 1)
    bloodLoss = math.Clamp(Number(bloodLoss, 0), 0, 1)
    consciousnessBlur = math.Clamp(Number(consciousnessBlur, 0), 0, 1)
    opiateVisual = math.Clamp(Number(opiateVisual, 0), 0, 1)
    withdrawalVisual = math.Clamp(Number(withdrawalVisual, 0), 0, 1)
    depression = math.Clamp(Number(depression, 0), 0, 1)
    dirtyness = math.Clamp(Number(dirtyness, 0), 0, 1)

    local debugMode = math.Clamp(cvScreenPassDebug:GetInt(), 0, 5)
    if debugMode == 4 then return false end

    local conditionOverlay = math.max(depression, dirtyness * 0.65)
    local screenSeverity = math.max(pain, painDistortion, lowOxygen, bloodLoss, consciousnessBlur, withdrawalVisual, conditionOverlay)
    if screenSeverity <= 0.00005 then return false end

    local strength = math.Clamp(cvPainShaderStrength:GetFloat(), 0, 2)
    if strength <= 0.00005 then return false end

    local mat = GetPainShaderMaterial()
    if not mat then return false end

    if render.UpdateScreenEffectTexture then
        render.UpdateScreenEffectTexture()
    end

    local distortion = math.Clamp((Number(painDistortion, 0) + Number(focusPain, 0) * 0.65) * cvPainShaderDistortion:GetFloat(), 0, 1)
    local pulse = math.sin((ScreenFX.painbeatTime or 0) * 1.7)
    local conditionAndDrug = math.max(conditionOverlay, withdrawalVisual * 0.75, opiateVisual * 0.25)
    local quantize = CAS3_CAPTURE_QUANTIZE * SmoothStep01(math.Clamp(screenSeverity * 1.12 + withdrawalVisual * 0.28, 0, 1))
    local desaturation = CAS3_CAPTURE_DESATURATION * (1 + math.min(conditionAndDrug, 1) * 0.18)
    local saturation = math.max(CAS3_CAPTURE_SATURATION - math.max(lowOxygen, consciousnessBlur) * 0.08 - bloodLoss * 0.05, 0.65)
    local drift = CAS3_CAPTURE_NOISE_DRIFT * (1 + screenSeverity * 0.85)

    mat:SetFloat("$c0_x", pain)
    mat:SetFloat("$c0_y", CurTime())
    mat:SetFloat("$c0_z", strength)
    mat:SetFloat("$c0_w", math.Clamp(distortion + CAS3_CAPTURE_DISTORTION * screenSeverity * 0.55, 0, 1))
    mat:SetFloat("$c1_x", pulse)
    mat:SetFloat("$c1_y", lowOxygen)
    mat:SetFloat("$c1_z", bloodLoss)
    mat:SetFloat("$c1_w", consciousnessBlur)
    mat:SetFloat("$c2_x", debugMode)
    mat:SetFloat("$c2_y", conditionAndDrug)
    mat:SetFloat("$c2_z", withdrawalVisual)
    mat:SetFloat("$c2_w", quantize)
    mat:SetFloat("$c3_x", math.max(CAS3_CAPTURE_OVERLAY_BLEND, CAS3_CAPTURE_PAIN_MASK * 0.08))
    mat:SetFloat("$c3_y", desaturation)
    mat:SetFloat("$c3_z", saturation)
    mat:SetFloat("$c3_w", drift)

    if render.SetScissorRect then
        render.SetScissorRect(0, 0, 0, 0, false)
    end

    render.SetMaterial(mat)

    render.DrawScreenQuad()

    ScreenFX._PainCompositeShaderFrame = FrameNumber and FrameNumber() or -1
    return true
end

function ScreenFX.WantsPainCompositeShader()
    return cvPainShaderEnabled:GetBool()
        and cvPainShaderStrength:GetFloat() > 0.00005
end

function ScreenFX.GetScreenPassDebugMode()
    return math.Clamp(cvScreenPassDebug:GetInt(), 0, 5)
end

function ScreenFX.PainCompositeShaderDrewThisFrame()
    return FrameNumber and ScreenFX._PainCompositeShaderFrame == FrameNumber()
end

function ScreenFX.HasMercShaders()
    return render
        and (
            render.DrawMercChromaticAberration
            or render.DrawMercRadialBlur
            or render.DrawMercBlur
            or render.DrawMercVignette
            or render.DrawMercFilmGrain
            or render.DrawMercFisheye
        )
end

function ScreenFX.TryMercShader(fn, ...)
    if type(fn) ~= "function" then return false end

    local ok, err = pcall(fn, ...)
    if not ok then
        ScreenFX.nextMercShaderWarn = ScreenFX.nextMercShaderWarn or 0
        if CurTime() >= ScreenFX.nextMercShaderWarn then
            ScreenFX.nextMercShaderWarn = CurTime() + 5
            MsgC(Color(255, 170, 80), "[WoundSystem] Simple Custom Shaders call failed: " .. tostring(err) .. "\n")
        end
        return false
    end

    return true
end

function ScreenFX.UpdatePlayerCameraChannels()
    local frameNumber = FrameNumber and FrameNumber() or -1
    if frameNumber == ScreenFX._PlayerCameraChannelFrame and ScreenFX._PlayerCameraChannels then
        return ScreenFX._PlayerCameraChannels
    end

    ScreenFX._PlayerCameraChannelFrame = frameNumber

    local c = (WoundSystemClientState and WoundSystemClientState.Cardio) or {}
    local ply = LocalPlayer()
    local alive = IsValid(ply) and ply:Alive()

    local hunger = 0
    local thirst = 0
    local sickness = 0
    local cold = 0
    local overheat = 0
    local dirty = 0
    local wet = 0
    local stimulant = 0

    if alive and not (WoundSystem and WoundSystem.HealthGUI and WoundSystem.HealthGUI.IsSpawnVisualGraceActive and WoundSystem.HealthGUI.IsSpawnVisualGraceActive()) then
        hunger = SmoothStep01((25 - Number(c.hunger, 100)) / 25)
        thirst = SmoothStep01((25 - Number(c.thirst, 100)) / 25)
        sickness = math.Clamp(Number(c.sicknessAmount, 0) * 0.01, 0, 1)
        cold = math.Clamp((34 - Number(c.temperature, 37)) * 0.17, 0, 1)
        overheat = math.Clamp((Number(c.temperature, 37) - 38.5) * 0.25, 0, 1)
        dirty = math.Clamp(Number(c.dirtyness, 0) * 0.01, 0, 1)
        wet = math.Clamp(Number(c.wetness, 0) * 0.01, 0, 1)
        stimulant = (c.onHardStimulants or Number(c.caffeinated, 0) > 0) and 1 or 0

    end

    ScreenFX._PlayerCameraChannels = {
        hunger = SmoothField("_CamHunger", hunger, 1.0, 0.75),
        thirst = SmoothField("_CamThirst", thirst, 1.0, 0.75),
        sickness = SmoothField("_CamSickness", sickness, 1.0, 0.65),
        cold = SmoothField("_CamCold", cold, 1.0, 0.65),
        overheat = SmoothField("_CamOverheat", overheat, 1.0, 0.85),
        dirty = SmoothField("_CamDirty", dirty, 1.4, 0.25),
        wet = SmoothField("_CamWet", wet, 3.0, 0.65),
        stimulant = SmoothField("_CamStimulant", stimulant, 0.55, 0.22)
    }

    return ScreenFX._PlayerCameraChannels
end

function ScreenFX.HasPlayerCameraEffects(threshold)
    local cam = ScreenFX.UpdatePlayerCameraChannels()
    threshold = threshold or 0.00005

    return cam.hunger > threshold
        or cam.thirst > threshold
        or cam.sickness > threshold
        or cam.cold > threshold
        or cam.overheat > threshold
        or cam.dirty > threshold
        or cam.wet > threshold
        or cam.stimulant > threshold
end

function ScreenFX.DrawVanillaCameraEffects(painPulse, painDistortion, lowOxygen, bloodLoss, focusPain, consciousnessBlur, opiateVisual, withdrawalVisual)
    local cam = ScreenFX.UpdatePlayerCameraChannels()
    local fever = math.max(cam.sickness * 0.65, cam.overheat)
    local deprivation = math.max(cam.hunger, cam.thirst)
    local frost = math.max(cam.cold, cam.wet * 0.35)

    DrawColorModify({
        ["$pp_colour_addr"] = (0.015 * painPulse) + (0.020 * fever) + (0.010 * cam.dirty),
        ["$pp_colour_addg"] = (0.010 * opiateVisual) + (0.012 * cam.sickness) - (0.010 * cam.thirst),
        ["$pp_colour_addb"] = (0.012 * lowOxygen) + (0.016 * opiateVisual) + (0.022 * frost) - (0.014 * fever),
        ["$pp_colour_brightness"] = -0.02 * painPulse - 0.03 * painDistortion - 0.045 * lowOxygen - 0.075 * bloodLoss - 0.035 * consciousnessBlur - (0.025 * opiateVisual) + (0.015 * withdrawalVisual) - (0.030 * deprivation),
        ["$pp_colour_contrast"] = 1 + (focusPain * 0.08) + (painDistortion * 0.14) - (lowOxygen * 0.05) - (bloodLoss * 0.10) - (consciousnessBlur * 0.06) - (opiateVisual * 0.035) + (withdrawalVisual * 0.10) + (cam.stimulant * 0.08),
        ["$pp_colour_colour"] = 1 - (focusPain * 0.16) - (painDistortion * 0.18) - (lowOxygen * 0.34) - (bloodLoss * 0.16) - (consciousnessBlur * 0.12) - (opiateVisual * 0.10) - (withdrawalVisual * 0.18) - (cam.sickness * 0.12) - (frost * 0.18) - (cam.dirty * 0.08) + (cam.stimulant * 0.16),
        ["$pp_colour_mulr"] = 0,
        ["$pp_colour_mulg"] = 0,
        ["$pp_colour_mulb"] = 0
    })

    local bloom = math.Clamp((fever * 0.18) + (lowOxygen * 0.10), 0, 0.75)
    if bloom > 0.00005 then
        DrawBloom(0, bloom, 9, 9, 1, 1, 1 + (fever * 0.25), 1 - (bloodLoss * 0.15), 1 + (frost * 0.25))
    end

    if focusPain > 0.00005 or painDistortion > 0.00005 or withdrawalVisual > 0.00005 then
        DrawSharpen((focusPain * 0.45) + (painDistortion * 1.4) + (withdrawalVisual * 0.7), (focusPain * 0.35) + painDistortion + (withdrawalVisual * 0.45))
    elseif lowOxygen > 0.00005 then
        DrawSharpen(lowOxygen * 0.28, lowOxygen * 0.22)
    end

    return cam
end

function ScreenFX.DrawMercCameraEffects(painPulse, painDistortion, lowOxygen, bloodLoss, focusPain, consciousnessBlur, opiateVisual, withdrawalVisual)
    if not ScreenFX.HasMercShaders() then return false end

    local cam = ScreenFX.UpdatePlayerCameraChannels()
    opiateVisual = opiateVisual or 0
    withdrawalVisual = withdrawalVisual or 0

    local drew = false
    local drewWarp = false
    local fever = math.max(cam.sickness * 0.65, cam.overheat)

    local tunnel = math.Clamp(math.max(lowOxygen * 0.75, bloodLoss, consciousnessBlur * 0.55, painDistortion * 0.45, opiateVisual * 0.34), 0, 1)
    if tunnel > 0.00005 then
        drew = ScreenFX.TryMercShader(render.DrawMercVignette, 1 - (tunnel * 0.42), 0.045 + (tunnel * 0.10)) or drew
    end

    local blur = math.Clamp((lowOxygen * 0.11) + (bloodLoss * 0.075) + (consciousnessBlur * 0.14) + (opiateVisual * 0.09), 0, 0.48)
    if blur > 0.00005 then
        drew = ScreenFX.TryMercShader(render.DrawMercBlur, blur) or drew
    end

    local radial = math.Clamp((bloodLoss * 0.085) + (lowOxygen * 0.065) + (consciousnessBlur * 0.050) + (painDistortion * 0.030) + (opiateVisual * 0.035), 0, 0.24)
    if radial > 0.00005 then
        local ok = ScreenFX.TryMercShader(render.DrawMercRadialBlur, 0.5, 0.5, radial)
        drew = ok or drew
        drewWarp = ok or drewWarp
    end

    local fisheye = math.Clamp((consciousnessBlur * 0.20) + (lowOxygen * 0.13) + (opiateVisual * 0.11), 0, 0.42)
    if fisheye > 0.00005 then
        local ok = ScreenFX.TryMercShader(render.DrawMercFisheye, fisheye)
        drew = ok or drew
        drewWarp = ok or drewWarp
    end

    local aberration = math.Clamp(((focusPain * 0.08) + (painDistortion * 0.42) + (lowOxygen * 0.08) + (withdrawalVisual * 0.26) + (fever * 0.12)) * 2, 0, 1)
    if aberration > 0.00005 then
        local ok = ScreenFX.TryMercShader(render.DrawMercChromaticAberration, aberration, true)
        drew = ok or drew
        drewWarp = ok or drewWarp
    end

    local grain = math.Clamp((painPulse * 0.035) + (lowOxygen * 0.070) + (bloodLoss * 0.055) + (withdrawalVisual * 0.105) + (cam.sickness * 0.035), 0, 0.24)
    if grain > 0.00005 then
        local varianceTarget = Lerp(math.Clamp(grain / 0.24, 0, 1), 0, 0.75)
        local variance = SmoothField("_MercFilmGrainVariance", varianceTarget, 8.0, 3.0)
        drew = ScreenFX.TryMercShader(render.DrawMercFilmGrain, 2, 10, grain, 0, variance) or drew
    end

    ScreenFX.mercDrewLastFrame = drew
    return drewWarp
end
