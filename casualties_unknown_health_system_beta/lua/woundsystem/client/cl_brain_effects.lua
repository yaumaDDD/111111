if WoundSystem and WoundSystem.BrainEffects and WoundSystem.BrainEffects._ClientLoaded then
    hook.Remove("RenderScreenspaceEffects", "WoundSystem_LobotomyVisualEffects")
    hook.Remove("CreateMove", "WoundSystem_LobotomyInputDelay")
    hook.Remove("CreateMove", "WoundSystem_LobotomySlipperyAim")
    hook.Remove("CreateMove", "WoundSystem_LobotomyInvertControls")
    hook.Remove("Think", "WoundSystem_BrainReverseClientState")
    hook.Remove("RenderScreenspaceEffects", "WoundSystem_BrainReverseScreenFlip")
    hook.Remove("PopulateToolMenu", "WoundSystem_LobotomyMenu")
    hook.Remove("RenderScreenspaceEffects", "DoomVisualEffects")
    hook.Remove("CreateMove", "DoomInputDelay")
    hook.Remove("CreateMove", "DoomSlipperyAim")
    hook.Remove("CreateMove", "DoomInvertControls")
    hook.Remove("CalcView", "WoundSystem_BrainDamageShakeView")
    hook.Remove("PopulateToolMenu", "DoomMenu")
end

WoundSystem = WoundSystem or {}
WoundSystem.BrainEffects = WoundSystem.BrainEffects or {}
WoundSystem.BrainEffects._ClientLoaded = true

local cvBrainCA = CreateClientConVar("woundsys_brain_ca_enabled", "1", true, false)
local cvBrainCAThreshold = CreateClientConVar("woundsys_brain_ca_threshold", "30", true, false)
local cvBrainCAIntensity = CreateClientConVar("woundsys_brain_ca_intensity", "15", true, false)
local cvBrainInvertFrame = CreateClientConVar("woundsys_brain_invert_frame", "1", true, false)
local cvBrainSharpen = CreateClientConVar("woundsys_brain_sharpen", "1", true, false)
local cvBrainFlashDuration = CreateClientConVar("woundsys_brain_flash_duration", "10", true, false)
local cvBrainFlashOpacity = CreateClientConVar("woundsys_brain_flash_opacity", "255", true, false)
local cvBrainFlashStack = CreateClientConVar("woundsys_brain_flash_stack", "2", true, false)
local cvBrainGhostExposureEnabled = CreateClientConVar("woundsys_brain_ghost_exposure_enabled", "0", true, false)
local cvBrainGhostExposure = CreateClientConVar("woundsys_brain_ghost_exposure", "2", true, false)
local cvBrainAimSlow = CreateClientConVar("woundsys_brain_aim_slow", "3", true, false)
local cvBrainInputDelay = CreateClientConVar("woundsys_brain_input_delay", "0", true, false)
local cvBrainDelayMs = CreateClientConVar("woundsys_brain_delay_ms", "200", true, false)
local cvBrainInvertControls = CreateClientConVar("woundsys_brain_invert_controls", "0", true, false)
local cvBrainReverseFlip = CreateClientConVar("woundsys_brain_reverse_flip", "1", true, false)

local function WoundSystemClientEnabled()
    local client = WoundSystem and WoundSystem.Client
    if client and client.IsEnabled then
        return client.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

local effectActive = false
local effectStartTime = 0
local needsCapture = false
local currentCA = 0
local inputBuffer = {}
local lastAngles = nil

local function IsWoundSystemRagdollCameraActive()
    local ply = LocalPlayer()
    if not IsValid(ply) then return false end

    if WoundSystem.IsRagdollCameraActiveClient and WoundSystem.IsRagdollCameraActiveClient(ply) then
        return true
    end

    return IsValid(ply:GetNWEntity("WoundSystemUnconsciousRagdoll"))
        or not ply:Alive()
        or ply:GetNWBool("WoundSystemUnconscious", false)
        or ply:GetNoDraw()
end

local rt = GetRenderTarget("woundsys_brain_rt_snapshot", ScrW(), ScrH())
local rtMat = CreateMaterial("woundsys_brain_rt_material_snapshot", "UnlitGeneric", {
    ["$basetexture"] = rt:GetName(),
    ["$vertexalpha"] = "1",
    ["$vertexcolor"] = "1"
})

local caMat = CreateMaterial("woundsys_brain_ca_material_true", "UnlitGeneric", {
    ["$basetexture"] = "_rt_FullFrameFB",
    ["$vertexalpha"] = "1",
    ["$vertexcolor"] = "1"
})

local flipMat = CreateMaterial("woundsys_brain_reverse_flip_material", "UnlitGeneric", {
    ["$basetexture"] = "_rt_FullFrameFB",
    ["$vertexalpha"] = "1",
    ["$vertexcolor"] = "1"
})

local function IsBrainReverseActive()
    if not WoundSystemClientEnabled() then return false end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return false end
    if IsWoundSystemRagdollCameraActive() then return false end

    local csharpReverse = ply:GetNWFloat("WoundSystemBrainReverseUntil", 0) > CurTime()
    local lobotomyReverse = effectActive and cvBrainInvertControls:GetBool()
    return csharpReverse or lobotomyReverse
end

local function LobotomySoundPath()
    if file.Exists("sound/lobotomy_assets/Lobotomy.ogg", "GAME") then
        return "lobotomy_assets/Lobotomy.ogg"
    end

    if file.Exists("sound/lobotomy.ogg", "GAME") then
        return "lobotomy.ogg"
    end

    return "lobotomy.ogg"
end

net.Receive("WoundSystem_LobotomyEffect", function()
    if not WoundSystemClientEnabled() then return end

    effectActive = true
    effectStartTime = CurTime()
    needsCapture = true
end)

hook.Add("Think", "WoundSystem_BrainReverseClientState", function()
    if not WoundSystemClientEnabled() then
        effectActive = false
        inputBuffer = {}
        lastAngles = nil

        WoundSystemClientState = WoundSystemClientState or {}
        WoundSystemClientState.Cardio = WoundSystemClientState.Cardio or {}
        WoundSystemClientState.Cardio.reversedControls = false

        if WoundSystemScreenFX then
            WoundSystemScreenFX.brainReverseActive = false
            WoundSystemScreenFX.brainReverseFlipDrawsScreen = false
        end
        return
    end

    local reversed = IsBrainReverseActive()

    WoundSystemClientState = WoundSystemClientState or {}
    WoundSystemClientState.Cardio = WoundSystemClientState.Cardio or {}
    WoundSystemClientState.Cardio.reversedControls = reversed

    if WoundSystemScreenFX then
        WoundSystemScreenFX.brainReverseActive = reversed
        WoundSystemScreenFX.brainReverseFlipDrawsScreen = reversed and cvBrainReverseFlip:GetBool()
    end
end)

hook.Add("RenderScreenspaceEffects", "WoundSystem_LobotomyVisualEffects", function()
    if not WoundSystemClientEnabled() then return end

    if needsCapture then
        needsCapture = false

        if cvBrainSharpen:GetBool() then
            DrawSharpen(2, 1.2)
        end

        if cvBrainInvertFrame:GetBool() then
            draw.NoTexture()
            surface.SetDrawColor(255, 255, 255, 255)

            render.OverrideBlend(true, BLEND_ONE_MINUS_DST_COLOR, BLEND_ZERO, BLENDFUNC_ADD)
            surface.DrawRect(0, 0, ScrW(), ScrH())

            render.CopyRenderTargetToTexture(rt)

            surface.DrawRect(0, 0, ScrW(), ScrH())
            render.OverrideBlend(false)
        else
            render.CopyRenderTargetToTexture(rt)
        end
    end

    local ply = LocalPlayer()
    local targetCA = 0

    if IsValid(ply) and ply:Alive() and cvBrainCA:GetBool() then
        if ply:Health() <= cvBrainCAThreshold:GetInt() then
            targetCA = cvBrainCAIntensity:GetFloat()
        end
    end

    currentCA = Lerp(FrameTime() * 3, currentCA, targetCA)

    if currentCA > 0.5 then
        render.UpdateScreenEffectTexture()
        caMat:SetTexture("$basetexture", render.GetScreenEffectTexture())

        render.Clear(0, 0, 0, 255, true, true)
        surface.SetMaterial(caMat)

        render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
        surface.SetDrawColor(255, 0, 0, 255)
        surface.DrawTexturedRect(-currentCA, 0, ScrW(), ScrH())

        render.OverrideBlend(true, BLEND_ONE, BLEND_ONE, BLENDFUNC_ADD)
        surface.SetDrawColor(0, 255, 0, 255)
        surface.DrawTexturedRect(0, 0, ScrW(), ScrH())

        render.OverrideBlend(true, BLEND_ONE, BLEND_ONE, BLENDFUNC_ADD)
        surface.SetDrawColor(0, 0, 255, 255)
        surface.DrawTexturedRect(currentCA, 0, ScrW(), ScrH())

        render.OverrideBlend(false)
    end

    if not effectActive then return end

    local duration = cvBrainFlashDuration:GetFloat()
    local opacity = cvBrainFlashOpacity:GetFloat()
    local stack = cvBrainFlashStack:GetInt()
    local elapsed = CurTime() - effectStartTime

    if elapsed > duration then
        effectActive = false
        return
    end

    local alpha = (elapsed <= duration * 0.3)
        and opacity
        or Lerp((elapsed - duration * 0.3) / (duration * 0.7), opacity, 0)

    alpha = math.Clamp(alpha, 0, 255)
    surface.SetMaterial(rtMat)

    if cvBrainCA:GetBool() then
        local offset = cvBrainCAIntensity:GetFloat()

        for _ = 1, stack do
            render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD)
            surface.SetDrawColor(255, 0, 0, alpha)
            surface.DrawTexturedRect(-offset, 0, ScrW(), ScrH())

            render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
            surface.SetDrawColor(0, 255, 0, alpha)
            surface.DrawTexturedRect(0, 0, ScrW(), ScrH())

            render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
            surface.SetDrawColor(0, 0, 255, alpha)
            surface.DrawTexturedRect(offset, 0, ScrW(), ScrH())
        end

        render.OverrideBlend(false)
    else
        for _ = 1, stack do
            surface.SetDrawColor(255, 255, 255, alpha)
            surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
        end
    end

    if cvBrainGhostExposureEnabled:GetBool() then
        local exposure = cvBrainGhostExposure:GetFloat()

        if exposure > 0 and alpha > 0 then
            render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
            surface.SetMaterial(rtMat)

            local passes = math.ceil(exposure)
            local fraction = exposure / passes

            for _ = 1, passes do
                surface.SetDrawColor(255, 255, 255, alpha * fraction)
                surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
            end

            render.OverrideBlend(false)
        end
    end
end)

hook.Add("RenderScreenspaceEffects", "WoundSystem_BrainReverseScreenFlip", function()
    if not WoundSystemClientEnabled() then return end
    if not cvBrainReverseFlip:GetBool() then return end
    if not IsBrainReverseActive() then return end

    render.UpdateScreenEffectTexture()
    flipMat:SetTexture("$basetexture", render.GetScreenEffectTexture())
    surface.SetMaterial(flipMat)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawTexturedRectUV(0, 0, ScrW(), ScrH(), 1, 1, 0, 0)
end)

hook.Add("CreateMove", "WoundSystem_LobotomyInputDelay", function(cmd)
    if not WoundSystemClientEnabled() then
        inputBuffer = {}
        return
    end

    if IsWoundSystemRagdollCameraActive() then
        inputBuffer = {}
        return
    end

    if not effectActive then
        inputBuffer = {}
        return
    end

    if not cvBrainInputDelay:GetBool() then return end

    local delay = cvBrainDelayMs:GetFloat() / 1000

    inputBuffer[#inputBuffer + 1] = {
        t = CurTime(),
        f = cmd:GetForwardMove(),
        s = cmd:GetSideMove()
    }

    cmd:SetForwardMove(0)
    cmd:SetSideMove(0)

    if #inputBuffer > 0 and CurTime() - inputBuffer[1].t >= delay then
        local delayedCmd = table.remove(inputBuffer, 1)
        cmd:SetForwardMove(delayedCmd.f)
        cmd:SetSideMove(delayedCmd.s)
    end
end)

hook.Add("CreateMove", "WoundSystem_LobotomySlipperyAim", function(cmd)
    if not WoundSystemClientEnabled() then
        lastAngles = nil
        return
    end

    if IsWoundSystemRagdollCameraActive() then
        lastAngles = nil
        return
    end

    if not effectActive then
        lastAngles = nil
        return
    end

    local slow = cvBrainAimSlow:GetFloat()
    local elapsed = CurTime() - effectStartTime

    if elapsed < 7 then
        local ang = cmd:GetViewAngles()
        lastAngles = lastAngles or ang
        local smooth = LerpAngle(FrameTime() * slow, lastAngles, ang)
        cmd:SetViewAngles(smooth)
        lastAngles = smooth
    else
        lastAngles = nil
    end
end)

hook.Add("CreateMove", "WoundSystem_LobotomyInvertControls", function(cmd)
    if not WoundSystemClientEnabled() then return end
    if not IsBrainReverseActive() then return end

    cmd:SetForwardMove(-cmd:GetForwardMove())
    cmd:SetSideMove(-cmd:GetSideMove())
end)

hook.Add("CalcView", "WoundSystem_BrainDamageShakeView", function(ply, pos, angles, fov)
    if not WoundSystemClientEnabled() then return end
    if not IsValid(ply) then return end
    if IsWoundSystemRagdollCameraActive() then return end

    local shakeUntil = ply:GetNWFloat("WoundSystemBrainShakeUntil", 0)
    if shakeUntil <= CurTime() then return end

    local frac = math.Clamp(1 - ((shakeUntil - CurTime()) / 5), 0, 1)
    local amt = frac * 1.75
    local view = {
        origin = pos,
        angles = Angle(
            angles.p + math.sin(CurTime() * 17) * amt,
            angles.y + math.sin(CurTime() * 13.7) * amt,
            angles.r + math.sin(CurTime() * 21.3) * amt
        ),
        fov = fov
    }

    return view
end)

WoundSystem.BrainEffects.IsLobotomyActive = function()
    return effectActive
end

WoundSystem.BrainEffects.IsBrainReverseActive = IsBrainReverseActive
