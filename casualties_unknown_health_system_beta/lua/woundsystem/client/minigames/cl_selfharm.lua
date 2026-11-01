if WoundSystemSelfHarmMinigame and WoundSystemSelfHarmMinigame._Loaded then
    if IsValid(WoundSystemSelfHarmMinigame.overlay) then
        WoundSystemSelfHarmMinigame.overlay:Remove()
    end
    hook.Remove("OnScreenSizeChanged", "WoundSystem_SelfHarmResize")
    hook.Remove("Think", "WoundSystem_SelfHarmInput")
    hook.Remove("ShutDown", "WoundSystem_SelfHarmCleanup")
end

if not (WoundSystem and WoundSystem.MinigameClip) and file.Exists("woundsystem/client/minigames/cl_clip.lua", "LUA") then
    include("woundsystem/client/minigames/cl_clip.lua")
end

local HandPhysics = include("woundsystem/client/minigames/sh_handphysics.lua")

WoundSystemSelfHarmMinigame = WoundSystemSelfHarmMinigame or {}
local MG = WoundSystemSelfHarmMinigame
MG._Loaded = true

-- All materials cached at load time (never inside Paint)
local path = "casunknown-images/selfharm/"
local matHandIdle  = Material(path .. "handSelfHarmIdle.png")
local matHandClick = Material(path .. "handSelfHarmGrab.png")
-- Eye: static background (white of eye). Pupil: separate jittering child.
local matEye       = Material(path .. "minigameeye.png")
local matEyeGone   = Material(path .. "minigameeyegone.png")
local matPupil     = Material(path .. "minigamePupil.png")
-- Cut slash: selfharmdrag drawn as a horizontal fill (FillMethod: Horizontal, FillOrigin: Right)
local matDrag      = Material(path .. "selfharmdrag.png")

-- Hand pivot from prefab: SizeDelta (234, 825), Pivot (0.4527, 0.9009)
-- Scaled to our source hand size (512x1260)
local SRC_HAND_W   = 512
local SRC_HAND_H   = 1260
local HAND_PIVOT_X = 0.4527
local HAND_PIVOT_Y = 0.0991  -- 1 - 0.9009

-- CAS3 prefab: Eye object SizeDelta = (192, 192), centered at (0, 0)
-- Pupil object SizeDelta = (192, 192), child of Eye centered at (0, 0)
local EYE_SRC_SIZE  = 192
-- CAS3: RedFlash color (r:0.811, g:0, b:0) = rgb(207, 0, 0), fullscreen, destroyed after 0.35s
local RED_FLASH_R, RED_FLASH_G, RED_FLASH_B = 207, 0, 0

local function BeginPixelFilter()
    if not render or not TEXFILTER then return false end
    if not render.PushFilterMag or not render.PushFilterMin then return false end
    render.PushFilterMag(TEXFILTER.POINT)
    render.PushFilterMin(TEXFILTER.POINT)
    return true
end

local function EndPixelFilter(active)
    if not active then return end
    if render and render.PopFilterMin and render.PopFilterMag then
        render.PopFilterMin()
        render.PopFilterMag()
    end
end

MG.active       = MG.active or false
MG.sessionId    = MG.sessionId or 0
MG.cutsLeft     = MG.cutsLeft or 1
MG.cutsDone     = MG.cutsDone or 0
MG.triesLeft    = MG.triesLeft or 15
MG.isEye        = MG.isEye or false
MG.cutting      = MG.cutting or false
MG.cutTime      = MG.cutTime or 0
MG.cutSlashes   = MG.cutSlashes or {}
MG.lastMouseDown = false
MG.overlay      = MG.overlay or nil
MG.openTime     = MG.openTime or 0
MG.redFlashAlpha = MG.redFlashAlpha or 0  -- for red flash fade-out

function MG.IsActive()
    return MG.active and IsValid(MG.overlay)
end

function MG.OnLeftClick()
    if not MG.active or MG.cutting then return end

    if MG.triesLeft > 0 then
        -- CAS3: handVelocity += Random.insideUnitCircle.normalized * (15 - triesLeft + 4) * 0.8
        -- Translated to screen pixels with escalating intensity
        local scale  = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or math.min(ScrW() / 1920, ScrH() / 1080)
        local mag    = (15 - MG.triesLeft + 4) * (8 * scale)
        local angle  = math.random() * math.pi * 2
        MG.handScreenVelX = (MG.handScreenVelX or 0) + math.cos(angle) * mag
        MG.handScreenVelY = (MG.handScreenVelY or 0) + math.sin(angle) * mag

        -- CAS3 sound: volume = (15-triesLeft)/15, pitch = 1.5 - (15-triesLeft)/15
        -- PlaybackRate maps inversely so it gets lower as resistance climbs
        local resistPct = (15 - MG.triesLeft) / 15
        local playbackRate = 1.5 - resistPct  -- 1.5 (fresh) -> ~0.57 (last click)
        sound.PlayFile("sound/woundsystem/selfharmtap.ogg", "noplay", function(station)
            if IsValid(station) then
                station:SetPlaybackRate(math.Clamp(playbackRate, 0.3, 1.5))
                station:SetVolume(math.Clamp(resistPct + 0.2, 0.1, 1.0))
                station:Play()
            end
        end)

        MG.triesLeft = MG.triesLeft - 1
    else
        MG.StartCut()
    end
end

function MG.RequestStart(cuts, isEye)
    if WoundSystem and WoundSystem.SelfHarmDisabled then return end
    cuts  = tonumber(cuts) or 1
    isEye = tobool(isEye)

    if MG.IsActive() then MG.Close("restart") end

    MG.sessionId = MG.sessionId + 1
    local currentSession = MG.sessionId

    MG.active        = true
    MG.cutsLeft      = cuts
    MG.cutsDone      = 0
    MG.triesLeft     = 15
    MG.isEye         = isEye
    MG.cutting       = false
    MG.cutTime       = 0
    MG.cutSlashes    = {}
    MG.redFlashAlpha = 0
    MG.lastMouseDown = input.IsMouseDown(MOUSE_LEFT)
    MG.openTime      = CurTime()

    HandPhysics.Init(MG)
    MG.handScreenX    = ScrW() * 0.5
    MG.handScreenY    = ScrH() * 0.45
    MG.handScreenVelX = 0
    MG.handScreenVelY = 0

    if IsValid(MG.overlay) then MG.overlay:Remove() end

    local overlay = vgui.Create("DPanel")
    overlay:SetSize(ScrW(), ScrH())
    overlay:SetPos(0, 0)
    overlay:SetZPos(32000)
    overlay:MakePopup()
    overlay:SetKeyboardInputEnabled(false)
    overlay:SetMouseInputEnabled(true)
    overlay:SetDrawOnTop(true)

    overlay.OnMousePressed = function(pnl, code)
        if code == MOUSE_LEFT then MG.OnLeftClick() end
    end

    overlay.Paint = function(pnl, w, h)
        if not MG.active or MG.sessionId ~= currentSession then return end
        MG.DrawOverlay(pnl, w, h)
    end

    MG.overlay = overlay
    gui.EnableScreenClicker(true)

    hook.Add("Think", "WoundSystem_SelfHarmInput", function()
        if not MG.IsActive() or MG.sessionId ~= currentSession then
            hook.Remove("Think", "WoundSystem_SelfHarmInput")
            return
        end
        MG.ThinkStep(FrameTime())
    end)

    hook.Add("OnScreenSizeChanged", "WoundSystem_SelfHarmResize", function()
        if IsValid(MG.overlay) then MG.overlay:SetSize(ScrW(), ScrH()) end
    end)

    hook.Add("ShutDown", "WoundSystem_SelfHarmCleanup", function()
        MG.Close("shutdown")
    end)
end

function MG.Close(reason)
    MG.active  = false
    MG.cutting = false

    hook.Remove("OnScreenSizeChanged", "WoundSystem_SelfHarmResize")
    hook.Remove("Think", "WoundSystem_SelfHarmInput")
    hook.Remove("ShutDown", "WoundSystem_SelfHarmCleanup")

    if IsValid(MG.overlay) then
        MG.overlay:Remove()
        MG.overlay = nil
    end

    gui.EnableScreenClicker(false)
end

function MG.StartCut()
    MG.cutTime  = 0.25
    MG.cutting  = true

    if not MG.isEye then
        local soundIdx = math.Clamp(MG.cutsDone + 1, 1, 3)
        surface.PlaySound("woundsystem/cut" .. soundIdx .. ".ogg")
    else
        surface.PlaySound("woundsystem/cuteye.ogg")
    end

    -- CAS3: Instantiate cut sprite at hand position, then Instantiate RedFlash on canvas
    table.insert(MG.cutSlashes, {
        x     = MG.handScreenX,
        y     = MG.handScreenY,
        angle = math.Rand(-25, 25),
        time  = CurTime()
    })

    -- CAS3: RedFlash spawned on canvas, Destroy after 0.35s
    MG.redFlashAlpha    = 200  -- start bright
    MG.redFlashBornAt   = CurTime()
    MG.redFlashDuration = 0.35

    MG.cutsLeft  = MG.cutsLeft - 1
    MG.cutsDone  = MG.cutsDone + 1
end

function MG.EndCut()
    MG.cutting = false
    if MG.cutsLeft <= 0 then
        local wasEye    = MG.isEye
        local cutsCount = MG.cutsDone

        MG.Close("completed")

        net.Start("WoundSystem_SelfHarmCompleted")
            net.WriteBool(wasEye)
            net.WriteInt(cutsCount, 8)
        net.SendToServer()
    else
        -- More cuts needed: reset resistance for next cut
        MG.triesLeft = 15
    end
end

function MG.ThinkStep(dt)
    dt = dt or FrameTime()

    -- CAS3 PhysicsUpdate: if Random.value < 0.4 -> handVelocity += Random.insideUnitCircle * 1f
    -- Scaled to pixels: *1 unity unit ≈ ~12px at standard resolution
    if math.random() < 0.4 then
        local angle = math.random() * math.pi * 2
        local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or math.min(ScrW() / 1920, ScrH() / 1080)
        MG.handScreenVelX = (MG.handScreenVelX or 0) + math.cos(angle) * (3 * scale)
        MG.handScreenVelY = (MG.handScreenVelY or 0) + math.sin(angle) * (3 * scale)
    end

    if MG.cutting then
        -- CAS3: handVelocity = Lerp(handVelocity, Vector2.down * 48f, 0.7f)
        -- 48 unity units/s downward ≈ 576 px/s at standard scale
        local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or math.min(ScrW() / 1920, ScrH() / 1080)
        MG.handScreenVelY = Lerp(0.7, MG.handScreenVelY or 0, 576 * scale)
        MG.cutTime = MG.cutTime - dt
        if MG.cutTime <= 0 then
            MG.EndCut()
        end
    elseif MG.isEye then
        -- CAS3: handPos lerp toward eye center (0, 360) proportional to progress
        local progress = math.Clamp((15 - MG.triesLeft) / 15, 0, 1)
        MG.handScreenX = Lerp(0.3 * progress, MG.handScreenX, ScrW() * 0.5)
        MG.handScreenY = Lerp(0.3 * progress, MG.handScreenY, ScrH() * 0.45)
    end

    HandPhysics.Step(MG, dt, {
        pain          = 0.15,
        str           = 5,
        conc          = 100,
        responsiveness = 6,
        followScale   = 0.3,
        relax         = 1.2
    })

    local mouseDown = input.IsMouseDown(MOUSE_LEFT)
    if mouseDown and not MG.lastMouseDown then
        MG.OnLeftClick()
    end
    MG.lastMouseDown = mouseDown
end

function MG.DrawOverlay(pnl, w, h)
    local now = CurTime()

    -- 1. Standard Minigame Backdrop
    if WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.DrawBackdrop then
        WoundSystem.MinigameClip.DrawBackdrop({ openTime = MG.openTime, alpha = 200, fadeTime = 0.2 })
    else
        surface.SetDrawColor(10, 8, 12, 230)
        surface.DrawRect(0, 0, w, h)
    end

    local filtered  = BeginPixelFilter()
    local clipActive = WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Begin()

    local s = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or math.min(w / 1920, h / 1080)
    local cx, cy = w * 0.5, h * 0.5

    -- Eye variant content
    if MG.isEye then
        local eyeSize = EYE_SRC_SIZE * s * 1.166  -- 3x smaller scale
        local eyeX = cx - eyeSize * 0.5
        local eyeY = cy * 0.9 - eyeSize * 0.5

        if MG.cutsDone > 0 then
            -- Eye gouged: show eyegone sprite, no pupil
            surface.SetMaterial(matEyeGone)
            surface.SetDrawColor(255, 255, 255, 255)
            surface.DrawTexturedRect(eyeX, eyeY, eyeSize, eyeSize)
        else
            -- Eye intact: static eye, jittering pupil on top
            surface.SetMaterial(matEye)
            surface.SetDrawColor(255, 255, 255, 255)
            surface.DrawTexturedRect(eyeX, eyeY, eyeSize, eyeSize)

            -- CAS3: pupil.localPosition = Random.insideUnitCircle * (15 - triesLeft) * 0.25 (2x smaller jitter)
            local jitMag = (15 - MG.triesLeft) * 0.25 * (eyeSize / EYE_SRC_SIZE)
            local angle  = math.random() * math.pi * 2
            local pupilX = math.cos(angle) * jitMag
            local pupilY = math.sin(angle) * jitMag

            surface.SetMaterial(matPupil)
            surface.SetDrawColor(255, 255, 255, 255)
            surface.DrawTexturedRect(cx + pupilX - eyeSize * 0.5, eyeY + pupilY, eyeSize, eyeSize)
        end
    end

    -- Completed slash marks — vertical scratch lines, anchored at top where cut started
    for _, slash in ipairs(MG.cutSlashes) do
        local slashW = 240 * s    -- 2x larger vertical scratch
        local slashH = 880 * s    -- 2x larger vertical scratch
        surface.SetMaterial(matDrag)
        surface.SetDrawColor(220, 20, 20, 200)
        local drawX = slash.x - slashW * 0.4527
        local drawY = slash.y - slashH * 0.0991
        surface.DrawTexturedRect(drawX, drawY, slashW, slashH)
    end

    -- Active cut stroke: vertical fill from top downward
    if MG.cutting then
        local fillAmt = math.Clamp(1.0 - MG.cutTime * 4.0, 0, 1)
        local slashW  = 240 * s
        local slashH  = 880 * s
        local drawX   = MG.handScreenX - slashW * 0.4527
        local drawY   = MG.handScreenY - slashH * 0.0991
        local visH    = slashH * fillAmt
        local visY    = drawY + (slashH - visH)
        surface.SetMaterial(matDrag)
        surface.SetDrawColor(240, 20, 20, 240)
        surface.DrawTexturedRectUV(drawX, visY, slashW, visH,
            0, 1 - fillAmt, 1, 1)
    end

    -- Resistance bar (not in CAS3 — our addition for player feedback)
    if MG.triesLeft > 0 and not MG.isEye then
        local progressPct = math.Clamp((15 - MG.triesLeft) / 15, 0, 1)
        local barW = 280 * s
        local barH = 10 * s
        local barX = cx - barW * 0.5
        local barY = cy + 200 * s

        surface.SetDrawColor(20, 20, 25, 180)
        surface.DrawRect(barX, barY, barW, barH)
        surface.SetDrawColor(220, 40, 40, 210)
        surface.DrawRect(barX, barY, barW * progressPct, barH)
    end

    -- Hand sprite (CAS3: SelfHarm=idle, SelfHarmForceOn=grab while cutting)
    local handMat = MG.cutting and matHandClick or matHandIdle
    local handW   = SRC_HAND_W * s * 1.5
    local handH   = SRC_HAND_H * s * 1.5
    local handX   = MG.handScreenX - handW * HAND_PIVOT_X
    local handY   = MG.handScreenY - handH * HAND_PIVOT_Y

    surface.SetMaterial(handMat)
    surface.SetDrawColor(255, 255, 255, 210)
    surface.DrawTexturedRect(handX, handY, handW, handH)

    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.End(clipActive)
    end
    EndPixelFilter(filtered)

    -- CAS3 RedFlash: fullscreen red rect, spawned on cut, fades over 0.35s
    -- Drawn OUTSIDE clip so it covers whole screen
    if MG.redFlashAlpha and MG.redFlashAlpha > 0 and MG.redFlashBornAt then
        local elapsed = now - MG.redFlashBornAt
        local fadeT   = math.Clamp(elapsed / MG.redFlashDuration, 0, 1)
        local alpha   = math.Clamp(MG.redFlashAlpha * (1 - fadeT), 0, 255)
        if alpha > 1 then
            surface.SetDrawColor(RED_FLASH_R, RED_FLASH_G, RED_FLASH_B, alpha)
            surface.DrawRect(0, 0, w, h)
        else
            MG.redFlashAlpha = 0
        end
    end
end

-- Network receiver from server
net.Receive("WoundSystem_StartSelfHarmMinigame", function()
    local cuts  = net.ReadInt(8)
    local isEye = net.ReadBool()
    WoundSystemSelfHarmMinigame.RequestStart(cuts, isEye)
end)

-- Console test command (client-side instant test)
concommand.Add("woundsystem_test_selfharm", function(ply, cmd, args)
    local cuts  = tonumber(args[1]) or 1
    local isEye = (args[2] == "1" or args[2] == "eye")
    WoundSystemSelfHarmMinigame.RequestStart(cuts, isEye)
end)
