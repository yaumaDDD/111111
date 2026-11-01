if WoundSystemSyringeMinigame and WoundSystemSyringeMinigame._Loaded then return end

if not (WoundSystem and WoundSystem.MinigameClip) and file.Exists("woundsystem/client/minigames/cl_clip.lua", "LUA") then
    include("woundsystem/client/minigames/cl_clip.lua")
    include("woundsystem/client/minigames/sh_handphysics.lua")
end
local HandPhysics = include("woundsystem/client/minigames/sh_handphysics.lua")

local function DrawRectInt(x, y, w, h)
    surface.DrawTexturedRect(math.Round(tonumber(x) or 0), math.Round(tonumber(y) or 0), math.Round(tonumber(w) or 0), math.Round(tonumber(h) or 0))
end

local function DrawRectUVInt(x, y, w, h, u1, v1, u2, v2)
    surface.DrawTexturedRectUV(math.Round(tonumber(x) or 0), math.Round(tonumber(y) or 0), math.Round(tonumber(w) or 0), math.Round(tonumber(h) or 0), u1, v1, u2, v2)
end

local function RotateLocal(x, y, angle)
    local rad = math.rad(angle or 0)
    local c = math.cos(rad)
    local s = math.sin(rad)
    return (x * c) - (y * s), (x * s) + (y * c)
end

local function DrawPivotedRect(pivotX, pivotY, localX, localY, w, h, angle)
    local halfW = w * 0.5
    local halfH = h * 0.5
    local points = {
        { x = localX - halfW, y = localY - halfH, u = 0, v = 0 },
        { x = localX + halfW, y = localY - halfH, u = 1, v = 0 },
        { x = localX + halfW, y = localY + halfH, u = 1, v = 1 },
        { x = localX - halfW, y = localY + halfH, u = 0, v = 1 }
    }

    for _, point in ipairs(points) do
        local ox, oy = RotateLocal(point.x, point.y, angle)
        point.x = pivotX + ox
        point.y = pivotY + oy
    end

    surface.DrawPoly(points)
end

local function DrawPivotedUVRect(pivotX, pivotY, localX, localY, w, h, angle, u1, v1, u2, v2)
    local halfW = w * 0.5
    local halfH = h * 0.5
    local points = {
        { x = localX - halfW, y = localY - halfH, u = u1, v = v1 },
        { x = localX + halfW, y = localY - halfH, u = u2, v = v1 },
        { x = localX + halfW, y = localY + halfH, u = u2, v = v2 },
        { x = localX - halfW, y = localY + halfH, u = u1, v = v2 }
    }

    for _, point in ipairs(points) do
        local ox, oy = RotateLocal(point.x, point.y, angle)
        point.x = pivotX + ox
        point.y = pivotY + oy
    end

    surface.DrawPoly(points)
end

local path = "casunknown-images/syringeminigame/"
-- legacy sprite filename, shared with the glass shard minigame (no shrapnel mechanic)
local matBackground = Material(path .. "minigameshrapnel.png")
local matSyringe = Material(path .. "minigameSyringe.png")
local matFill = Material(path .. "minigameSyringeFill.png")
local matHandIdle = Material(path .. "handgraspidle1.png")
local matHandClick = Material(path .. "handgraspclick.png")

WoundSystemSyringeMinigame = WoundSystemSyringeMinigame or {}
local MG = WoundSystemSyringeMinigame
MG._Loaded = true

local SRC_BG_W = 200
local SRC_BG_H = 128
local SRC_SYRINGE_W = 30
local SRC_SYRINGE_H = 164
local SRC_FILL_W = 20
local SRC_FILL_H = 78
local SRC_HAND_W = 512
local SRC_HAND_H = 1260

local GetActiveItem

local DEFAULT_MINIGAME = {
    syringeStartX = 0,
    syringeStartY = -150,
    skinY = -180,
    stopY = -273,
    syringeScale = 2,
    syringePivotX = 0.5,
    syringePivotY = 1,
    syringeDrawOffsetY = -670,
    fillOffsetX = 5,
    fillOffsetY = 33,
    boardOffsetY = 600,
    boardExtraHeight = 500,
    boardMinWidth = 320,
    boardMinHeight = 220,
    boardScaleBaseHeight = 720,
    boardScaleMultiplier = 0.8,
    boardMinScale = 0.45,
    ClipBackgroundEnabled = true,
    ClipBackgroundAlpha = 200,
    ClipBackgroundFadeTime = 0.2,
    frontLayerY = 300,
    frontLayerAlpha = 255,
    handScale = 0.85,
    handPivotX = 0.4,
    handPivotY = 0.1,
    handOffsetX = 40,
    handOffsetY = 0,
    handIdleAngle = 290,
    handHoldAngle = 290,
    handAlpha = 153,
    grabHalfWidth = 45,
    grabBelowTip = 35,
    grabAboveTip = 368,
    breakSideForce = 80,
    rotationDirection = -1,
    rotationPerSideForce = 0.125,
    maxRotation = 20,
    sendInterval = 0.05,
    painTensionLow = 45,
    painTensionHigh = 250,
    painDampingLow = 2,
    painDampingHigh = 14,
    painShakeX = 140,
    painShakeY = 40,
    painShakeSpeed = 0.8
}

local function GetMinigameOptions()
    local item = GetActiveItem and GetActiveItem()
    local syringe = item and item.use and item.use.syringe
    if type(syringe) ~= "table" then return nil end

    if type(syringe.minigame) == "table" then return syringe.minigame end
    if type(syringe.visuals) == "table" then return syringe.visuals end
    if type(syringe.ui) == "table" then return syringe.ui end
    return nil
end

local function MiniValue(keys, fallback)
    local options = GetMinigameOptions()
    if type(keys) ~= "table" then keys = { keys } end

    if type(options) == "table" then
        for _, key in ipairs(keys) do
            if options[key] ~= nil then return options[key] end
        end
    end

    return fallback
end

local function MiniNumber(keys, fallback)
    local value = MiniValue(keys, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

MG.active = MG.active or false
MG.sessionId = MG.sessionId or 0
MG.limbId = MG.limbId or nil
MG.slotIdx = MG.slotIdx or nil
MG.itemId = MG.itemId or nil
MG.condition = MG.condition or 1
MG.overlay = MG.overlay or nil
MG.board = MG.board or nil
MG.closeRequested = MG.closeRequested or false
MG.lastMouseDown = input.IsMouseDown(MOUSE_LEFT)
MG.lastRightDown = input.IsMouseDown(MOUSE_RIGHT)
MG.lastEscDown = input.IsKeyDown(KEY_ESCAPE)
MG.openTime = MG.openTime or 0
MG.lastSampleAt = MG.lastSampleAt or 0
MG.lastSentAt = MG.lastSentAt or 0
MG.handScreenX = MG.handScreenX or 0
MG.handScreenY = MG.handScreenY or 0
MG.handScreenVelX = MG.handScreenVelX or 0
MG.handScreenVelY = MG.handScreenVelY or 0
MG.handX = MG.handX or 0
MG.handY = MG.handY or 0
MG.handDrawX = MG.handDrawX or 0
MG.handDrawY = MG.handDrawY or 0
MG.handPivotScreenX = MG.handPivotScreenX or 0
MG.handPivotScreenY = MG.handPivotScreenY or 0
MG.handDrawPivotX = MG.handDrawPivotX or DEFAULT_MINIGAME.handPivotX
MG.handDrawPivotY = MG.handDrawPivotY or DEFAULT_MINIGAME.handPivotY
MG.handDrawAngle = MG.handDrawAngle or 0
MG.syringeX = MG.syringeX or DEFAULT_MINIGAME.syringeStartX
MG.syringeY = MG.syringeY or DEFAULT_MINIGAME.syringeStartY
MG.syringeAngle = MG.syringeAngle or 0
MG.lastXPos = MG.lastXPos or 0
MG.holdingSyringe = MG.holdingSyringe or false
MG.holdOffsetX = MG.holdOffsetX or 0
MG.holdOffsetY = MG.holdOffsetY or 0
MG.wasInjectingBefore = MG.wasInjectingBefore or false
MG.breakSent = MG.breakSent or false
MG.loopStation = MG.loopStation or nil
MG.scale = MG.scale or 0.8
MG.boardW = MG.boardW or 0
MG.boardH = MG.boardH or 0
MG.handDrawW = MG.handDrawW or 0
MG.handDrawH = MG.handDrawH or 0
MG.inputSeq = MG.inputSeq or 0
MG.ackSeq = MG.ackSeq or 0

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

local function UpdateHandDrawPosition()
    local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
    local handPivotX = MiniNumber("handPivotX", DEFAULT_MINIGAME.handPivotX)
    local handPivotY = MiniNumber("handPivotY", DEFAULT_MINIGAME.handPivotY)
    local handOffsetX = MiniNumber("handOffsetX", DEFAULT_MINIGAME.handOffsetX) * scale
    local handOffsetY = MiniNumber("handOffsetY", DEFAULT_MINIGAME.handOffsetY) * scale

    MG.handPivotScreenX = MG.handScreenX + handOffsetX
    MG.handPivotScreenY = MG.handScreenY + handOffsetY
    MG.handDrawX = MG.handPivotScreenX - (MG.handDrawW * handPivotX)
    MG.handDrawY = MG.handPivotScreenY - (MG.handDrawH * handPivotY)
    MG.handDrawPivotX = handPivotX
    MG.handDrawPivotY = handPivotY
    local idleAngle = MiniNumber({"handIdleAngle", "handAngle"}, DEFAULT_MINIGAME.handIdleAngle)
    local holdAngle = MiniNumber({"handHoldAngle", "handAngle"}, idleAngle)
    if HandPhysics then
        MG.handDrawAngle = HandPhysics.Rotation(MG, MG.holdingSyringe and holdAngle or idleAngle)
    else
        MG.handDrawAngle = MG.holdingSyringe and holdAngle or idleAngle
    end
end

local function RebuildBoardMetrics()
    local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
    
    MG.scale = scale * 1.537
    MG.boardW = 1382 * scale
    MG.boardH = 1384 * scale

    MG.handDrawW = SRC_HAND_W * MG.scale * MiniNumber("handScale", DEFAULT_MINIGAME.handScale)
    MG.handDrawH = SRC_HAND_H * MG.scale * MiniNumber("handScale", DEFAULT_MINIGAME.handScale)
    UpdateHandDrawPosition()
end

local function ScreenToSim(x, y)
    if not IsValid(MG.board) then return 0, 0 end
    local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
    local lx, ly = MG.board:ScreenToLocal(x, y)
    local sx = (lx - MG.board:GetWide() * 0.5) / MG.scale
    local sy = -((ly - MG.board:GetTall() * 0.5 - (MiniNumber({"syringeDrawOffsetY", "drawOffsetY"}, DEFAULT_MINIGAME.syringeDrawOffsetY) * scale)) / MG.scale)
    return sx, sy
end

local function SimToScreen(x, y)
    if not IsValid(MG.board) then return ScrW() * 0.5, ScrH() * 0.5 end
    local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
    local lx = MG.board:GetWide() * 0.5 + (x * MG.scale)
    local ly = MG.board:GetTall() * 0.5 - (y * MG.scale) + (MiniNumber({"syringeDrawOffsetY", "drawOffsetY"}, DEFAULT_MINIGAME.syringeDrawOffsetY) * scale)
    return MG.board:LocalToScreen(lx, ly)
end

local function StopLoop()
    if IsValid(MG.loopStation) then
        MG.loopStation:Stop()
        MG.loopStation = nil
        if WoundSystem.BroadcastMinigameSound then
            WoundSystem.BroadcastMinigameSound("syringeloop.ogg", 0.5, true, true)
        end
    end
end

local function EnsureLoop()
    if IsValid(MG.loopStation) then return end

    sound.PlayFile("sound/syringeloop.ogg", "noblock noplay 2d", function(station)
        if not IsValid(station) then return end
        if not MG.active then
            station:Stop()
            return
        end

        MG.loopStation = station
        station:EnableLooping(true)
        station:SetVolume(0)
        station:Play()
        MG.loopStation = station
        if WoundSystem.BroadcastMinigameSound then
            WoundSystem.BroadcastMinigameSound("syringeloop.ogg", 0.5, true, false)
        end
    end)
end

local function SetLoopVolume(volume)
    volume = math.Clamp(tonumber(volume) or 0, 0, 1)
    if volume > 0 then EnsureLoop() end
    if IsValid(MG.loopStation) then
        MG.loopStation:SetVolume(volume * 0.85)
        MG.loopStation:SetPlaybackRate(1.6 - math.Clamp(MG.condition or 1, 0, 1))
    end
end

local function DestroyOverlay()
    if IsValid(MG.overlay) then MG.overlay:Remove() end
    MG.overlay = nil
    MG.board = nil
end

local function LocalReset()
    if MG.externalClicker then
        MG.externalClicker = false
        if WoundSystem and WoundSystem.HealthGUI and WoundSystem.HealthGUI.SetScreenClickerOwned and not WoundSystemHealthHUDOpen then
            WoundSystem.HealthGUI.SetScreenClickerOwned(false, "zcity_swep_syringe_end")
        end
    end

    MG.active = false
    MG.sessionId = 0
    MG.limbId = nil
    MG.slotIdx = nil
    MG.itemId = nil
    MG.condition = 1
    MG.closeRequested = false
    MG.lastMouseDown = false
    MG.lastRightDown = false
    MG.lastEscDown = false
    MG.openTime = 0
    MG.lastSampleAt = 0
    MG.lastSentAt = 0
    MG.handScreenX = 0
    MG.handScreenY = 0
    MG.handScreenVelX = 0
    MG.handScreenVelY = 0
    MG.handX = 0
    MG.handY = 0
    MG.handDrawX = 0
    MG.handDrawY = 0
    MG.handPivotScreenX = 0
    MG.handPivotScreenY = 0
    MG.handDrawPivotX = DEFAULT_MINIGAME.handPivotX
    MG.handDrawPivotY = DEFAULT_MINIGAME.handPivotY
    MG.handDrawAngle = 0
    MG.syringeX = DEFAULT_MINIGAME.syringeStartX
    MG.syringeY = DEFAULT_MINIGAME.syringeStartY
    MG.syringeAngle = 0
    MG.lastXPos = 0
    MG.holdingSyringe = false
    MG.holdOffsetX = 0
    MG.holdOffsetY = 0
    MG.wasInjectingBefore = false
    MG.breakSent = false
    MG.boardW = 0
    MG.boardH = 0
    MG.handDrawW = 0
    MG.handDrawH = 0
    MG._hp_acc = 0
    MG.inputSeq = 0
    MG.ackSeq = 0
    StopLoop()
    DestroyOverlay()
end

local function BeginClose()
    if not MG.active then return end
    MG.closeRequested = true
    LocalReset()
end

GetActiveItem = function()
    local itemId = MG.itemId or ""
    if WoundSystem and WoundSystem.Items and WoundSystem.Items.Get then
        local item = WoundSystem.Items.Get(itemId)
        if item then return item end
    end

    return WoundSystemMedToolConfig and WoundSystemMedToolConfig[itemId] or nil
end

local function ToColor(value, fallback)
    fallback = fallback or Color(0, 132, 173, 255)
    if IsColor and IsColor(value) then return value end
    if type(value) ~= "table" then return fallback end

    return Color(
        value.r or value[1] or fallback.r,
        value.g or value[2] or fallback.g,
        value.b or value[3] or fallback.b,
        value.a or value[4] or fallback.a or 255
    )
end

local function GetSyringeFillColor()
    local item = GetActiveItem()
    local syringe = item and item.use and item.use.syringe
    return ToColor(type(syringe) == "table" and syringe.color or nil, Color(0, 132, 173, 255))
end

local function GetSyringeDurabilityRate()
    local item = GetActiveItem()
    local syringe = item and item.use and item.use.syringe
    if type(syringe) == "table" and tonumber(syringe.durabilityPerSecond) then
        return math.max(tonumber(syringe.durabilityPerSecond), 0)
    end

    return 18
end

local function DrawMinigameHeader()
    if not (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.DrawHeader) then return end

    local slot = MG.slotIdx and WoundSystemInventorySlots and WoundSystemInventorySlots[MG.slotIdx]
    local item = GetActiveItem()
    local maxDur = item and item.max or 100
    local curDur = slot and slot.durability or ((MG.condition or 0) * maxDur)
    local durPct = math.Round(math.Clamp(curDur / math.max(maxDur, 1), 0, 1) * 100)

    WoundSystem.MinigameClip.DrawHeader({
        minigame = "syringe",
        title = item and item.title or MG.itemId or "Syringe",
        value = durPct .. "%",
        curValue = curDur,
        maxValue = maxDur,
        mat = slot and slot.mat,
        icon = item and item.icon,
        pw = (slot and slot.pw) or (item and item.pw),
        ph = (slot and slot.ph) or (item and item.ph)
    })
end

local function SendInput(depth, brokeNeedle)
    if not MG.active or MG.closeRequested then return end
    net.Start("WoundSystem_SyringeInput")
    net.WriteUInt(MG.sessionId or 0, 24)
    net.WriteFloat(math.Clamp(depth or 0, 0, 1))
    net.WriteBool(brokeNeedle == true)
    net.WriteUInt(WoundSystem and WoundSystem.MinigameNextInputSeq and WoundSystem.MinigameNextInputSeq(MG) or 0, 24)
    net.SendToServer()
    MG.lastSentAt = CurTime()
end

local function DrawSyringe()
    if not IsValid(MG.board) then return end

    local syringeScale = MiniNumber("syringeScale", DEFAULT_MINIGAME.syringeScale)
    local scale = MG.scale * syringeScale
    local filtered = BeginPixelFilter()
    local clipActive = WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Begin()

    local pivotX, pivotY = SimToScreen(MG.syringeX, MG.syringeY)
    local syringeW = SRC_SYRINGE_W * scale
    local syringeH = SRC_SYRINGE_H * scale
    local fillW = SRC_FILL_W * scale
    local fillH = SRC_FILL_H * scale
    local fillAmount = math.Clamp(MG.condition or 0, 0, 1)
    local angle = MG.syringeAngle or 0
    local pivotFracX = MiniNumber({"syringePivotX", "pivotX"}, DEFAULT_MINIGAME.syringePivotX)
    local pivotFracY = MiniNumber({"syringePivotY", "pivotY"}, DEFAULT_MINIGAME.syringePivotY)
    local syringeLeft = -pivotFracX * syringeW
    local syringeTop = -pivotFracY * syringeH
    local syringeCenterX = syringeLeft + syringeW * 0.5
    local syringeCenterY = syringeTop + syringeH * 0.5

    surface.SetMaterial(matFill)
    local fillColor = GetSyringeFillColor()
    surface.SetDrawColor(fillColor.r, fillColor.g, fillColor.b, math.min(fillColor.a or 255, 245))
    local fillDrawH = fillH * fillAmount
    if fillDrawH > 1 then
        local fillLocalX = syringeLeft + (MiniNumber("fillOffsetX", DEFAULT_MINIGAME.fillOffsetX) * scale) + fillW * 0.5
        local fillLocalY = syringeTop + (MiniNumber("fillOffsetY", DEFAULT_MINIGAME.fillOffsetY) * scale) + fillH - (fillDrawH * 0.5)
        DrawPivotedUVRect(pivotX, pivotY, fillLocalX, fillLocalY, fillW, fillDrawH, angle, 0, 1 - fillAmount, 1, 1)
    end

    surface.SetMaterial(matSyringe)
    surface.SetDrawColor(255, 255, 255, 255)
    DrawPivotedRect(pivotX, pivotY, syringeCenterX, syringeCenterY, syringeW, syringeH, angle)

    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.End(clipActive)
    end
    EndPixelFilter(filtered)
end

local function DrawHand()
    local handMat = MG.holdingSyringe and matHandClick or matHandIdle
    local pivotX = MG.handPivotScreenX or MG.handScreenX
    local pivotY = MG.handPivotScreenY or MG.handScreenY
    local localX = (0.5 - (MG.handDrawPivotX or DEFAULT_MINIGAME.handPivotX)) * MG.handDrawW
    local localY = (0.5 - (MG.handDrawPivotY or DEFAULT_MINIGAME.handPivotY)) * MG.handDrawH

    local filtered = BeginPixelFilter()
    local clipActive = WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Begin()
    surface.SetMaterial(handMat)
    surface.SetDrawColor(255, 255, 255, MiniNumber("handAlpha", DEFAULT_MINIGAME.handAlpha))
    DrawPivotedRect(pivotX, pivotY, localX, localY, MG.handDrawW, MG.handDrawH, MG.handDrawAngle or 0)
    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.End(clipActive)
    end
    EndPixelFilter(filtered)
end

local function EnsureOverlay()
    DestroyOverlay()
    RebuildBoardMetrics()

    MG.overlay = vgui.Create("DPanel")
    MG.overlay:SetSize(ScrW(), ScrH())
    MG.overlay:SetPos(0, 0)
    MG.overlay:SetZPos(32000)
    MG.overlay:SetMouseInputEnabled(false)
    MG.overlay:SetKeyboardInputEnabled(false)
    MG.overlay:SetPaintBackground(false)

    MG.overlay.Paint = function()
        if not MG.active then return end
        if not IsValid(MG.board) then return end

        if MiniValue("ClipBackgroundEnabled", DEFAULT_MINIGAME.ClipBackgroundEnabled) ~= false
            and WoundSystem
            and WoundSystem.MinigameClip
            and WoundSystem.MinigameClip.DrawBackdrop then
            WoundSystem.MinigameClip.DrawBackdrop({
                openTime = MG.openTime,
                alpha = MiniNumber("ClipBackgroundAlpha", DEFAULT_MINIGAME.ClipBackgroundAlpha),
                fadeTime = MiniNumber("ClipBackgroundFadeTime", DEFAULT_MINIGAME.ClipBackgroundFadeTime)
            })
        end

        DrawSyringe()

        local bx, by = MG.board:GetPos()
        local filtered = BeginPixelFilter()
        local clipActive = WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Begin()
        local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
        surface.SetMaterial(matBackground)
        surface.SetDrawColor(255, 255, 255, MiniNumber("frontLayerAlpha", DEFAULT_MINIGAME.frontLayerAlpha))
        DrawRectInt(bx, by + (MiniNumber("frontLayerY", DEFAULT_MINIGAME.frontLayerY) * scale), MG.boardW, MG.boardH)
        if WoundSystem and WoundSystem.MinigameClip then
            WoundSystem.MinigameClip.End(clipActive)
        end
        EndPixelFilter(filtered)
    end

    MG.overlay.PaintOver = function()
        if not MG.active then return end
        DrawHand()
        DrawMinigameHeader()
        WoundSystem.MinigameClip.DrawExitGuide()
    end

    MG.board = vgui.Create("DPanel", MG.overlay)
    MG.board:SetSize(MG.boardW, MG.boardH)
    MG.board:Center()
    do
        local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
        local bx, by = MG.board:GetPos()
        MG.board:SetPos(bx, by + (MiniNumber("boardOffsetY", DEFAULT_MINIGAME.boardOffsetY) * scale))
    end
    MG.board:SetMouseInputEnabled(false)
    MG.board:SetKeyboardInputEnabled(false)

    MG.board.Paint = function(_, w, h)
        if not MG.active then return end
    end
end

function MG.IsActive()
    return MG.active == true
end

function MG.RequestStart(limbId, slotIdx)
    MG.slotIdx = slotIdx
    net.Start("WoundSystem_SyringeStart")
    net.WriteString(limbId)
    net.WriteUInt(slotIdx or 0, 3)
    net.SendToServer()
end

function MG.RequestClose(reason)
    if not MG.active or MG.closeRequested then return end
    MG.closeRequested = true
    net.Start("WoundSystem_SyringeClose")
    net.WriteUInt(MG.sessionId or 0, 24)
    net.WriteString(reason or "client_close")
    net.SendToServer()
    BeginClose()
end

net.Receive("WoundSystem_SyringeOpen", function()
    LocalReset()
    MG.active = true
    MG.sessionId = net.ReadUInt(24)
    MG.limbId = net.ReadString()
    MG.slotIdx = net.ReadUInt(3)
    MG.itemId = net.ReadString()
    MG.condition = net.ReadFloat()
    MG.openTime = CurTime()
    MG.lastMouseDown = input.IsMouseDown(MOUSE_LEFT)
    MG.lastRightDown = input.IsMouseDown(MOUSE_RIGHT)
    MG.lastEscDown = input.IsKeyDown(KEY_ESCAPE)

    if MG.slotIdx == 6 and WoundSystem.HealthGUI and WoundSystem.HealthGUI.SetScreenClickerOwned then
        MG.externalClicker = true
        WoundSystem.HealthGUI.SetScreenClickerOwned(true, "zcity_swep_syringe")
    end

    EnsureOverlay()

    local mx, my = gui.MousePos()
    if mx <= 0 and my <= 0 then
        mx, my = ScrW() * 0.5, ScrH() * 0.5
    end
    MG.handScreenX = mx
    MG.handScreenY = my
    MG.handX, MG.handY = ScreenToSim(mx, my)
    MG.syringeX = MiniNumber({"syringeStartX", "startX"}, DEFAULT_MINIGAME.syringeStartX)
    MG.syringeY = MiniNumber({"syringeStartY", "startY"}, DEFAULT_MINIGAME.syringeStartY)
    MG.lastXPos = MG.syringeX
    MG.lastSampleAt = CurTime()
    MG.lastSentAt = CurTime()
    UpdateHandDrawPosition()

    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.MarkOpened(MG)
    end
end)

net.Receive("WoundSystem_SyringeState", function()
    local sessionId = net.ReadUInt(24)
    local condition = net.ReadFloat()
    local ackSeq = WoundSystem and WoundSystem.MinigameReadAck and WoundSystem.MinigameReadAck(0) or 0
    if not MG.active or sessionId ~= MG.sessionId then return end
    MG.condition = math.Clamp(condition, 0, 1)
    if WoundSystem and WoundSystem.MinigameAck then
        WoundSystem.MinigameAck(MG, ackSeq)
    end
end)

net.Receive("WoundSystem_SyringeClose", function()
    local sessionId = net.ReadUInt(24)
    net.ReadString()
    if not MG.active or sessionId ~= MG.sessionId then return end
    LocalReset()
end)

hook.Add("Think", "WoundSystem_SyringeInput", function()
    if not MG.active then return end
    if not IsValid(MG.overlay) or not IsValid(MG.board) then
        EnsureOverlay()
        if not IsValid(MG.board) then return end
    end

    -- slot 6 = minigame started by a Z-City SWEP: it does not need the health HUD
    if WoundSystemHealthHUDOpen == false and MG.slotIdx ~= 6 then
        MG.RequestClose("hud_closed")
        return
    end

    local now = CurTime()
    local dt = math.max(now - (MG.lastSampleAt or now), 0.001)

    local mx, my = gui.MousePos()
    if mx <= 0 and my <= 0 then mx, my = ScrW() * 0.5, ScrH() * 0.5 end

    local state = WoundSystemClientState and WoundSystemClientState.PlayerLimbs and WoundSystemClientState.PlayerLimbs[MG.limbId]
    local painFactor = 0
    if state and state.pain then
        painFactor = math.Clamp(state.pain, 0, 100) / 100
    end

    local stats = WoundSystemClientState and WoundSystemClientState.PlayerStats or nil
    local str = stats and stats.STR or 0
    local conc = stats and stats.consciousness or 100

    HandPhysics.Step(MG, dt, {
        pain = painFactor,
        str = str,
        conc = conc,
        shakeX = MiniNumber("painShakeX", DEFAULT_MINIGAME.painShakeX),
        shakeY = MiniNumber("painShakeY", DEFAULT_MINIGAME.painShakeY),
        maxLength = MiniNumber({"handMaxLength", "maxLength"}, 75),
        bounds = { 0, ScrW(), 0, ScrH() }
    })

    MG.handX, MG.handY = ScreenToSim(MG.handScreenX, MG.handScreenY)
    UpdateHandDrawPosition()
    MG.lastSampleAt = now

    local leftDown = input.IsMouseDown(MOUSE_LEFT)
    local startedClick = leftDown and not MG.lastMouseDown
    local stoppedClick = (not leftDown) and MG.lastMouseDown
    MG.lastMouseDown = leftDown

    if startedClick and not MG.holdingSyringe then
        local dx = math.abs(MG.handX - MG.syringeX)
        local dyFromTip = MG.handY - MG.syringeY
        local syringeScale = MiniNumber("syringeScale", DEFAULT_MINIGAME.syringeScale)
        local grabHalfW = MiniNumber("grabHalfWidth", SRC_SYRINGE_W * syringeScale * 0.75)
        local grabBelowTip = MiniNumber("grabBelowTip", DEFAULT_MINIGAME.grabBelowTip)
        local grabAboveTip = MiniNumber("grabAboveTip", SRC_SYRINGE_H * syringeScale + 40)
        if dx <= grabHalfW and dyFromTip >= -grabBelowTip and dyFromTip <= grabAboveTip then
            MG.holdingSyringe = true
            MG.holdOffsetX = MG.syringeX - MG.handX
            MG.holdOffsetY = MG.syringeY - MG.handY
        end
    end

    if MG.holdingSyringe then
        MG.syringeX = MG.handX + MG.holdOffsetX
        MG.syringeY = MG.handY + MG.holdOffsetY

        local skinY = MiniNumber({"skinY", "injectStartY"}, DEFAULT_MINIGAME.skinY)
        local stopY = MiniNumber({"stopY", "injectEndY"}, DEFAULT_MINIGAME.stopY)

        if MG.syringeY < skinY then
            MG.syringeX = MG.lastXPos
            local sideForce = MG.lastXPos - MG.holdOffsetX - MG.handX
            local maxRotation = MiniNumber("maxRotation", DEFAULT_MINIGAME.maxRotation)
            MG.syringeAngle = math.Clamp(
                sideForce * MiniNumber("rotationPerSideForce", DEFAULT_MINIGAME.rotationPerSideForce) * MiniNumber("rotationDirection", DEFAULT_MINIGAME.rotationDirection),
                -maxRotation,
                maxRotation
            )

            if math.abs(sideForce) > MiniNumber("breakSideForce", DEFAULT_MINIGAME.breakSideForce) and not MG.breakSent then
                MG.breakSent = true
                surface.PlaySound("bullethit.ogg")
                if WoundSystem.BroadcastMinigameSound then WoundSystem.BroadcastMinigameSound("bullethit.ogg", 0.5) end
                SendInput(0, true)
                BeginClose()
                return
            end

            if not MG.wasInjectingBefore then
                MG.wasInjectingBefore = true
                surface.PlaySound("syringe.ogg")
                if WoundSystem.BroadcastMinigameSound then WoundSystem.BroadcastMinigameSound("syringe.ogg", 0.5) end
            end

            local depth = math.Clamp((skinY - MG.syringeY) / math.max(skinY - stopY, 1), 0, 1)
            SetLoopVolume(depth)

            if now - (MG.lastSentAt or 0) >= MiniNumber("sendInterval", DEFAULT_MINIGAME.sendInterval) then
                local sendElapsed = now - (MG.lastSentAt or now)
                SendInput(depth, false)
                local slot = MG.slotIdx and WoundSystemInventorySlots and WoundSystemInventorySlots[MG.slotIdx]
                local item = GetActiveItem()
                local maxDur = item and item.max or 100
                local rate = GetSyringeDurabilityRate()
                local predictedCost = depth * sendElapsed * rate
                if slot and slot.type == "tool" then
                    slot.durability = math.max(0, (slot.durability or 0) - predictedCost)
                    MG.condition = math.Clamp(slot.durability / math.max(maxDur, 1), 0, 1)
                end
            end
        else
            MG.lastXPos = MG.syringeX
            MG.wasInjectingBefore = false
            MG.syringeAngle = Lerp(math.min(dt * 4, 1), MG.syringeAngle or 0, 0)
            SetLoopVolume(0)
        end

        if MG.syringeY < stopY then
            MG.syringeY = stopY
            local sx, sy = SimToScreen(MG.syringeX - MG.holdOffsetX, MG.syringeY - MG.holdOffsetY)
            MG.handScreenY = sy
            UpdateHandDrawPosition()
            if (MG.handScreenVelY or 0) > 0 then
                MG.handScreenVelY = 0
            end
        end
    else
        SetLoopVolume(0)
    end

    if stoppedClick then
        MG.holdingSyringe = false
        SetLoopVolume(0)
    end

    if MG.active and not MG.closeRequested and now - (MG.lastSentAt or 0) >= MiniNumber("sendInterval", DEFAULT_MINIGAME.sendInterval) then
        SendInput(0, false)
    end

    local rightDown = input.IsMouseDown(MOUSE_RIGHT)
    local escDown = input.IsKeyDown(KEY_ESCAPE)
    local startedRight = rightDown and not MG.lastRightDown
    local startedEsc = escDown and not MG.lastEscDown
    MG.lastRightDown = rightDown
    MG.lastEscDown = escDown

    if (startedRight or startedEsc) and (CurTime() - (MG.openTime or 0) > 0.2) then
        if startedEsc then gui.HideGameUI() end
        MG.RequestClose("user_cancel")
    end
end)

hook.Add("OnScreenSizeChanged", "WoundSystem_SyringeResize", function()
    if not MG.active then return end
    EnsureOverlay()
    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.MarkOpened(MG)
    end
end)

hook.Add("ShutDown", "WoundSystem_SyringeCleanup", function()
    StopLoop()
    DestroyOverlay()
end)
