if WoundSystemAEDMinigame and WoundSystemAEDMinigame._Loaded then return end

if not (WoundSystem and WoundSystem.MinigameClip) and file.Exists("woundsystem/client/minigames/cl_clip.lua", "LUA") then
    include("woundsystem/client/minigames/cl_clip.lua")
    include("woundsystem/client/minigames/sh_handphysics.lua")
end
local HandPhysics = include("woundsystem/client/minigames/sh_handphysics.lua")
local DevMinigameCfg = include("woundsystem/client/minigames/minigame_dev_config.lua") or {}

WoundSystemAEDMinigame = WoundSystemAEDMinigame or {}
local MG = WoundSystemAEDMinigame
MG._Loaded = true

local function CorruptUIText(text)
    return tostring(text or "")
end

local path = "casunknown-images/aedminigame/"
-- shared glass-shard sprites (folder name is legacy; no shrapnel mechanic remains)
local graspHandPath = "casunknown-images/shrapnelminigame/"
local matPad1 = Material(path .. "aedpad1.png")
local matPad2 = Material(path .. "aedpad2.png")
local matButton = Material(path .. "aedbutton.png")
local matLine = Material(path .. "aedline.png")
local matSideLine = Material(path .. "aedsideline.png")
local matHandGraspIdle = Material(graspHandPath .. "handgraspidle1.png")
local matHandGraspClick = Material(graspHandPath .. "handgraspclick.png")
local matHandPointIdle = Material(path .. "handPointIdle2.png")
local matHandPointClick = Material(path .. "handPointClick.png")

local CFG = {
    -- Global sim-space layout. Coordinates are centered on the screen.
    Scale = 1,
    CenterOffsetX = 0,
    CenterOffsetY = 0,

    -- AED-only clipped backplate.
    ClipBackgroundEnabled = true,
    ClipBackgroundAlpha = 200,
    ClipBackgroundFadeTime = 0.2,

    -- Hand: same spring/pain logic as the glass shard minigame.
    HandScale = 2,
    HandPivotX = 0.4,
    HandPivotY = 0.1,
    HandOffsetX = 50,
    HandOffsetY = 0,
    HandAlpha = 153,
    PainTensionLow = 45,
    PainTensionHigh = 250,
    PainDampingLow = 2,
    PainDampingHigh = 14,
    PainShakeX = 140,
    PainShakeY = 40,
    PainShakeSpeed = 0.8,

    -- Pad movement and placement.
    PadTargetTolerance = 150,
    RandomizePadStart = true,
    RandomPadRangeX = 150,
    RandomPadRangeY = 150,

    Pad1StartX = -120,
    Pad1StartY = 0,
    Pad1TargetX = -296,
    Pad1TargetY = 153,
    Pad1Width = 178,
    Pad1Height = 228,
    Pad1Rotation = 0,

    Pad2StartX = 120,
    Pad2StartY = 0,
    Pad2TargetX = 273,
    Pad2TargetY = -141,
    Pad2Width = 172,
    Pad2Height = 184,
    Pad2Rotation = 0,

    -- Static AED art.
    ButtonX = 0,
    ButtonY = -325,
    ButtonWidth = 128,
    ButtonHeight = 128,
    ButtonRotation = 0,
    ButtonDisabledAlpha = 255,
    ButtonEnabledAlpha = 255,

    SideLine1X = -177,
    SideLine1Y = 153,
    SideLine1Width = 350,
    SideLine1Height = 25,
    SideLine1Rotation = 0,

    SideLine2X = 177,
    SideLine2Y = -141,
    SideLine2Width = 350,
    SideLine2Height = 25,
    SideLine2Rotation = 180,

    LineX = 0,
    LineY = 0,
    LineWidth = 600,
    LineHeight = 800,
    LineRotation = 0,
    LineAlpha = 255,

    TextEnabled = true,
    TextX = 0,
    TextY = -229,
    StatusTextColor = Color(255, 255, 255),
    StatusTextAlignX = TEXT_ALIGN_CENTER,
    StatusTextAlignY = TEXT_ALIGN_CENTER,
    StatusTextFont = "WoundSystemAEDStatus",
    StatusTextLineGap = -15
}
MG.Config = CFG

local PAD_SOURCES = {
    { mat = matPad1, widthKey = "Pad1Width", heightKey = "Pad1Height", rotationKey = "Pad1Rotation" },
    { mat = matPad2, widthKey = "Pad2Width", heightKey = "Pad2Height", rotationKey = "Pad2Rotation" }
}

local STATE_TEXT = {
    [0] = "Place pads in designated spots.",
    [1] = "Analyzing pulse",
    [2] = "Shock recommended.\nPress button to shock.",
    [3] = "Charging",
    [4] = "Shock administered.\nStart CPR on patient.",
    [5] = "Shock not recommended.\nStart CPR on patient."
}

if WoundSystem and WoundSystem.CAS3Locale and WoundSystem.CAS3Locale.ApplyAEDStateText then
    WoundSystem.CAS3Locale.ApplyAEDStateText(STATE_TEXT)
end

surface.CreateFont("WoundSystemAEDStatus", { font = "Retro Gaming", size = 36, weight = 400, antialias = false })

local AED_SOUND_CANDIDATES = {
    start = { "aedstart.ogg", "aedstart.mp3", "aedstart.wav", "menuopen.ogg" },
    analyze = { "aedanalyze.ogg", "aedanalyze.mp3", "aedanalyze.wav", "heartthump-heavy-monitor.ogg", "miniclick.ogg" },
    ready = { "aedstart.ogg", "aedstart.mp3", "aedstart.wav", "miniclick.ogg" },
    charge = { "aedcharge.ogg", "aedcharge.mp3", "aedcharge.wav", "heartthump-heavy-monitor.ogg" },
    fail = { "aedfail.ogg", "aedfail.mp3", "aedfail.wav", "click.ogg" },
    shock = { "aedshock.ogg", "aedshock.mp3", "aedshock.wav", "bullethit.ogg" }
}

local soundCache = {}

local function ConfigNumber(key, fallback)
    local value = CFG[key]
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function ConfigColor(key, fallback)
    local value = CFG[key]
    if istable(value) and value.r and value.g and value.b then return value end
    return fallback
end

local function ConfigAlign(key, fallback)
    local value = CFG[key]
    if isnumber(value) then return value end
    if isstring(value) then
        local align = string.lower(value)
        if align == "left" then return TEXT_ALIGN_LEFT end
        if align == "center" or align == "middle" then return TEXT_ALIGN_CENTER end
        if align == "right" then return TEXT_ALIGN_RIGHT end
        if align == "top" then return TEXT_ALIGN_TOP end
        if align == "bottom" then return TEXT_ALIGN_BOTTOM end
    end
    return fallback
end

local function Scale()
    local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
    return scale * ConfigNumber("Scale", 1)
end

local function SimToScreen(x, y)
    local scale = Scale()
    local sx = ScrW() * 0.5 + ((x + ConfigNumber("CenterOffsetX", 0)) * scale)
    local sy = ScrH() * 0.5 - ((y + ConfigNumber("CenterOffsetY", 0)) * scale)
    return sx, sy
end

local function ScreenToSim(x, y)
    local scale = Scale()
    if scale <= 0 then scale = 1 end
    local sx = ((x - ScrW() * 0.5) / scale) - ConfigNumber("CenterOffsetX", 0)
    local sy = -((y - ScrH() * 0.5) / scale) - ConfigNumber("CenterOffsetY", 0)
    return sx, sy
end

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

local function SoundExists(soundPath)
    return file.Exists("sound/" .. soundPath, "GAME") or file.Exists("sound/" .. soundPath, "LUA")
end

local function ResolveSound(kind)
    if soundCache[kind] ~= nil then return soundCache[kind] or nil end

    local candidates = AED_SOUND_CANDIDATES[kind]
    if not candidates then
        soundCache[kind] = false
        return nil
    end

    for _, soundPath in ipairs(candidates) do
        if SoundExists(soundPath) then
            soundCache[kind] = soundPath
            return soundPath
        end
    end

    soundCache[kind] = candidates[#candidates] or false
    return soundCache[kind] or nil
end

local function PlayAEDSound(kind)
    local soundPath = ResolveSound(kind)
    if soundPath then
        surface.PlaySound(soundPath)
        if WoundSystem.BroadcastMinigameSound then
            WoundSystem.BroadcastMinigameSound(soundPath, 0.5)
        end
    end
end

local function DrawCentered(mat, x, y, w, h, rotation, color)
    if not mat or mat:IsError() then return end
    surface.SetMaterial(mat)
    surface.SetDrawColor(color or color_white)
    surface.DrawTexturedRectRotated(math.Round(x), math.Round(y), math.Round(w), math.Round(h), rotation or 0)
end

local function DrawCenteredStatusText(text, font, x, y, color, lineGap)
    text = tostring(text or "")
    font = font or "WoundSystemAEDStatus"
    surface.SetFont(font)

    local lines = string.Explode("\n", text, false)
    local _, lineH = surface.GetTextSize("Ag")
    local step = math.max(1, lineH + (tonumber(lineGap) or 0))
    local startY = y - ((#lines - 1) * step * 0.5)

    for i, line in ipairs(lines) do
        draw.SimpleText(line, font, x, startY + ((i - 1) * step), color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

local function PointInRotatedRect(px, py, cx, cy, w, h, rotation)
    local rad = math.rad(-(rotation or 0))
    local c = math.cos(rad)
    local s = math.sin(rad)
    local dx = px - cx
    local dy = py - cy
    local rx = (dx * c) - (dy * s)
    local ry = (dx * s) + (dy * c)
    return math.abs(rx) <= w * 0.5 and math.abs(ry) <= h * 0.5
end

local function GetPadTarget(index)
    if index == 2 then
        return ConfigNumber("Pad2TargetX", 273), ConfigNumber("Pad2TargetY", -141)
    end
    return ConfigNumber("Pad1TargetX", -296), ConfigNumber("Pad1TargetY", 153)
end

local function PadDistanceFromTarget(pad, index)
    local tx, ty = GetPadTarget(index)
    return math.sqrt((pad.x - tx) ^ 2 + (pad.y - ty) ^ 2)
end

local function PadsArePlaced()
    if not MG.pads[1] or not MG.pads[2] then return false end
    local tolerance = ConfigNumber("PadTargetTolerance", 150)
    return PadDistanceFromTarget(MG.pads[1], 1) < tolerance and PadDistanceFromTarget(MG.pads[2], 2) < tolerance
end

local function HitPad(screenX, screenY)
    local scale = Scale()
    for i = #MG.pads, 1, -1 do
        local pad = MG.pads[i]
        local src = PAD_SOURCES[i]
        local x, y = SimToScreen(pad.x, pad.y)
        local w = ConfigNumber(src.widthKey, i == 1 and 89 or 89) * scale
        local h = ConfigNumber(src.heightKey, i == 1 and 114 or 92) * scale
        local rotation = ConfigNumber(src.rotationKey, 0)
        if PointInRotatedRect(screenX, screenY, x, y, w, h, rotation) then
            return i
        end
    end
end

local function HitButton(screenX, screenY)
    local x, y = SimToScreen(ConfigNumber("ButtonX", 0), ConfigNumber("ButtonY", -205))
    local scale = Scale()
    return PointInRotatedRect(
        screenX,
        screenY,
        x,
        y,
        ConfigNumber("ButtonWidth", 64) * scale,
        ConfigNumber("ButtonHeight", 64) * scale,
        ConfigNumber("ButtonRotation", 0)
    )
end

local function SendAEDAction(action)
    if not MG.active or MG.closeRequested then return end
    if action == 1 and MG.state == 0 then
        MG.state = 1
        PlayAEDSound("analyze")
    elseif action == 2 and MG.state == 2 then
        MG.state = 3
        PlayAEDSound("charge")
    end

    net.Start("WoundSystem_AEDInput")
        net.WriteUInt(MG.sessionId or 0, 24)
        net.WriteUInt(action or 0, 3)
        net.WriteUInt(WoundSystem and WoundSystem.MinigameNextInputSeq and WoundSystem.MinigameNextInputSeq(MG) or 0, 24)
    net.SendToServer()
end

local function GetActiveItem()
    local itemId = MG.itemId or "AED"
    if WoundSystem and WoundSystem.Items and WoundSystem.Items.Get then
        local item = WoundSystem.Items.Get(itemId)
        if item then return item end
    end

    return WoundSystemMedToolConfig and WoundSystemMedToolConfig[itemId] or nil
end

MG.active = MG.active or false
MG.sessionId = MG.sessionId or 0
MG.limbId = MG.limbId or nil
MG.slotIdx = MG.slotIdx or nil
MG.itemId = MG.itemId or nil
MG.state = MG.state or 0
MG.condition = MG.condition or 1
MG.overlay = MG.overlay or nil
MG.closeRequested = MG.closeRequested or false
MG.pads = MG.pads or {}
MG.heldPad = MG.heldPad or nil
MG.heldOffsetX = MG.heldOffsetX or 0
MG.heldOffsetY = MG.heldOffsetY or 0
MG.placedSent = MG.placedSent or false
MG.chargeSent = MG.chargeSent or false
MG.lastMouseDown = input.IsMouseDown(MOUSE_LEFT)
MG.lastRightDown = input.IsMouseDown(MOUSE_RIGHT)
MG.lastEscDown = input.IsKeyDown(KEY_ESCAPE)
MG.openTime = MG.openTime or 0
MG.lastSampleAt = MG.lastSampleAt or 0
MG.handScreenX = MG.handScreenX or 0
MG.handScreenY = MG.handScreenY or 0
MG.handScreenVelX = MG.handScreenVelX or 0
MG.handScreenVelY = MG.handScreenVelY or 0
MG.handX = MG.handX or 0
MG.handY = MG.handY or 0
MG.handDrawX = MG.handDrawX or 0
MG.handDrawY = MG.handDrawY or 0
MG.handDrawW = MG.handDrawW or 0
MG.handDrawH = MG.handDrawH or 0
MG.inputSeq = MG.inputSeq or 0
MG.ackSeq = MG.ackSeq or 0

local function UpdateHandDrawPosition()
    local scale = Scale()
    MG.handDrawX = MG.handScreenX - (MG.handDrawW * ConfigNumber("HandPivotX", 0.4)) + ((DevMinigameCfg.aedHandOffsetX or ConfigNumber("HandOffsetX", 40)) * scale)
    MG.handDrawY = MG.handScreenY - (MG.handDrawH * ConfigNumber("HandPivotY", 0.1)) + ((DevMinigameCfg.aedHandOffsetY or ConfigNumber("HandOffsetY", 0)) * scale)
end

local function RebuildHandMetrics()
    local scale = Scale()
    -- Match bandage minigame hand sizing: use same source resolution and scale factors
    local SRC_HAND_W = 512
    local SRC_HAND_H = 1260
    local BANDAGE_SCALE_MULT = 1.7
    local BANDAGE_HAND_CURSOR_SCALE = 0.8
    local baseScale = scale * BANDAGE_SCALE_MULT
    MG.handDrawW = SRC_HAND_W * baseScale * BANDAGE_HAND_CURSOR_SCALE
    MG.handDrawH = SRC_HAND_H * baseScale * BANDAGE_HAND_CURSOR_SCALE
    UpdateHandDrawPosition()
end

local function DestroyOverlay()
    if IsValid(MG.overlay) then MG.overlay:Remove() end
    MG.overlay = nil
end

local function LocalReset()
    MG.active = false
    MG.sessionId = 0
    MG.limbId = nil
    MG.slotIdx = nil
    MG.itemId = nil
    MG.state = 0
    MG.condition = 1
    MG.closeRequested = false
    MG.pads = {}
    MG.heldPad = nil
    MG.heldOffsetX = 0
    MG.heldOffsetY = 0
    MG.placedSent = false
    MG.chargeSent = false
    MG.lastMouseDown = false
    MG.lastRightDown = false
    MG.lastEscDown = false
    MG.openTime = 0
    MG.lastSampleAt = 0
    MG.handScreenX = 0
    MG.handScreenY = ScrH() * 0.5 + ((DevMinigameCfg.aedHandOffsetY or 500) * Scale())
    MG.handScreenVelX = 0
    MG.handScreenVelY = 0
    MG.handX = 0
    MG.handY = 0
    MG.handDrawX = 0
    MG.handDrawY = 0
    MG.handDrawW = 0
    MG.handDrawH = 0
    MG._hp_acc = 0
    MG.inputSeq = 0
    MG.ackSeq = 0
    DestroyOverlay()
end

local function DrawAED()
    local scale = Scale()
    if CFG.ClipBackgroundEnabled and WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.DrawBackdrop then
        WoundSystem.MinigameClip.DrawBackdrop({
            openTime = MG.openTime,
            alpha = ConfigNumber("ClipBackgroundAlpha", 200),
            fadeTime = ConfigNumber("ClipBackgroundFadeTime", 0.2)
        })
    end

    local clipActive = WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Begin()

    do
        local x, y = SimToScreen(ConfigNumber("LineX", 0), ConfigNumber("LineY", 0))
        DrawCentered(
            matLine,
            x,
            y,
            ConfigNumber("LineWidth", 129) * scale,
            ConfigNumber("LineHeight", 128) * scale,
            ConfigNumber("LineRotation", 0),
            Color(255, 255, 255, ConfigNumber("LineAlpha", 120))
        )
    end

    do
        local x, y = SimToScreen(ConfigNumber("SideLine1X", -296), ConfigNumber("SideLine1Y", 153))
        DrawCentered(
            matSideLine,
            x,
            y,
            ConfigNumber("SideLine1Width", 95) * scale,
            math.max(1, ConfigNumber("SideLine1Height", 2) * scale),
            ConfigNumber("SideLine1Rotation", 0),
            Color(255, 255, 255, 190)
        )
    end

    do
        local x, y = SimToScreen(ConfigNumber("SideLine2X", 273), ConfigNumber("SideLine2Y", -141))
        DrawCentered(
            matSideLine,
            x,
            y,
            ConfigNumber("SideLine2Width", 95) * scale,
            math.max(1, ConfigNumber("SideLine2Height", 2) * scale),
            ConfigNumber("SideLine2Rotation", 0),
            Color(255, 255, 255, 190)
        )
    end

    for i, pad in ipairs(MG.pads) do
        local src = PAD_SOURCES[i]
        local x, y = SimToScreen(pad.x, pad.y)
        DrawCentered(
            src.mat,
            x,
            y,
            ConfigNumber(src.widthKey, i == 1 and 89 or 89) * scale,
            ConfigNumber(src.heightKey, i == 1 and 114 or 92) * scale,
            ConfigNumber(src.rotationKey, 0),
            Color(255, 255, 255, MG.state == 0 and 255 or 220)
        )
    end

    do
        local x, y = SimToScreen(ConfigNumber("ButtonX", 0), ConfigNumber("ButtonY", -205))
        local alpha = (MG.state == 2) and ConfigNumber("ButtonEnabledAlpha", 255) or ConfigNumber("ButtonDisabledAlpha", 95)
        DrawCentered(
            matButton,
            x,
            y,
            ConfigNumber("ButtonWidth", 64) * scale,
            ConfigNumber("ButtonHeight", 64) * scale,
            ConfigNumber("ButtonRotation", 0),
            Color(255, 255, 255, alpha)
        )
    end

    if CFG.TextEnabled then
        local tx, ty = SimToScreen(ConfigNumber("TextX", 0), ConfigNumber("TextY", -289))
        local text = STATE_TEXT[MG.state] or "AED"
        if MG.state == 1 or MG.state == 3 then
            text = text .. string.rep(".", 1 + (math.floor(CurTime() * 3) % 3))
        end
        text = CorruptUIText(text)

        DrawCenteredStatusText(
            text,
            CFG.StatusTextFont or "WoundSystemAEDStatus",
            tx,
            ty,
            ConfigColor("StatusTextColor", Color(220, 240, 245)),
            ConfigNumber("StatusTextLineGap", -15)
        )
    end

    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.End(clipActive)
    end
end

local function DrawHand()
    local clicking = input.IsMouseDown(MOUSE_LEFT)
    local pointMode = MG.state >= 1
    local handMat = pointMode and (clicking and matHandPointClick or matHandPointIdle) or (clicking and matHandGraspClick or matHandGraspIdle)
    if not handMat or handMat:IsError() then return end

    local clipActive = WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Begin()
    surface.SetMaterial(handMat)

    local gb = 255
    local state = WoundSystemClientState and WoundSystemClientState.PlayerLimbs and WoundSystemClientState.PlayerLimbs[MG.limbId]
    if state and state.pain then
        local painFactor = math.Clamp(state.pain, 0, 100) / 100
        gb = 255 * (1 - painFactor)
    end

    surface.SetDrawColor(255, gb, gb, ConfigNumber("HandAlpha", 153))
    local cx = MG.handDrawX + (MG.handDrawW * ConfigNumber("HandPivotX", 0.4))
    local cy = MG.handDrawY + (MG.handDrawH * ConfigNumber("HandPivotY", 0.1))
    local angle = (MG.handScreenVelX or 0) * 0.5
    surface.DrawTexturedRectRotated(math.Round(cx), math.Round(cy), math.Round(MG.handDrawW), math.Round(MG.handDrawH), angle)

    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.End(clipActive)
    end
end

local function DrawMinigameHeader()
    if not (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.DrawHeader) then return end

    local slot = MG.slotIdx and WoundSystemInventorySlots and WoundSystemInventorySlots[MG.slotIdx]
    local item = GetActiveItem()
    local maxDur = item and item.max or 100
    local curDur = slot and slot.durability or ((MG.condition or 0) * maxDur)
    local durPct = math.Round(math.Clamp(curDur / math.max(maxDur, 1), 0, 1) * 100)

    WoundSystem.MinigameClip.DrawHeader({
        minigame = "aed",
        title = item and item.title or MG.itemId or "AED",
        value = durPct .. "%",
        curValue = curDur,
        maxValue = maxDur,
        mat = slot and slot.mat,
        icon = item and item.icon,
        pw = (slot and slot.pw) or (item and item.pw),
        ph = (slot and slot.ph) or (item and item.ph)
    })
end

local function EnsureOverlay()
    DestroyOverlay()
    RebuildHandMetrics()

    MG.overlay = vgui.Create("DPanel")
    MG.overlay:SetSize(ScrW(), ScrH())
    MG.overlay:SetPos(0, 0)
    MG.overlay:SetZPos(32000)
    MG.overlay:SetMouseInputEnabled(false)
    MG.overlay:SetKeyboardInputEnabled(false)
    MG.overlay:SetPaintBackground(false)

    MG.overlay.Paint = function()
        if not MG.active then return end
        local filtered = BeginPixelFilter()
        DrawAED()
        EndPixelFilter(filtered)
    end

    MG.overlay.PaintOver = function()
        if not MG.active then return end
        local filtered = BeginPixelFilter()
        DrawHand()
        EndPixelFilter(filtered)
        DrawMinigameHeader()
        WoundSystem.MinigameClip.DrawExitGuide()
    end
end

function MG.IsActive()
    return MG.active == true
end

concommand.Add("woundsys_aed_print_pads", function()
    if not MG.active then
        print("[WS AED POS] minigame is not active")
        return
    end

    local tolerance = ConfigNumber("PadTargetTolerance", 150)
    for i = 1, 2 do
        local pad = MG.pads[i]
        if pad then
            local tx, ty = GetPadTarget(i)
            local dist = PadDistanceFromTarget(pad, i)
            print(string.format(
                "[WS AED POS] pad%d=(%.1f, %.1f) target=(%.1f, %.1f) dist=%.1f tolerance=%.1f ok=%s",
                i,
                pad.x or 0,
                pad.y or 0,
                tx,
                ty,
                dist,
                tolerance,
                tostring(dist < tolerance)
            ))
        end
    end
end)

function MG.RequestStart(limbId, slotIdx)
    MG.slotIdx = slotIdx
    net.Start("WoundSystem_AEDStart")
        net.WriteString(limbId or "")
        net.WriteUInt(slotIdx or 0, 3)
    net.SendToServer()
end

function MG.RequestClose(reason)
    if not MG.active or MG.closeRequested then return end
    MG.closeRequested = true
    net.Start("WoundSystem_AEDClose")
        net.WriteUInt(MG.sessionId or 0, 24)
        net.WriteString(reason or "client_close")
    net.SendToServer()
    LocalReset()
end

net.Receive("WoundSystem_AEDOpen", function()
    LocalReset()
    MG.active = true
    MG.sessionId = net.ReadUInt(24)
    MG.limbId = net.ReadString()
    MG.slotIdx = net.ReadUInt(3)
    MG.itemId = net.ReadString()
    MG.condition = net.ReadFloat()
    MG.state = 0
    MG.openTime = CurTime()
    MG.lastMouseDown = input.IsMouseDown(MOUSE_LEFT)
    MG.lastRightDown = input.IsMouseDown(MOUSE_RIGHT)
    MG.lastEscDown = input.IsKeyDown(KEY_ESCAPE)

    MG.pads = {
        {
            x = CFG.RandomizePadStart and math.Rand(-ConfigNumber("RandomPadRangeX", 150), ConfigNumber("RandomPadRangeX", 150)) or ConfigNumber("Pad1StartX", -120),
            y = CFG.RandomizePadStart and math.Rand(-ConfigNumber("RandomPadRangeY", 150), ConfigNumber("RandomPadRangeY", 150)) or ConfigNumber("Pad1StartY", 0)
        },
        {
            x = CFG.RandomizePadStart and math.Rand(-ConfigNumber("RandomPadRangeX", 150), ConfigNumber("RandomPadRangeX", 150)) or ConfigNumber("Pad2StartX", 120),
            y = CFG.RandomizePadStart and math.Rand(-ConfigNumber("RandomPadRangeY", 150), ConfigNumber("RandomPadRangeY", 150)) or ConfigNumber("Pad2StartY", 0)
        }
    }

    EnsureOverlay()

    local mx, my = gui.MousePos()
    if mx <= 0 and my <= 0 then
        mx, my = ScrW() * 0.5, ScrH() * 0.5
    end

    MG.handScreenX = mx
    MG.handScreenY = my + ((DevMinigameCfg.aedHandOffsetY or 500) * Scale())
    MG.handScreenVelX = 0
    MG.handScreenVelY = 0
    MG.handX, MG.handY = ScreenToSim(mx, my)
    MG.lastSampleAt = CurTime()
    UpdateHandDrawPosition()

    PlayAEDSound("start")

    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.MarkOpened(MG)
    end
end)

net.Receive("WoundSystem_AEDState", function()
    local sessionId = net.ReadUInt(24)
    local state = net.ReadUInt(3)
    local condition = net.ReadFloat()
    local ackSeq = WoundSystem and WoundSystem.MinigameReadAck and WoundSystem.MinigameReadAck(0) or 0
    if not MG.active or sessionId ~= MG.sessionId then return end

    local oldState = MG.state
    MG.state = state
    MG.condition = math.Clamp(condition, 0, 1)
    if WoundSystem and WoundSystem.MinigameAck then
        WoundSystem.MinigameAck(MG, ackSeq)
    end
    if state ~= 3 then MG.chargeSent = false end

    if state ~= oldState then
        if state == 1 then
            PlayAEDSound("analyze")
        elseif state == 2 then
            PlayAEDSound("ready")
        elseif state == 3 then
            PlayAEDSound("charge")
        elseif state == 4 then
            PlayAEDSound("shock")
        elseif state == 5 then
            PlayAEDSound("fail")
        end
    end
end)

net.Receive("WoundSystem_AEDClose", function()
    local sessionId = net.ReadUInt(24)
    net.ReadString()
    if not MG.active or sessionId ~= MG.sessionId then return end
    LocalReset()
end)

hook.Add("Think", "WoundSystem_AEDInput", function()
    if not MG.active then return end
    if not IsValid(MG.overlay) then
        EnsureOverlay()
        if not IsValid(MG.overlay) then return end
    end

    if WoundSystemHealthHUDOpen == false then
        MG.RequestClose("hud_closed")
        return
    end

    local now = CurTime()
    local dt = math.max(now - (MG.lastSampleAt or now), 0.001)
    local mx, my = gui.MousePos()

    local state = WoundSystemClientState and WoundSystemClientState.PlayerLimbs and WoundSystemClientState.PlayerLimbs[MG.limbId]
    local painFactor = 0
    if state and state.pain then
        painFactor = math.Clamp(state.pain, 0, 100) / 100
    end

    -- Use shared HandPhysics for AED hand movement + shake
    local stats = WoundSystemClientState and WoundSystemClientState.PlayerStats or nil
    local str = stats and stats.STR or 0
    local conc = stats and stats.consciousness or 100

    HandPhysics.Step(MG, dt, {
        pain = painFactor,
        str = str,
        conc = conc,
        shakeX = ConfigNumber("PainShakeX", 140),
        shakeY = ConfigNumber("PainShakeY", 40),
        maxLength = 200,
        bounds = { 0, ScrW(), 0, ScrH() }
    })

    MG.handX, MG.handY = ScreenToSim(MG.handScreenX, MG.handScreenY)
    MG.lastSampleAt = now
    UpdateHandDrawPosition()

    local leftDown = input.IsMouseDown(MOUSE_LEFT)
    local rightDown = input.IsMouseDown(MOUSE_RIGHT)
    local escDown = input.IsKeyDown(KEY_ESCAPE)
    local startedClick = leftDown and not MG.lastMouseDown
    local stoppedClick = not leftDown and MG.lastMouseDown
    local startedRight = rightDown and not MG.lastRightDown
    local startedEsc = escDown and not MG.lastEscDown

    if (startedRight or startedEsc) and (CurTime() - (MG.openTime or 0) > 0.2) then
        if startedEsc then gui.HideGameUI() end
        MG.RequestClose("manual_close")
        return
    end

    if startedClick then
        if MG.state == 0 then
            local padIndex = HitPad(MG.handScreenX, MG.handScreenY)
            if padIndex then
                MG.heldPad = padIndex
                MG.heldOffsetX = MG.pads[padIndex].x - MG.handX
                MG.heldOffsetY = MG.pads[padIndex].y - MG.handY
            end
        elseif MG.state == 2 and HitButton(MG.handScreenX, MG.handScreenY) and not MG.chargeSent then
            MG.chargeSent = true
            SendAEDAction(2)
        end
    end

    if MG.heldPad and MG.state == 0 then
        MG.pads[MG.heldPad].x = MG.handX + MG.heldOffsetX
        MG.pads[MG.heldPad].y = MG.handY + MG.heldOffsetY
    end

    if stoppedClick then
        MG.heldPad = nil
    end

    if MG.state == 0 and not MG.heldPad and not MG.placedSent and PadsArePlaced() then
        MG.placedSent = true
        SendAEDAction(1)
    end

    MG.lastMouseDown = leftDown
    MG.lastRightDown = rightDown
    MG.lastEscDown = escDown
end)

hook.Add("OnScreenSizeChanged", "WoundSystem_AEDResize", function()
    if not MG.active then return end
    EnsureOverlay()
    UpdateHandDrawPosition()
    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.MarkOpened(MG)
    end
end)

hook.Add("ShutDown", "WoundSystem_AEDCleanup", function()
    DestroyOverlay()
end)
