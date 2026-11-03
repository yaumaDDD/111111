if WoundSystemDislocationMinigame and WoundSystemDislocationMinigame._Loaded then
    if IsValid(WoundSystemDislocationMinigame.overlay) then
        WoundSystemDislocationMinigame.overlay:Remove()
    end

    hook.Remove("OnScreenSizeChanged", "WoundSystem_DislocationResize")
    hook.Remove("Think", "WoundSystem_DislocationInput")
    hook.Remove("ShutDown", "WoundSystem_DislocationCleanup")
end

if not (WoundSystem and WoundSystem.MinigameClip) and file.Exists("woundsystem/client/minigames/cl_clip.lua", "LUA") then
    include("woundsystem/client/minigames/cl_clip.lua")
    include("woundsystem/client/minigames/sh_handphysics.lua")
end

local HandPhysics = include("woundsystem/client/minigames/sh_handphysics.lua")
local DevMinigameCfg = include("woundsystem/client/minigames/minigame_dev_config.lua") or {}

WoundSystemDislocationMinigame = WoundSystemDislocationMinigame or {}
local MG = WoundSystemDislocationMinigame
MG._Loaded = true

local path = "casunknown-images/dislocationminigame/"
local matBoneBase = Material(path .. "dislocationBoneBase.png")
local matBoneGhost = Material(path .. "dislocationBoneGhost.png")
local matBoneMove = Material(path .. "dislocationBoneMove.png")
local matHandIdle = Material(path .. "handgraspidle1.png")
local matHandClick = Material(path .. "handgraspclick.png")
local matWrenchIdle = Material(path .. "handWrenchIdle.png")
local matWrenchClick = Material(path .. "handWrenchClick.png")

local DEFAULT_CONFIG = {
    Scale = 0.8,
    CenterOffsetX = 0,
    CenterOffsetY = 0,

    BoneBaseWidth = 552,
    BoneBaseHeight = 324,
    BoneBaseOffsetX = -900,
    BoneBaseOffsetY = 0,
    BoneBaseRotation = 0,
    BoneBaseAlpha = 235,

    BoneGhostWidth = 1220,
    BoneGhostHeight = 356,
    BoneGhostOffsetX = -25,
    BoneGhostOffsetY = 0,
    BoneGhostRotation = 0,
    BoneGhostAlpha = 95,

    BoneMoveWidth = 1292,
    BoneMoveHeight = 480,
    BoneMoveOffsetX = 0,
    BoneMoveOffsetY = 0,
    BoneMoveRotation = 0,
    BoneMoveAlpha = 255,
    BoneHitboxWidthFactor = 2.4,
    BoneHitboxHeightFactor = .5,

    HandWidth = 512,
    HandHeight = 1260,
    HandScale = 3,
    HandOffsetX = 300,
    HandOffsetY = 1200,
    HandHitOffsetX = 0,
    HandHitOffsetY = 0,
    HandPivotX = 0.4,
    HandPivotY = 0.1,
    HandRotation = 0,
    HandAlpha = 210,

    PainShakeX = 120,
    PainShakeY = 40,
    HandMaxLength = 75,
    BoneVisualFollowSpeed = 16,
    HitPulseTime = 0.16
}

local FINISH_X = 421.82
local FINISH_Y = 229.82
local SIM_MIN_X = -500
local SIM_MAX_X = 900
local SIM_MIN_Y = -500
local SIM_MAX_Y = 500
local SEND_INTERVAL = 0.033
local BONE_DRAG = 6
local BONE_MOVE_MULT = 1.5
local HIT_MIN_HAND_SPEED = 4
local HIT_MAX_BONE_SPEED = 60

MG.active = MG.active or false
MG.sessionId = MG.sessionId or 0
MG.limbId = MG.limbId or nil
MG.hasWrench = MG.hasWrench or false
MG.overlay = MG.overlay or nil
MG.closeRequested = MG.closeRequested or false
MG.lastSentAt = MG.lastSentAt or 0
MG.lastSampleAt = MG.lastSampleAt or 0
MG.lastMouseDown = input.IsMouseDown(MOUSE_LEFT)
MG.lastRightDown = input.IsMouseDown(MOUSE_RIGHT)
MG.lastEscDown = input.IsKeyDown(KEY_ESCAPE)
MG.openTime = MG.openTime or 0
MG.boneX = MG.boneX or FINISH_X
MG.boneY = MG.boneY or FINISH_Y
MG.boneVelX = MG.boneVelX or 0
MG.boneVelY = MG.boneVelY or 0
MG.boneDrawX = MG.boneDrawX or FINISH_X
MG.boneDrawY = MG.boneDrawY or FINISH_Y
MG.dislocationTimer = MG.dislocationTimer or 100
MG.painBlocked = MG.painBlocked or false
MG.hitPulse = MG.hitPulse or 0
MG.handX = MG.handX or 0
MG.handY = MG.handY or 0
MG.lastHandX = MG.lastHandX or 0
MG.lastHandY = MG.lastHandY or 0
MG.handScreenX = MG.handScreenX or 0
MG.handScreenY = MG.handScreenY or 0
MG.handScreenVelX = MG.handScreenVelX or 0
MG.handScreenVelY = MG.handScreenVelY or 0
MG.handDrawX = MG.handDrawX or 0
MG.handDrawY = MG.handDrawY or 0
MG.handDrawW = MG.handDrawW or 0
MG.handDrawH = MG.handDrawH or 0
MG.sendPrevHandX = MG.sendPrevHandX or 0
MG.sendPrevHandY = MG.sendPrevHandY or 0
MG.sendPeakVelX = MG.sendPeakVelX or 0
MG.sendPeakVelY = MG.sendPeakVelY or 0
MG.scale = MG.scale or 1
MG._hp_acc = MG._hp_acc or 0
MG.predHitLocked = MG.predHitLocked or false
MG.inputSeq = MG.inputSeq or 0
MG.ackSeq = MG.ackSeq or 0
MG.lastLocalHitSoundAt = MG.lastLocalHitSoundAt or 0

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

local function DrawCentered(mat, x, y, w, h, rot, color)
    if not mat or mat:IsError() then return end
    surface.SetMaterial(mat)
    surface.SetDrawColor(color.r, color.g, color.b, color.a)
    surface.DrawTexturedRectRotated(math.Round(x), math.Round(y), math.Round(w), math.Round(h), rot or 0)
end

local function ConfigNumber(key, fallback)
    local section = DevMinigameCfg.dislocation
    local value = section and section[key]
    if value == nil then
        value = DevMinigameCfg["dislocation" .. key]
    end
    if value == nil then value = fallback end

    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function ClipRect()
    if WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.GetRect then
        return WoundSystem.MinigameClip.GetRect()
    end

    local size = ScrH() * 0.76
    return (ScrW() - size) * 0.5, (ScrH() - size) * 0.5, size, size, 38
end

local function RebuildMetrics()
    local _, _, clipW, clipH = ClipRect()
    -- the canvas is designed for a ~0.76 * screen height box: the fullscreen clip must not blow it up to the whole screen
    local refSize = ScrH() * 0.76
    clipW, clipH = math.min(clipW, refSize), math.min(clipH, refSize)
    MG.scale = math.min(clipW / 1500, clipH / 1100) * ConfigNumber("Scale", DEFAULT_CONFIG.Scale)
    MG.handDrawW = ConfigNumber("HandWidth", DEFAULT_CONFIG.HandWidth) * MG.scale * ConfigNumber("HandScale", DEFAULT_CONFIG.HandScale)
    MG.handDrawH = ConfigNumber("HandHeight", DEFAULT_CONFIG.HandHeight) * MG.scale * ConfigNumber("HandScale", DEFAULT_CONFIG.HandScale)
end

local function SimToScreen(x, y)
    local clipX, clipY, clipW, clipH = ClipRect()
    local cx = clipX + clipW * 0.5 + (ConfigNumber("CenterOffsetX", DEFAULT_CONFIG.CenterOffsetX) * MG.scale)
    local cy = clipY + clipH * 0.5 - (ConfigNumber("CenterOffsetY", DEFAULT_CONFIG.CenterOffsetY) * MG.scale)
    return cx + (x * MG.scale), cy - (y * MG.scale)
end

local function ScreenToSim(x, y)
    local clipX, clipY, clipW, clipH = ClipRect()
    local cx = clipX + clipW * 0.5 + (ConfigNumber("CenterOffsetX", DEFAULT_CONFIG.CenterOffsetX) * MG.scale)
    local cy = clipY + clipH * 0.5 - (ConfigNumber("CenterOffsetY", DEFAULT_CONFIG.CenterOffsetY) * MG.scale)
    return (x - cx) / MG.scale, (cy - y) / MG.scale
end

local function SegmentHitsRect(x1, y1, x2, y2, cx, cy, halfW, halfH)
    for step = 0, 6 do
        local t = step / 6
        local x = Lerp(t, x1 or x2 or 0, x2 or x1 or 0)
        local y = Lerp(t, y1 or y2 or 0, y2 or y1 or 0)
        if math.abs(x - cx) <= halfW and math.abs(y - cy) <= halfH then
            return true
        end
    end

    return false
end

local function UpdatePredictedBone(dt, isClicking, stoppedClick, handVelX, handVelY, prevHandX, prevHandY, hitOffsetX, hitOffsetY, hitHalfW, hitHalfH)
    local elapsed = math.Clamp(tonumber(dt) or 0, 0.001, 0.2)

    if stoppedClick or not isClicking then
        MG.predHitLocked = false
    end

    local dragT = math.Clamp(elapsed * BONE_DRAG, 0, 1)
    MG.boneX = math.Clamp((MG.boneX or FINISH_X) + ((MG.boneVelX or 0) * elapsed * BONE_MOVE_MULT), SIM_MIN_X, SIM_MAX_X)
    MG.boneY = math.Clamp((MG.boneY or FINISH_Y) + ((MG.boneVelY or 0) * elapsed * BONE_MOVE_MULT), SIM_MIN_Y, SIM_MAX_Y)
    MG.boneVelX = Lerp(dragT, MG.boneVelX or 0, 0)
    MG.boneVelY = Lerp(dragT, MG.boneVelY or 0, 0)

    local handSpeed = math.sqrt((handVelX or 0) * (handVelX or 0) + (handVelY or 0) * (handVelY or 0))
    local boneSpeed = math.sqrt((MG.boneVelX or 0) * (MG.boneVelX or 0) + (MG.boneVelY or 0) * (MG.boneVelY or 0))
    local hitBone = SegmentHitsRect(
        prevHandX,
        prevHandY,
        MG.handX,
        MG.handY,
        (MG.boneX or FINISH_X) + (hitOffsetX or 0),
        (MG.boneY or FINISH_Y) + (hitOffsetY or 0),
        hitHalfW or 0,
        hitHalfH or 0
    )

    if not MG.painBlocked
        and not MG.predHitLocked
        and isClicking
        and handSpeed >= HIT_MIN_HAND_SPEED
        and boneSpeed <= HIT_MAX_BONE_SPEED
        and hitBone then
        local hitMult = MG.hasWrench and 24 or 20
        MG.boneVelX = (MG.boneVelX or 0) + ((handVelX or 0) * hitMult)
        MG.boneVelY = (MG.boneVelY or 0) + ((handVelY or 0) * hitMult)
        MG.hitPulse = CurTime() + ConfigNumber("HitPulseTime", DEFAULT_CONFIG.HitPulseTime)
        MG.predHitLocked = true

        if CurTime() > (MG.lastLocalHitSoundAt or 0) + 0.08 then
            surface.PlaySound("boneHit.ogg")
            MG.lastLocalHitSoundAt = CurTime()
        end
    end

    local dx = (MG.boneX or FINISH_X) - FINISH_X
    local dy = (MG.boneY or FINISH_Y) - FINISH_Y
    MG.dislocationTimer = math.Clamp(math.sqrt(dx * dx + dy * dy) * 0.2, 0, 100)
end

local function UpdateHandDrawPosition()
    local offsetX = (DevMinigameCfg.dislocationHandOffsetX or ConfigNumber("HandOffsetX", DEFAULT_CONFIG.HandOffsetX)) * MG.scale
    local offsetY = (DevMinigameCfg.dislocationHandOffsetY or ConfigNumber("HandOffsetY", DEFAULT_CONFIG.HandOffsetY)) * MG.scale
    MG.handDrawX = MG.handScreenX - (MG.handDrawW * ConfigNumber("HandPivotX", DEFAULT_CONFIG.HandPivotX)) + offsetX
    MG.handDrawY = MG.handScreenY - (MG.handDrawH * ConfigNumber("HandPivotY", DEFAULT_CONFIG.HandPivotY)) + offsetY
end

local function GetHandGripScreenPos()
    local offsetX = ConfigNumber("HandHitOffsetX", DEFAULT_CONFIG.HandHitOffsetX) * MG.scale
    local offsetY = ConfigNumber("HandHitOffsetY", DEFAULT_CONFIG.HandHitOffsetY) * MG.scale
    return MG.handScreenX + offsetX,
        MG.handScreenY + offsetY
end

local function DestroyOverlay()
    if IsValid(MG.overlay) then
        MG.overlay:Remove()
    end
    MG.overlay = nil
end

local function LocalReset()
    MG.active = false
    MG.sessionId = 0
    MG.limbId = nil
    MG.hasWrench = false
    MG.closeRequested = false
    MG.lastSentAt = 0
    MG.lastSampleAt = 0
    MG.lastMouseDown = false
    MG.lastRightDown = false
    MG.lastEscDown = false
    MG.openTime = 0
    MG.boneX = FINISH_X
    MG.boneY = FINISH_Y
    MG.boneVelX = 0
    MG.boneVelY = 0
    MG.boneDrawX = FINISH_X
    MG.boneDrawY = FINISH_Y
    MG.dislocationTimer = 100
    MG.painBlocked = false
    MG.hitPulse = 0
    MG.handX = 0
    MG.handY = 0
    MG.lastHandX = 0
    MG.lastHandY = 0
    MG.handScreenX = ScrW() * 0.5
    MG.handScreenY = ScrH() * 0.5
    MG.handScreenVelX = 0
    MG.handScreenVelY = 0
    MG.sendPrevHandX = 0
    MG.sendPrevHandY = 0
    MG.sendPeakVelX = 0
    MG.sendPeakVelY = 0
    MG._hp_acc = 0
    MG.predHitLocked = false
    MG.inputSeq = 0
    MG.ackSeq = 0
    MG.lastLocalHitSoundAt = 0
    DestroyOverlay()
end

local function BeginClose()
    if not MG.active then return end
    MG.closeRequested = true
    LocalReset()
end

local function DrawScene()
    local clipActive = WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Begin(MG)

    local tx, ty = SimToScreen(FINISH_X, FINISH_Y)
    DrawCentered(
        matBoneGhost,
        tx + (ConfigNumber("BoneGhostOffsetX", DEFAULT_CONFIG.BoneGhostOffsetX) * MG.scale),
        ty - (ConfigNumber("BoneGhostOffsetY", DEFAULT_CONFIG.BoneGhostOffsetY) * MG.scale),
        ConfigNumber("BoneGhostWidth", DEFAULT_CONFIG.BoneGhostWidth) * MG.scale,
        ConfigNumber("BoneGhostHeight", DEFAULT_CONFIG.BoneGhostHeight) * MG.scale,
        ConfigNumber("BoneGhostRotation", DEFAULT_CONFIG.BoneGhostRotation),
        Color(255, 255, 255, ConfigNumber("BoneGhostAlpha", DEFAULT_CONFIG.BoneGhostAlpha))
    )
    DrawCentered(
        matBoneBase,
        tx + (ConfigNumber("BoneBaseOffsetX", DEFAULT_CONFIG.BoneBaseOffsetX) * MG.scale),
        ty - (ConfigNumber("BoneBaseOffsetY", DEFAULT_CONFIG.BoneBaseOffsetY) * MG.scale),
        ConfigNumber("BoneBaseWidth", DEFAULT_CONFIG.BoneBaseWidth) * MG.scale,
        ConfigNumber("BoneBaseHeight", DEFAULT_CONFIG.BoneBaseHeight) * MG.scale,
        ConfigNumber("BoneBaseRotation", DEFAULT_CONFIG.BoneBaseRotation),
        Color(255, 255, 255, ConfigNumber("BoneBaseAlpha", DEFAULT_CONFIG.BoneBaseAlpha))
    )

    local follow = math.Clamp(FrameTime() * ConfigNumber("BoneVisualFollowSpeed", DEFAULT_CONFIG.BoneVisualFollowSpeed), 0, 1)
    MG.boneDrawX = Lerp(follow, MG.boneDrawX or MG.boneX, MG.boneX or FINISH_X)
    MG.boneDrawY = Lerp(follow, MG.boneDrawY or MG.boneY, MG.boneY or FINISH_Y)

    local bx, by = SimToScreen(MG.boneDrawX, MG.boneDrawY)
    local pulseTime = math.max(ConfigNumber("HitPulseTime", DEFAULT_CONFIG.HitPulseTime), 0.01)
    local pulse = math.Clamp((MG.hitPulse or 0) - CurTime(), 0, pulseTime) / pulseTime
    local moveAlpha = ConfigNumber("BoneMoveAlpha", DEFAULT_CONFIG.BoneMoveAlpha)
    local tint = Color(255, 255, 255, moveAlpha)
    if pulse > 0 then
        tint = Color(255, 255 - pulse * 50, 255 - pulse * 80, moveAlpha)
    end
    DrawCentered(
        matBoneMove,
        bx + (ConfigNumber("BoneMoveOffsetX", DEFAULT_CONFIG.BoneMoveOffsetX) * MG.scale),
        by - (ConfigNumber("BoneMoveOffsetY", DEFAULT_CONFIG.BoneMoveOffsetY) * MG.scale),
        ConfigNumber("BoneMoveWidth", DEFAULT_CONFIG.BoneMoveWidth) * MG.scale,
        ConfigNumber("BoneMoveHeight", DEFAULT_CONFIG.BoneMoveHeight) * MG.scale,
        ConfigNumber("BoneMoveRotation", DEFAULT_CONFIG.BoneMoveRotation),
        tint
    )

    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.End(clipActive)
    end
end

local function DrawHand()
    local clicking = input.IsMouseDown(MOUSE_LEFT)
    local mat = clicking
        and (MG.hasWrench and matWrenchClick or matHandClick)
        or (MG.hasWrench and matWrenchIdle or matHandIdle)
    if not mat or mat:IsError() then return end

    local clipActive = WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Begin(MG)
    surface.SetMaterial(mat)
    local handAlpha = ConfigNumber("HandAlpha", DEFAULT_CONFIG.HandAlpha)
    if MG.painBlocked then
        surface.SetDrawColor(255, 115, 115, handAlpha)
    else
        surface.SetDrawColor(255, 255, 255, handAlpha)
    end
    local cx = MG.handDrawX + (MG.handDrawW * ConfigNumber("HandPivotX", DEFAULT_CONFIG.HandPivotX))
    local cy = MG.handDrawY + (MG.handDrawH * ConfigNumber("HandPivotY", DEFAULT_CONFIG.HandPivotY))
    surface.DrawTexturedRectRotated(math.Round(cx), math.Round(cy), math.Round(MG.handDrawW), math.Round(MG.handDrawH), HandPhysics.Rotation(MG, ConfigNumber("HandRotation", DEFAULT_CONFIG.HandRotation)))

    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.End(clipActive)
    end
end

local function DrawHeader()
    if not (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.DrawHeader) then return end

    WoundSystem.MinigameClip.DrawHeader({
        minigame = "dislocation",
        title = MG.hasWrench and "Wrench reduction" or "Fix dislocation",
        value = MG.painBlocked and "PAIN" or (tostring(math.Round(MG.dislocationTimer or 0)) .. "%"),
        curValue = math.max(100 - (MG.dislocationTimer or 100), 0),
        maxValue = 100,
        icon = "casunknown-images/icons/dislocatedbone.png",
        pw = 30,
        ph = 30,
        valueColor = MG.painBlocked and Color(255, 90, 90, 255) or nil
    })
end

local function EnsureOverlay()
    DestroyOverlay()
    RebuildMetrics()

    MG.overlay = vgui.Create("DPanel")
    MG.overlay:SetSize(ScrW(), ScrH())
    MG.overlay:SetPos(0, 0)
    MG.overlay:SetZPos(32000)
    MG.overlay:SetMouseInputEnabled(false)
    MG.overlay:SetKeyboardInputEnabled(false)
    MG.overlay:SetPaintBackground(false)

    MG.overlay.Paint = function()
        if not MG.active then return end
        if WoundSystem and WoundSystem.MinigameClip then
            WoundSystem.MinigameClip.DrawBackdrop(MG)
        end

        local filtered = BeginPixelFilter()
        DrawScene()
        EndPixelFilter(filtered)
    end

    MG.overlay.PaintOver = function()
        if not MG.active then return end
        local filtered = BeginPixelFilter()
        DrawHand()
        EndPixelFilter(filtered)
        DrawHeader()
        if WoundSystem and WoundSystem.MinigameClip then
            WoundSystem.MinigameClip.DrawExitGuide()
        end
    end
end

function MG.IsActive()
    return MG.active == true
end

concommand.Add("woundsys_dislocation_print_pos", function()
    if not MG.active then
        print("[WS DISLOC POS] minigame is not active")
        return
    end

    local boneScreenX, boneScreenY = SimToScreen(MG.boneX or FINISH_X, MG.boneY or FINISH_Y)
    local drawScreenX, drawScreenY = SimToScreen(MG.boneDrawX or MG.boneX or FINISH_X, MG.boneDrawY or MG.boneY or FINISH_Y)
    local finishScreenX, finishScreenY = SimToScreen(FINISH_X, FINISH_Y)
    local moveOffsetX = ConfigNumber("BoneMoveOffsetX", DEFAULT_CONFIG.BoneMoveOffsetX)
    local moveOffsetY = ConfigNumber("BoneMoveOffsetY", DEFAULT_CONFIG.BoneMoveOffsetY)

    print(string.format(
        "[WS DISLOC POS] bone=(%.2f, %.2f) draw=(%.2f, %.2f) finish=(%.2f, %.2f) moveOffset=(%.2f, %.2f)",
        MG.boneX or 0,
        MG.boneY or 0,
        MG.boneDrawX or 0,
        MG.boneDrawY or 0,
        FINISH_X,
        FINISH_Y,
        moveOffsetX,
        moveOffsetY
    ))
    print(string.format(
        "[WS DISLOC POS] screen bone=(%.1f, %.1f) draw=(%.1f, %.1f) finish=(%.1f, %.1f)",
        boneScreenX,
        boneScreenY,
        drawScreenX,
        drawScreenY,
        finishScreenX,
        finishScreenY
    ))
end)

function MG.RequestStart(limbId, slotIdx)
    if not limbId or limbId == "" then return end

    net.Start("WoundSystem_DislocationStart")
        net.WriteString(limbId)
        net.WriteUInt(slotIdx or 0, 3)
    net.SendToServer()
end

function MG.RequestClose(reason)
    if not MG.active or MG.closeRequested then return end
    MG.closeRequested = true

    net.Start("WoundSystem_DislocationClose")
        net.WriteUInt(MG.sessionId or 0, 24)
        net.WriteString(reason or "client_close")
    net.SendToServer()

    BeginClose()
end

net.Receive("WoundSystem_DislocationOpen", function()
    LocalReset()
    MG.active = true
    MG.sessionId = net.ReadUInt(24)
    MG.limbId = net.ReadString()
    MG.hasWrench = net.ReadBool()
    MG.boneX = net.ReadFloat()
    MG.boneY = net.ReadFloat()
    MG.boneVelX = net.ReadFloat()
    MG.boneVelY = net.ReadFloat()
    MG.dislocationTimer = net.ReadFloat()
    MG.painBlocked = net.ReadBool()
    MG.ackSeq = WoundSystem and WoundSystem.MinigameReadAck and WoundSystem.MinigameReadAck(0) or 0
    MG.boneDrawX = MG.boneX
    MG.boneDrawY = MG.boneY
    MG.openTime = CurTime()
    MG.lastSentAt = 0
    MG.lastMouseDown = input.IsMouseDown(MOUSE_LEFT)
    MG.lastRightDown = input.IsMouseDown(MOUSE_RIGHT)
    MG.lastEscDown = input.IsKeyDown(KEY_ESCAPE)

    local mx, my = gui.MousePos()
    if mx <= 0 and my <= 0 then
        mx, my = ScrW() * 0.5, ScrH() * 0.5
    end

    MG.handScreenX = mx
    MG.handScreenY = my
    RebuildMetrics()
    local gx, gy = GetHandGripScreenPos()
    MG.handX, MG.handY = ScreenToSim(gx, gy)
    MG.lastHandX = MG.handX
    MG.lastHandY = MG.handY
    MG.sendPrevHandX = MG.handX
    MG.sendPrevHandY = MG.handY
    MG.sendPeakVelX = 0
    MG.sendPeakVelY = 0
    UpdateHandDrawPosition()
    EnsureOverlay()
    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.MarkOpened(MG)
    end
end)

net.Receive("WoundSystem_DislocationState", function()
    local sessionId = net.ReadUInt(24)
    if not MG.active or sessionId ~= MG.sessionId then return end

    MG.boneX = net.ReadFloat()
    MG.boneY = net.ReadFloat()
    MG.boneVelX = net.ReadFloat()
    MG.boneVelY = net.ReadFloat()
    MG.dislocationTimer = net.ReadFloat()
    MG.painBlocked = net.ReadBool()
    if net.ReadBool() then
        MG.hitPulse = CurTime() + ConfigNumber("HitPulseTime", DEFAULT_CONFIG.HitPulseTime)
    end
    if WoundSystem and WoundSystem.MinigameAck then
        WoundSystem.MinigameAck(MG, WoundSystem.MinigameReadAck and WoundSystem.MinigameReadAck(0) or 0)
    end
end)

net.Receive("WoundSystem_DislocationClose", function()
    local sessionId = net.ReadUInt(24)
    net.ReadString()
    if not MG.active then return end
    if sessionId ~= MG.sessionId then return end
    BeginClose()
end)

net.Receive("WoundSystem_DislocationDebug", function()
    print(net.ReadString())
end)

hook.Add("OnScreenSizeChanged", "WoundSystem_DislocationResize", function(_, _)
    if not MG.active then return end
    EnsureOverlay()
    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.MarkOpened(MG)
    end
end)

hook.Add("Think", "WoundSystem_DislocationInput", function()
    if not MG.active then return end
    if not IsValid(MG.overlay) then
        EnsureOverlay()
    end

    if WoundSystemHealthHUDOpen == false then
        MG.RequestClose("hud_closed")
        return
    end

    local now = CurTime()
    local dt = math.max(now - (MG.lastSampleAt or now), 0.001)
    MG.lastSampleAt = now

    local state = WoundSystemClientState and WoundSystemClientState.PlayerLimbs and WoundSystemClientState.PlayerLimbs[MG.limbId]
    local painFactor = state and math.Clamp(tonumber(state.pain) or 0, 0, 100) / 100 or 0
    local stats = WoundSystemClientState and WoundSystemClientState.PlayerStats or nil
    local str = stats and stats.STR or 0
    local conc = stats and stats.consciousness or 100

    HandPhysics.Step(MG, dt, {
        pain = painFactor,
        str = str,
        conc = conc,
        shakeX = ConfigNumber("PainShakeX", DEFAULT_CONFIG.PainShakeX),
        shakeY = ConfigNumber("PainShakeY", DEFAULT_CONFIG.PainShakeY),
        maxLength = ConfigNumber("HandMaxLength", DEFAULT_CONFIG.HandMaxLength),
        positionScale = 120,
        bounds = {0, ScrW(), 0, ScrH()}
    })

    local gx, gy = GetHandGripScreenPos()
    MG.handX, MG.handY = ScreenToSim(gx, gy)
    MG.handX = math.Clamp(MG.handX, SIM_MIN_X, SIM_MAX_X)
    MG.handY = math.Clamp(MG.handY, SIM_MIN_Y, SIM_MAX_Y)
    local prevHandX = MG.lastHandX or MG.handX
    local prevHandY = MG.lastHandY or MG.handY
    local handVelX = (MG.handX - prevHandX) / math.max(dt * 60, 0.001)
    local handVelY = (MG.handY - prevHandY) / math.max(dt * 60, 0.001)
    MG.lastHandX = MG.handX
    MG.lastHandY = MG.handY
    UpdateHandDrawPosition()

    local handSpeedSq = handVelX * handVelX + handVelY * handVelY
    local peakSpeedSq = (MG.sendPeakVelX or 0) * (MG.sendPeakVelX or 0) + (MG.sendPeakVelY or 0) * (MG.sendPeakVelY or 0)
    if handSpeedSq > peakSpeedSq then
        MG.sendPeakVelX = handVelX
        MG.sendPeakVelY = handVelY
    end

    local isClicking = input.IsMouseDown(MOUSE_LEFT)
    local stoppedClick = (not isClicking) and MG.lastMouseDown
    MG.lastMouseDown = isClicking

    local boneHitOffsetX = ConfigNumber("BoneMoveOffsetX", DEFAULT_CONFIG.BoneMoveOffsetX)
    local boneHitOffsetY = ConfigNumber("BoneMoveOffsetY", DEFAULT_CONFIG.BoneMoveOffsetY)
    local boneHitHalfW = (ConfigNumber("BoneMoveWidth", DEFAULT_CONFIG.BoneMoveWidth) * ConfigNumber("BoneHitboxWidthFactor", DEFAULT_CONFIG.BoneHitboxWidthFactor)) * 0.5
    local boneHitHalfH = (ConfigNumber("BoneMoveHeight", DEFAULT_CONFIG.BoneMoveHeight) * ConfigNumber("BoneHitboxHeightFactor", DEFAULT_CONFIG.BoneHitboxHeightFactor)) * 0.5
    UpdatePredictedBone(dt, isClicking, stoppedClick, handVelX, handVelY, prevHandX, prevHandY, boneHitOffsetX, boneHitOffsetY, boneHitHalfW, boneHitHalfH)

    local rightDown = input.IsMouseDown(MOUSE_RIGHT)
    local escDown = input.IsKeyDown(KEY_ESCAPE)
    local startedRight = rightDown and not MG.lastRightDown
    local startedEsc = escDown and not MG.lastEscDown
    MG.lastRightDown = rightDown
    MG.lastEscDown = escDown

    if (startedRight or startedEsc) and (CurTime() - (MG.openTime or 0) > 0.2) then
        if startedEsc then gui.HideGameUI() end
        MG.RequestClose("user_cancel")
        return
    end

    if MG.closeRequested then return end
    if now - (MG.lastSentAt or 0) < SEND_INTERVAL then return end
    MG.lastSentAt = now

    local sendVelX = MG.sendPeakVelX or handVelX
    local sendVelY = MG.sendPeakVelY or handVelY
    net.Start("WoundSystem_DislocationInput")
        net.WriteUInt(MG.sessionId or 0, 24)
        net.WriteFloat(MG.handX)
        net.WriteFloat(MG.handY)
        net.WriteFloat(sendVelX)
        net.WriteFloat(sendVelY)
        net.WriteBool(isClicking)
        net.WriteBool(stoppedClick)
        net.WriteFloat(MG.sendPrevHandX or MG.handX)
        net.WriteFloat(MG.sendPrevHandY or MG.handY)
        net.WriteFloat(boneHitOffsetX)
        net.WriteFloat(boneHitOffsetY)
        net.WriteFloat(boneHitHalfW)
        net.WriteFloat(boneHitHalfH)
        net.WriteUInt(WoundSystem and WoundSystem.MinigameNextInputSeq and WoundSystem.MinigameNextInputSeq(MG) or 0, 24)
    net.SendToServer()

    MG.sendPrevHandX = MG.handX
    MG.sendPrevHandY = MG.handY
    MG.sendPeakVelX = 0
    MG.sendPeakVelY = 0
end)

hook.Add("ShutDown", "WoundSystem_DislocationCleanup", function()
    DestroyOverlay()
end)
