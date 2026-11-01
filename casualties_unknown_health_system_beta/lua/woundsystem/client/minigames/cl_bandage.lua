if WoundSystemBandageMinigame and WoundSystemBandageMinigame._Loaded then return end

if not (WoundSystem and WoundSystem.MinigameClip) and file.Exists("woundsystem/client/minigames/cl_clip.lua", "LUA") then
    include("woundsystem/client/minigames/cl_clip.lua")
end

local function DrawRectInt(x, y, w, h)
    surface.DrawTexturedRect(math.Round(tonumber(x) or 0), math.Round(tonumber(y) or 0), math.Round(tonumber(w) or 0), math.Round(tonumber(h) or 0))
end
local function DrawRectUVInt(x, y, w, h, u1, v1, u2, v2)
    surface.DrawTexturedRectUV(math.Round(tonumber(x) or 0), math.Round(tonumber(y) or 0), math.Round(tonumber(w) or 0), math.Round(tonumber(h) or 0), u1, v1, u2, v2)
end
-- healthsystem/lua/autorun/client/cl_bandage_minigame.lua

local CFG = {
    -- UI Scaling
    ScaleMultiplier = 1.7,        -- OVERALL UI SIZE
    HandCursorScale = .8,         -- How big the hand cursor is relative to the minigame
    ClipBackgroundEnabled = true,
    ClipBackgroundAlpha = 200,
    ClipBackgroundFadeTime = 0.2,

    -- Bandage Visuals
    InnerBaseSize = 320,          -- The static size of the Inner Circle
    OuterSizeRatio = .55,         -- Outer Bandage size multiplier relative to the inner circle
    OuterGrowthRate = 0.02,       -- How many pixels the outer bandage grows per degree AFTER the first wrap
    StickSize = 420,              -- Size of the arm/stick image

    -- Roll & Collision (Orbit around the center)
    CollisionRadius = 175,        -- The invisible barrier that pushes your hand outward
    OrbitDistanceMin = 190,       -- Orbit radius from center when bandage roll is EMPTY
    OrbitDistanceMax = 260,       -- Orbit radius from center when bandage roll is FULL
    RollScaleMult = 200,          -- Base size of the bandage roll spool image itself

    -- Spring Physics (The bouncy cursor)
    SpringTension = 250,          -- BASE TENSION (When healthy)
    SpringDamping = 14,           -- BASE FRICTION (When healthy)

    -- Gameplay Mechanics
    PhysicsDrag = 2,             -- How heavy the bandage feels when you drag it
    DurabilityPerWrap = 2.0,      -- NEW: How much tool durability is permanently lost per full 360 wrap
    AngleTolerance = 20,          -- How many degrees you can move per frame and have it count
    GrabDotProduct = 0.85,        -- How accurate you have to click (1.0 = perfect aim, 0.0 = anywhere)
    MaxFrameTime = 0.08,          -- Clamp lag spikes so the spring stays controllable
    PhysicsStep = 1 / 90          -- Substep large frames for smoother low-FPS movement
}

-- Client-adjustable tuning
local BANDAGE_SPEED_CONVAR = CreateClientConVar("woundsys_bandage_speed_mult", "1", true, false, "Global speed multiplier for bandage minigame (multiplies limb.bandageMinigameSpeedMult)")
---------------------------------------------------------------------------

local path = "casunknown-images/bandageminigame/"
local matBackground = Material(path .. "bandageOuter.png")
local matInner = Material(path .. "bandageCircleInner.png")
local matStick = Material(path .. "bandageStick.png")
local matRoll = Material(path .. "bandageRoll.png")
local matHandIdle = Material(path .. "handGraspIdle1.png")
local matHandClick = Material(path .. "handGraspClick.png")
local HandPhysics = include("woundsystem/client/minigames/sh_handphysics.lua")
if not istable(HandPhysics) then
    ErrorNoHalt("[WoundSystem] Bandage minigame could not load sh_handphysics.lua; using emergency fallback.\n")
    HandPhysics = {
        Init = function(mg)
            mg.handScreenX = mg.handScreenX or (ScrW() * 0.5)
            mg.handScreenY = mg.handScreenY or (ScrH() * 0.5)
            mg.handScreenVelX = mg.handScreenVelX or 0
            mg.handScreenVelY = mg.handScreenVelY or 0
        end,
        Step = function(mg, dt, opts)
            opts = opts or {}
            HandPhysics.Init(mg)
            local mx, my = gui.MousePos()
            if mx <= 0 and my <= 0 then mx, my = ScrW() * 0.5, ScrH() * 0.5 end
            local follow = tonumber(opts.followScale) or 0.25
            local rate = math.Clamp((tonumber(dt) or 0) * (tonumber(opts.responsiveness) or 6), 0, 1)
            mg.handScreenX = Lerp(rate, mg.handScreenX, mx)
            mg.handScreenY = Lerp(rate, mg.handScreenY, my)
            mg.handScreenVelX = (mx - mg.handScreenX) * follow
            mg.handScreenVelY = (my - mg.handScreenY) * follow
        end,
        Rotation = function(mg, rotOffset)
            return (mg.handScreenVelX or 0) * 0.5 + (rotOffset or 0)
        end
    }
end
local DevMinigameCfg = include("woundsystem/client/minigames/minigame_dev_config.lua") or {}

-- bandage uses its own hand physics (restore original logic)

local iconPath = "casunknown-images/icons/"
local BleedIcons = {
    small = Material(iconPath .. "smallbleeding.png"),
    smallBandaged = Material(iconPath .. "smallbleedingbandaged.png"),
    mid = Material(iconPath .. "midbleeding.png"),
    midBandaged = Material(iconPath .. "midbleedingbandaged.png"),
    strong = Material(iconPath .. "strongbleed.png"),
    strongBandaged = Material(iconPath .. "strongbleedbandaged.png"),
    extreme = Material(iconPath .. "bleeding.png"),
    extremeBandaged = Material(iconPath .. "bleedingbandaged.png")
}

WoundSystemBandageMinigame = WoundSystemBandageMinigame or {}
local MG = WoundSystemBandageMinigame
MG._Loaded = true

local SRC_HAND_W = 512
local SRC_HAND_H = 1260

local function GetScale()
    return (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
end

local HAND_CURSOR_PIVOT_X = 0.4
local HAND_CURSOR_PIVOT_Y = 0.1
local HAND_CURSOR_OFFSET_X = 40

MG.active = MG.active or false
MG.sessionId = MG.sessionId or 0
MG.limbId = MG.limbId or nil
MG.slotIdx = MG.slotIdx or nil
MG.mode = MG.mode or "gauze"

MG.bandageAngle = MG.bandageAngle or 0
MG.totalDegreesWrapped = MG.totalDegreesWrapped or 0
MG.completedWraps = MG.completedWraps or 0
MG.unsentDegrees = MG.unsentDegrees or 0

MG.holdingBandage = MG.holdingBandage or false
MG.condition = MG.condition or 1.0

MG.overlay = MG.overlay or nil
MG.closeRequested = MG.closeRequested or false
MG.lastMouseDown = input.IsMouseDown(MOUSE_LEFT)
MG.lastRightDown = input.IsMouseDown(MOUSE_RIGHT)
MG.lastEscDown = input.IsKeyDown(KEY_ESCAPE)
MG.openTime = MG.openTime or 0

-- Simulated coordinates
MG.handPos = MG.handPos or { x = 0, y = 300 }
MG.handVelocity = MG.handVelocity or { x = 0, y = 0 }
MG.handScreenX = MG.handScreenX or 0
MG.handScreenY = MG.handScreenY or 0
MG.handScreenVelX = MG.handScreenVelX or 0
MG.handScreenVelY = MG.handScreenVelY or 0
MG.lastSampleAt = MG.lastSampleAt or 0
MG.lastSentAt = MG.lastSentAt or 0
MG.inputSeq = MG.inputSeq or 0
MG.ackSeq = MG.ackSeq or 0

local function GetVectorFromAngle(angle)
    local rad = angle * (math.pi / 180)
    return { x = math.sin(rad), y = math.cos(rad) } 
end

local function GetAngleFromVector(dirX, dirY)
    local num = math.atan2(dirX, dirY) * 57.29578
    if num < 0 then num = num + 360 end
    return num
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

local function DestroyOverlay()
    if IsValid(MG.overlay) then MG.overlay:Remove() end
    MG.overlay = nil
end

local function LocalReset()
    if MG.externalClicker then
        MG.externalClicker = false
        if WoundSystem and WoundSystem.HealthGUI and WoundSystem.HealthGUI.SetScreenClickerOwned and not WoundSystemHealthHUDOpen then
            WoundSystem.HealthGUI.SetScreenClickerOwned(false, "zcity_swep_bandage_end")
        end
    end

    MG.active = false
    MG.closing = false
    MG.sessionId = 0
    MG.limbId = nil
    MG.slotIdx = nil
    MG.mode = "gauze"
    MG.closeRequested = false
    MG.lastMouseDown = false
    MG.lastRightDown = false
    MG.lastEscDown = false
    MG.openTime = 0
    MG.bandageAngle = 0
    MG.lastActionAngle = 0
    MG.totalDegreesWrapped = 0
    MG.completedWraps = 0
    MG.unsentDegrees = 0
    MG.didWrap = false
    MG.sizeMultiplier = 0.9
    MG.holdingBandage = false
    MG.condition = 1.0
    MG._hp_acc = 0
    
    local baseScale = (ScrH() / 1080) * CFG.ScaleMultiplier
    MG.handPos = { x = 0, y = 0 }
    MG.handVelocity = { x = 0, y = 0 }
    MG.handScreenX = ScrW() * 0.5
    MG.handScreenY = ScrH() * 0.5 + ((DevMinigameCfg.bandageHandOffsetY or 500) * baseScale)
    MG.handScreenVelX = 0
    MG.handScreenVelY = 0
    MG.lastSampleAt = 0
    MG.lastSentAt = 0
    MG.inputSeq = 0
    MG.ackSeq = 0
    
    DestroyOverlay()
end

local function BeginClose()
    if not MG.active then return end
    MG.closeRequested = true
    LocalReset()
end

local function GetActiveToolId()
    local slot = MG.slotIdx and WoundSystemInventorySlots and WoundSystemInventorySlots[MG.slotIdx]
    return slot and slot.toolName or "GAUZE"
end

local function GetActiveItem()
    local toolId = GetActiveToolId()
    if WoundSystem and WoundSystem.Items and WoundSystem.Items.Get then
        local item = WoundSystem.Items.Get(toolId)
        if item then return item end
    end

    return WoundSystemMedToolConfig and WoundSystemMedToolConfig[toolId] or nil
end

local function GetActiveBandageConfig()
    local item = GetActiveItem()
    local use = item and item.use
    return type(use and use.bandage) == "table" and use.bandage or {}
end

local function ToColor(value, fallback)
    fallback = fallback or color_white
    if IsColor and IsColor(value) then return value end
    if type(value) ~= "table" then return fallback end

    local r = value.r or value[1] or fallback.r or 255
    local g = value.g or value[2] or fallback.g or 255
    local b = value.b or value[3] or fallback.b or 255
    local a = value.a or value[4] or fallback.a or 255
    return Color(r, g, b, a)
end

local function GetBandageTint()
    local cfg = GetActiveBandageConfig()
    if cfg.color then
        return ToColor(cfg.color, Color(255, 255, 255, 255))
    end

    if MG.mode == "bruise" then
        return Color(50, 255, 70, 255)
    end

    return Color(255, 255, 255, 255)
end

local function GetDurabilityPerWrap()
    local cfg = GetActiveBandageConfig()
    if tonumber(cfg.durabilityPerWrap) then
        return tonumber(cfg.durabilityPerWrap)
    end

    local item = GetActiveItem()
    local use = item and item.use
    if use and tonumber(use.durabilityPerWrap) then
        return tonumber(use.durabilityPerWrap)
    end

    if MG.mode == "bruise" then
        return 10
    end

    return CFG.DurabilityPerWrap
end

local function GetHintText()
    return (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.ExitGuide) or "Press RMB/ESC to exit"
end

local function DrawMinigameHeader()
    if not (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.DrawHeader) then return end

    local slot = MG.slotIdx and WoundSystemInventorySlots and WoundSystemInventorySlots[MG.slotIdx]
    if not slot or slot.type ~= "tool" then return end

    local item = GetActiveItem()
    local maxDur = item and item.max or 100
    local curDur = MG.shownDur or slot.durability or 0
    local durPct = math.Round(math.Clamp(curDur / math.max(maxDur, 1), 0, 1) * 100)

    WoundSystem.MinigameClip.DrawHeader({
        minigame = "bandage",
        title = item and item.title or slot.toolName or "Medical tool",
        value = durPct .. "%",
        curValue = curDur,
        maxValue = maxDur,
        mat = slot.mat,
        icon = item and item.icon,
        pw = slot.pw or (item and item.pw),
        ph = slot.ph or (item and item.ph)
    })
end

local function LerpColor(t, c1, c2)
    return Color(Lerp(t, c1.r, c2.r), Lerp(t, c1.g, c2.g), Lerp(t, c1.b, c2.b), Lerp(t, c1.a or 255, c2.a or 255))
end

local function GetBleedIcon(state)
    if not state then return nil end

    local rate = (tonumber(state.bleed) or 0) * 0.075
    if rate <= 0.01 then return nil end

    local bandaged = state.isBandaged == true
    local mat
    if rate < 0.05 then
        mat = bandaged and BleedIcons.smallBandaged or BleedIcons.small
    elseif rate < 0.35 then
        mat = bandaged and BleedIcons.midBandaged or BleedIcons.mid
    elseif rate < 0.9 then
        mat = bandaged and BleedIcons.extremeBandaged or BleedIcons.extreme
    else
        mat = bandaged and BleedIcons.strongBandaged or BleedIcons.strong
    end

    local p1 = Color(255, 255, 255, 255)
    local p2 = Color(255, 232, 45, 255)
    local p3 = Color(105, 0, 0, 255)
    local color

    if rate <= 0.08 then
        color = LerpColor(math.Clamp((rate - 0.01) / 0.07, 0, 1), p1, p2)
    else
        color = LerpColor(math.Clamp((rate - 0.08) / 0.67, 0, 1), p2, p3)
    end

    return mat, color
end

-- Polygon Triangle drawing
local function DrawPie(x, y, radius, startAngle, endAngle, step)
    step = step or 2
    for a = startAngle, endAngle, step do
        local nextAngle = math.min(a + step, endAngle)
        if a == nextAngle then break end
        
        local rad1 = math.rad(a)
        local rad2 = math.rad(nextAngle)
        
        local poly = {
            { x = x, y = y, u = 0.5, v = 0.5 },
            { x = x + math.sin(rad1) * radius, y = y - math.cos(rad1) * radius, u = 0.5 + math.sin(rad1) * 0.5, v = 0.5 - math.cos(rad1) * 0.5 },
            { x = x + math.sin(rad2) * radius, y = y - math.cos(rad2) * radius, u = 0.5 + math.sin(rad2) * 0.5, v = 0.5 - math.cos(rad2) * 0.5 }
        }
        surface.DrawPoly(poly)
    end
end

local function EnsureOverlay()
    DestroyOverlay()

    MG.overlay = vgui.Create("DPanel")
    MG.overlay:SetSize(ScrW(), ScrH())
    MG.overlay:SetPos(0, 0)
    MG.overlay:SetZPos(32000)
    MG.overlay:SetMouseInputEnabled(false)
    MG.overlay:SetKeyboardInputEnabled(false)
    MG.overlay:SetPaintBackground(false)

    MG.overlay.Paint = function(_, w, h)
        if not MG.active then return end

        local cx, cy = w / 2, h / 2
        local filtered = BeginPixelFilter()
        if CFG.ClipBackgroundEnabled and WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.DrawBackdrop then
            WoundSystem.MinigameClip.DrawBackdrop({
                openTime = MG.openTime,
                alpha = CFG.ClipBackgroundAlpha,
                fadeTime = CFG.ClipBackgroundFadeTime
            })
        end

        local clipActive = WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Begin()
        
        local baseScale = GetScale() * CFG.ScaleMultiplier
        
        local innerSize = CFG.InnerBaseSize * baseScale
        local stickSize = CFG.StickSize * baseScale
        
        local outerBaseSize = innerSize * CFG.OuterSizeRatio
        local outerCurrentSize = outerBaseSize
        
        if MG.totalDegreesWrapped > 360 then
            outerCurrentSize = outerBaseSize + ((MG.totalDegreesWrapped - 360) * CFG.OuterGrowthRate)
        end

        -- Display angle for pie: full circle when wrapped, otherwise current bandage angle (updates every frame smoothly)
        local displayAngleForPie = (MG.didWrap and 360) or MG.bandageAngle
        
        if displayAngleForPie > 0 then
            local radius = math.Round(outerCurrentSize)
            local drawSize = radius * 2 
            local drawX = math.Round(cx - radius)
            local drawY = math.Round(cy - radius)

            surface.SetMaterial(matBackground)
            surface.SetDrawColor(GetBandageTint())

            if displayAngleForPie < 360 then
                DrawPie(cx, cy, radius, 0, displayAngleForPie, 2)
            else
                DrawRectInt(drawX, drawY, drawSize, drawSize)
            end
        end

        surface.SetMaterial(matInner)
        surface.SetDrawColor(255, 255, 255, 255)
        DrawRectInt(cx - innerSize/2, cy - innerSize/2, innerSize, innerSize)
        
        local conditionFactor = 1 - (1 - MG.condition) * (1 - MG.condition)
        local rollDist = Lerp(conditionFactor, CFG.OrbitDistanceMin, CFG.OrbitDistanceMax) * baseScale
        
        local rollVec = GetVectorFromAngle(MG.bandageAngle)
        local rollX = cx + (rollVec.x * rollDist)
        local rollY = cy - (rollVec.y * rollDist) 
        local rollScaleSize = CFG.RollScaleMult * baseScale * conditionFactor

        surface.SetMaterial(matRoll)
        surface.SetDrawColor(GetBandageTint())
        surface.DrawTexturedRectRotated(rollX, rollY, rollScaleSize, rollScaleSize, MG.bandageAngle * -3)

        local state = WoundSystemClientState and WoundSystemClientState.PlayerLimbs and WoundSystemClientState.PlayerLimbs[MG.limbId]
        local bleedMat, bleedColor = GetBleedIcon(state)
        if bleedMat then
            local iconScale = 4.5 * GetScale()
            local iconW = bleedMat:Width() * iconScale
            local iconH = bleedMat:Height() * iconScale
            local iconX = cx - iconW / 2
            local iconY = cy + (innerSize * 0.18)
            surface.SetMaterial(bleedMat)
            surface.SetDrawColor(bleedColor.r, bleedColor.g, bleedColor.b, bleedColor.a)
            DrawRectInt(iconX, iconY, iconW, iconH)
        end

        surface.SetMaterial(matStick)
        surface.SetDrawColor(255, 255, 255, 153)
        surface.DrawTexturedRectRotated(cx, cy, stickSize, stickSize, -MG.bandageAngle)

        if WoundSystem and WoundSystem.MinigameClip then
            WoundSystem.MinigameClip.End(clipActive)
        end
        EndPixelFilter(filtered)
    end

    MG.overlay.PaintOver = function(_, _, _)
        if not MG.active then return end

        local cx, cy = ScrW() / 2, ScrH() / 2
        local baseScale = GetScale() * CFG.ScaleMultiplier
        
        local screenX = cx + (MG.handPos.x * baseScale)
        local screenY = cy - (MG.handPos.y * baseScale)
        
        local handDrawW = SRC_HAND_W * baseScale * CFG.HandCursorScale
        local handDrawH = SRC_HAND_H * baseScale * CFG.HandCursorScale
        local handPivotX = 0.4
        local handPivotY = 0.1
        local handX = screenX - (handDrawW * handPivotX) + ((DevMinigameCfg.bandageHandOffsetX or 0) * baseScale)
        local handY = screenY - (handDrawH * handPivotY) + ((DevMinigameCfg.bandageHandOffsetY or 0) * baseScale)

        local handMat = MG.holdingBandage and matHandClick or matHandIdle
        local filtered = BeginPixelFilter()
        local clipActive = WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Begin()
        surface.SetMaterial(handMat)
        
        local gb = 255
        local state = WoundSystemClientState and WoundSystemClientState.PlayerLimbs and WoundSystemClientState.PlayerLimbs[MG.limbId]
        if state and state.pain then
            local painFactor = math.Clamp(state.pain, 0, 100) / 100
            gb = 255 * (1 - painFactor)
        end
        
        surface.SetDrawColor(255, gb, gb, 153)
        
        local cx_hand = handX + (handDrawW * handPivotX)
        local cy_hand = handY + (handDrawH * handPivotY)
        local angle = HandPhysics.Rotation(MG, (MG.handPos and MG.handPos.x) and (MG.handPos.x * 0.02) or 0)
        surface.DrawTexturedRectRotated(cx_hand, cy_hand, handDrawW, handDrawH, angle)
        if WoundSystem and WoundSystem.MinigameClip then
            WoundSystem.MinigameClip.End(clipActive)
        end
        EndPixelFilter(filtered)

        DrawMinigameHeader()
        WoundSystem.MinigameClip.DrawExitGuide()
    end
end

function MG.IsActive() return MG.active == true end

function MG.RequestStart(limbId, slotIdx)
    MG.slotIdx = slotIdx
    net.Start("WoundSystem_BandageStart")
        net.WriteString(limbId)
        net.WriteUInt(slotIdx or 0, 3)
    net.SendToServer()
end

function MG.RequestClose(reason)
    if not MG.active or MG.closeRequested then return end
    MG.closeRequested = true
    net.Start("WoundSystem_BandageClose")
    net.WriteUInt(MG.sessionId or 0, 24)
    net.WriteString(reason or "client_close")
    net.SendToServer()
    BeginClose()
end

net.Receive("WoundSystem_BandageOpen", function()
    local incomingSession = net.ReadUInt(24)
    local incomingLimb = net.ReadString()
    local incomingMode = net.ReadString()
    local incomingSlotIdx = net.ReadUInt(3)
    LocalReset()
    MG.active = true
    MG.sessionId = incomingSession
    MG.limbId = incomingLimb
    MG.slotIdx = incomingSlotIdx
    MG.mode = incomingMode ~= "" and incomingMode or "gauze"
    
    local cx, cy = ScrW() / 2, ScrH() / 2
    local mx, my = gui.MousePos()
    if mx <= 0 and my <= 0 then
        mx, my = cx, cy
    end
    local baseScale = GetScale() * CFG.ScaleMultiplier
    
    MG.handPos.x = (mx - cx) / baseScale
    MG.handPos.y = -(my - cy) / baseScale
    MG.handScreenX = mx
    MG.handScreenY = my
    
    -- INITIALIZE ROLL SIZE BASED ON ACTUAL INVENTORY DURABILITY
    local curDur = (MG.slotIdx and WoundSystemInventorySlots[MG.slotIdx]) and WoundSystemInventorySlots[MG.slotIdx].durability or 20
    local slotTool = (MG.slotIdx and WoundSystemInventorySlots[MG.slotIdx]) and WoundSystemInventorySlots[MG.slotIdx].toolName or "GAUZE"
    local maxDur = WoundSystemMedToolConfig and WoundSystemMedToolConfig[slotTool] and WoundSystemMedToolConfig[slotTool].max or 20
    MG.condition = math.Clamp(curDur / maxDur, 0, 1)
    MG.minDur = curDur
    MG.shownDur = curDur

    MG.lastSampleAt = CurTime()
    MG.lastSentAt = CurTime()
    MG.openTime = CurTime()
    MG.lastMouseDown = input.IsMouseDown(MOUSE_LEFT)
    MG.lastRightDown = input.IsMouseDown(MOUSE_RIGHT)
    MG.lastEscDown = input.IsKeyDown(KEY_ESCAPE)
    if incomingSlotIdx == 6 and WoundSystem.HealthGUI and WoundSystem.HealthGUI.SetScreenClickerOwned then
        MG.externalClicker = true
        WoundSystem.HealthGUI.SetScreenClickerOwned(true, "zcity_swep_bandage")
    end
    EnsureOverlay()
    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.MarkOpened(MG)
    end
end)

net.Receive("WoundSystem_BandageClose", function()
    local sessionId = net.ReadUInt(24)
    net.ReadString()
    if not MG.active or sessionId ~= MG.sessionId then return end
    BeginClose()
end)

hook.Add("Think", "WoundSystem_BandageInput", function()
    if not MG.active then return end
    if not IsValid(MG.overlay) then EnsureOverlay() end

    -- slot 6 = minigame started by a Z-City SWEP: it does not need the health HUD
    if WoundSystemHealthHUDOpen == false and MG.slotIdx ~= 6 then
        MG.RequestClose("hud_closed")
        return
    end

    local slot = MG.slotIdx and WoundSystemInventorySlots and WoundSystemInventorySlots[MG.slotIdx]
    if not slot or slot.type ~= "tool" or slot.durability <= 0.01 then
        MG.RequestClose("empty")
        return
    end

    local slotTool = slot.toolName or "GAUZE"
    local maxDur = WoundSystemMedToolConfig and WoundSystemMedToolConfig[slotTool] and WoundSystemMedToolConfig[slotTool].max or 20

    local now = CurTime()
    local dt = math.Clamp(now - (MG.lastSampleAt or now), 0.001, CFG.MaxFrameTime)

    -- Remaining bandage as shown to the player: it only goes down (a late server value never bumps it back up),
    -- includes the part that is wound but not sent yet, and eases towards the target instead of jumping.
    MG.minDur = math.min(MG.minDur or slot.durability, slot.durability)
    local pending = ((MG.unsentDegrees or 0) / 360) * GetDurabilityPerWrap()
    local shownTarget = math.max(0, MG.minDur - pending)
    MG.shownDur = (MG.shownDur or shownTarget) + (shownTarget - (MG.shownDur or shownTarget)) * (1 - math.exp(-dt * 14))
    MG.condition = math.Clamp(MG.shownDur / maxDur, 0, 1)
    MG.lastSampleAt = now
    
    local cx, cy = ScrW() / 2, ScrH() / 2
    local mx, my = gui.MousePos()
    local baseScale = GetScale() * CFG.ScaleMultiplier

    local state = WoundSystemClientState and WoundSystemClientState.PlayerLimbs and WoundSystemClientState.PlayerLimbs[MG.limbId]
    local painFactor = 0
    if state and state.pain then
        painFactor = math.Clamp(state.pain, 0, 100) / 100
    end

    local currentTension = Lerp(painFactor, CFG.SpringTension, 35)
    local currentDamping = Lerp(painFactor, CFG.SpringDamping, 1.2)

    local offsetX = 0
    local offsetY = 0
    if painFactor > 0 then
        local t = CurTime() * 0.7
        local w = 60 * painFactor * GetScale()
        offsetX = math.sin(t) * w
        offsetY = math.cos(t * 1.1) * w
    end

    local targetScreenX = mx + offsetX
    local targetScreenY = my + offsetY

    -- Use shared hand physics (same as other minigames, matching CAS3)
    HandPhysics.Step(MG, dt, {
        pain = painFactor,
        str = 0,
        conc = 100,
        shakeX = 120,
        shakeY = 40,
        positionScale = 120,
        bounds = { 0, ScrW(), 0, ScrH() }
    })

    -- Convert screen-space to sim-space (centered, y-up)
    MG.handPos.x = (MG.handScreenX - cx) / baseScale
    MG.handPos.y = -(MG.handScreenY - cy) / baseScale

    -- Map screen velocity to sim velocity for legacy bandage logic
    -- Do not overwrite sim velocity while actively holding the bandage
    if not MG.holdingBandage then
        MG.handVelocity.x = (MG.handScreenVelX or 0) / baseScale
        MG.handVelocity.y = (MG.handScreenVelY or 0) / baseScale
    end

    local isPauseActive = gui.IsGameUIVisible() or gui.IsConsoleVisible()
    local isClicking = not isPauseActive and input.IsMouseDown(MOUSE_LEFT) or false
    local startedClick = isClicking and not MG.lastMouseDown
    local stoppedClick = (not isClicking) and MG.lastMouseDown
    MG.lastMouseDown = isClicking

    -- Compute distance and normal relative to the sim-space center (0,0)
    local centerX, centerY = 0, 0
    local dx = MG.handPos.x - centerX
    local dy = MG.handPos.y - centerY
    local dist = math.sqrt(dx * dx + dy * dy)
    local normX, normY = 0, 1
    if dist > 0.001 then normX, normY = dx / dist, dy / dist end

    if startedClick then
        local bVec = GetVectorFromAngle(MG.bandageAngle)
        local dot = (bVec.x * normX) + (bVec.y * normY)
        MG.holdingBandage = dot > CFG.GrabDotProduct 
    end

    if stoppedClick then MG.holdingBandage = false end

    if MG.holdingBandage then
        -- replicate C# BandageMinigame.PhysicsUpdate holding logic
        local state = WoundSystemClientState and WoundSystemClientState.PlayerLimbs and WoundSystemClientState.PlayerLimbs[MG.limbId]
        local speedMult = (state and state.bandageMinigameSpeedMult) or 1
        speedMult = speedMult * math.max(BANDAGE_SPEED_CONVAR and BANDAGE_SPEED_CONVAR:GetFloat() or 1, 1)

        -- Use the limb-provided multiplier (if any); lerp factor matches C# (34)
        -- Slow only screen-space velocity; sim-space velocity will follow naturally
        MG.handScreenVelX = Lerp(dt * 34 * speedMult, MG.handScreenVelX or 0, 0)
        MG.handScreenVelY = Lerp(dt * 34 * speedMult, MG.handScreenVelY or 0, 0)

        local angleFromVector = GetAngleFromVector(normX, normY)
        local num = angleFromVector - MG.bandageAngle
        local num2 = angleFromVector - (MG.lastActionAngle or 0)

        if num < 20 then
            -- wrap detection (C# compares >350 then <90)
            if MG.bandageAngle > 350 and (angleFromVector < 90 or angleFromVector == 360) then
                MG.bandageAngle = MG.bandageAngle - 360
                MG.lastActionAngle = (MG.lastActionAngle or 0) - 360
                MG.didWrap = true
                surface.PlaySound("bandage.ogg")
                if WoundSystem.BroadcastMinigameSound then
                    WoundSystem.BroadcastMinigameSound("bandage.ogg", 0.5)
                end
                -- perform bandage action (20° step)
                MG.lastActionAngle = (MG.lastActionAngle or 0) + 20
                MG.totalDegreesWrapped = MG.totalDegreesWrapped + 20
                MG.unsentDegrees = MG.unsentDegrees + 20
                if MG.didWrap then
                    MG.sizeMultiplier = (MG.sizeMultiplier or 0.9) + 0.0015
                end
            elseif num2 > 20 then
                -- normal step action every 20 degrees
                MG.lastActionAngle = (MG.lastActionAngle or 0) + 20
                MG.totalDegreesWrapped = MG.totalDegreesWrapped + 20
                MG.unsentDegrees = MG.unsentDegrees + 20
            end

            MG.bandageAngle = angleFromVector
        end
    end

    if now - MG.lastSentAt > 0.1 then
        if MG.unsentDegrees > 0 then
            net.Start("WoundSystem_BandageInput")
            net.WriteUInt(MG.sessionId, 24)
            net.WriteFloat(MG.unsentDegrees)
            net.WriteUInt(WoundSystem and WoundSystem.MinigameNextInputSeq and WoundSystem.MinigameNextInputSeq(MG) or 0, 24)
            net.SendToServer()
            local slot = MG.slotIdx and WoundSystemInventorySlots and WoundSystemInventorySlots[MG.slotIdx]
            if slot and slot.type == "tool" then
                local predictedCost = (MG.unsentDegrees / 360) * GetDurabilityPerWrap()
                slot.durability = math.max(0, (slot.durability or 0) - predictedCost)
            end
            MG.unsentDegrees = 0
            MG.lastSentAt = now
        end
    end

    -- Collision: enforce inner bandage collision radius (push outward and damp when not holding)
    do
        local collRadius = CFG.CollisionRadius or 250
        if dist < collRadius then
            -- Only apply collision push if hand velocity is pointing inward (toward center)
            -- This prevents velocity buildup when already moving outward
            local velDot = (MG.handVelocity.x * normX) + (MG.handVelocity.y * normY)
            if velDot < 0 then
                -- Velocity is pointing inward, so apply outward push
                MG.handVelocity.x = MG.handVelocity.x + (normX * (dt * 25))
                MG.handVelocity.y = MG.handVelocity.y + (normY * (dt * 25))
            end
            MG.handPos.x = normX * collRadius
            MG.handPos.y = normY * collRadius
            if not MG.holdingBandage then
                MG.handVelocity.x = MG.handVelocity.x * 0.9
                MG.handVelocity.y = MG.handVelocity.y * 0.9
            end
            MG.handScreenX = cx + (MG.handPos.x * baseScale)
            MG.handScreenY = cy - (MG.handPos.y * baseScale)
        end
    end

    local rightDown = input.IsMouseDown(MOUSE_RIGHT)
    local escDown = input.IsKeyDown(KEY_ESCAPE)
    local canCloseByInput = (CurTime() - (MG.openTime or 0)) > 0.2
    local startedRight = rightDown and not MG.lastRightDown
    local startedEsc = escDown and not MG.lastEscDown
    MG.lastRightDown = rightDown
    MG.lastEscDown = escDown

    if canCloseByInput and (startedRight or startedEsc) then
        if startedEsc then gui.HideGameUI() end
        MG.RequestClose("user_cancel")
    end
end)
