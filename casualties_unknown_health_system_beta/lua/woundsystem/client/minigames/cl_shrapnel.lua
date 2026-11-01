--[[
    GLASS SHARD minigame (Z-City bridge).

    This is the original shrapnel minigame file, restored from archive.zip and EDITED, not rewritten.
    The shrapnel MECHANIC is gone: no limb.shrapnel, no TWEEZERS item, no healing/clotting penalty,
    no fragments from bullets / explosions / broken needles. The server (sv_woundbridge.lua) only ever
    sends `hasTweezers = false`, and shards are created exclusively by Z-City glass damage.
    Historical net/file names are kept so the existing client code stays intact.
]]

if WoundSystemShrapnelMinigame and WoundSystemShrapnelMinigame._Loaded then
    if IsValid(WoundSystemShrapnelMinigame.overlay) then
        WoundSystemShrapnelMinigame.overlay:Remove()
    end

    hook.Remove("OnScreenSizeChanged", "WoundSystem_ShrapnelResize")
    hook.Remove("Think", "WoundSystem_ShrapnelInput")
    hook.Remove("ShutDown", "WoundSystem_ShrapnelCleanup")
end

if not (WoundSystem and WoundSystem.MinigameClip) and file.Exists("woundsystem/client/minigames/cl_clip.lua", "LUA") then
    include("woundsystem/client/minigames/cl_clip.lua")
    include("woundsystem/client/minigames/sh_handphysics.lua")
end
local HandPhysics = include("woundsystem/client/minigames/sh_handphysics.lua")
local DevMinigameCfg = include("woundsystem/client/minigames/minigame_dev_config.lua") or {}

local function DrawRectInt(x, y, w, h)
    surface.DrawTexturedRect(math.Round(tonumber(x) or 0), math.Round(tonumber(y) or 0), math.Round(tonumber(w) or 0), math.Round(tonumber(h) or 0))
end
local function DrawRectUVInt(x, y, w, h, u1, v1, u2, v2)
    surface.DrawTexturedRectUV(math.Round(tonumber(x) or 0), math.Round(tonumber(y) or 0), math.Round(tonumber(w) or 0), math.Round(tonumber(h) or 0), u1, v1, u2, v2)
end
local path = "casunknown-images/shrapnelminigame/"
local matBackground = Material(path .. "minigameShrapnel.png")
local matHandIdle = Material(path .. "handGraspIdle1.png")
local matHandClick = Material(path .. "handGraspClick.png")
local matTweezersIdle = Material(path .. "handTweezersIdle.png")
local matTweezersClick = Material(path .. "handTweezersClick.png")

local function RedBloodEnabled()
    local cvBloodColor = GetConVar("woundsys_blood_color")
    return string.lower(string.Trim(cvBloodColor and cvBloodColor:GetString() or "alien_yellow")) == "red"
end

local function ShrapnelPieceMaterialPath()
    local redPath = path .. "shrapnelpiece_red.png"
    if RedBloodEnabled() and file.Exists("materials/" .. redPath, "GAME") then
        return redPath
    end

    return path .. "shrapnelpiece.png"
end

local matPiece = Material(ShrapnelPieceMaterialPath())

local function RefreshShrapnelPieceMaterial()
    matPiece = Material(ShrapnelPieceMaterialPath())
end

if cvars and cvars.AddChangeCallback then
    cvars.AddChangeCallback("woundsys_blood_color", RefreshShrapnelPieceMaterial, "WoundSystem_ShrapnelPieceBloodColor")
end

WoundSystemShrapnelMinigame = WoundSystemShrapnelMinigame or {}
local MG = WoundSystemShrapnelMinigame
MG._Loaded = true

local PIECE_COUNT = 5

local SRC_BG_W = 200
local SRC_BG_H = 128
local SRC_PIECE_W = 52
local SRC_PIECE_H = 276
local SRC_HAND_W = 512
local SRC_HAND_H = 1260

local HAND_CURSOR_PIVOT_X = 0.4
local HAND_CURSOR_PIVOT_Y = 0.1
local HAND_CURSOR_OFFSET_X = 40
local BOARD_OFFSET_Y = 500
local SHARD_DRAW_OFFSET_Y = -670
local CLIP_BACKGROUND_ENABLED = true
local CLIP_BACKGROUND_ALPHA = 200
local CLIP_BACKGROUND_FADE_TIME = 0.2
local SHRAPNEL_EXTRACT_Y = -60
local SHRAPNEL_REIMPALE_Y = SHRAPNEL_EXTRACT_Y - 8
local SHRAPNEL_HAND_START_Y = -170
local SHRAPNEL_MIN_Y = -364
local SHRAPNEL_FREE_MAX_Y = 240
local SHRAPNEL_GRAB_HALF_X = 75
local SHRAPNEL_GRAB_HALF_Y = 350
local SHRAPNEL_BREAK_VEL_Y = 2.2
local SHRAPNEL_BREAK_X_DIST = 42

MG.active = MG.active or false
MG.external = MG.external or false -- opened by Z-City damage, no health HUD needed
MG.externalClicker = MG.externalClicker or false
MG.sessionId = MG.sessionId or 0
MG.limbId = MG.limbId or nil
MG.pieces = MG.pieces or {}
MG.remaining = MG.remaining or 0
MG.hasTweezers = MG.hasTweezers or false
MG.overlay = MG.overlay or nil
MG.board = MG.board or nil
MG.closeRequested = MG.closeRequested or false
MG.sendInterval = MG.sendInterval or 0.05
MG.lastSentAt = MG.lastSentAt or 0
MG.lastMouseDown = input.IsMouseDown(MOUSE_LEFT)
MG.lastRightDown = input.IsMouseDown(MOUSE_RIGHT)
MG.lastEscDown = input.IsKeyDown(KEY_ESCAPE)
MG.lastSampleAt = MG.lastSampleAt or 0
MG.lastHandY = MG.lastHandY or 0
MG.handX = MG.handX or 0
MG.handY = MG.handY or 0
MG.handBaseX = MG.handBaseX or 0
MG.handBaseY = MG.handBaseY or 0
MG.handScreenX = MG.handScreenX or 0
MG.handScreenY = MG.handScreenY or 0
MG.handScreenVelX = MG.handScreenVelX or 0
MG.handScreenVelY = MG.handScreenVelY or 0
MG.handDrawX = MG.handDrawX or 0
MG.handDrawY = MG.handDrawY or 0
MG.scale = MG.scale or 0.8
MG.handSlideSpeed = MG.handSlideSpeed or 14
MG.handVelocityScale = MG.handVelocityScale or 0.35
MG.boardW = MG.boardW or 0
MG.boardH = MG.boardH or 0
MG.pieceDrawW = MG.pieceDrawW or 0
MG.pieceDrawH = MG.pieceDrawH or 0
MG.handDrawW = MG.handDrawW or 0
MG.openTime = MG.openTime or 0
MG.handDrawH = MG.handDrawH or 0
MG.inputSeq = MG.inputSeq or 0
MG.ackSeq = MG.ackSeq or 0
MG.visualHeldIndex = MG.visualHeldIndex or nil
MG.visualGrabArmed = MG.visualGrabArmed or false
MG.visualHoldSource = MG.visualHoldSource or nil
MG.visualHoldOffsetX = MG.visualHoldOffsetX or 0
MG.visualHoldOffsetY = MG.visualHoldOffsetY or 0

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

local function GetHandOffsets()
    local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
    local ox = (DevMinigameCfg.shrapnelHandOffsetX or HAND_CURSOR_OFFSET_X) * scale
    local oy = (DevMinigameCfg.shrapnelHandOffsetY or 0) * scale
    return ox, oy
end

local function UpdateHandDrawPosition()
    local ox, oy = GetHandOffsets()
    MG.handDrawX = MG.handScreenX - (MG.handDrawW * HAND_CURSOR_PIVOT_X) + ox
    MG.handDrawY = MG.handScreenY - (MG.handDrawH * HAND_CURSOR_PIVOT_Y) + oy
end

local function GetHandGripScreenPos()
    local ox, oy = GetHandOffsets()
    return MG.handScreenX + ox, MG.handScreenY + oy
end

local function RebuildBoardMetrics()
    local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
    
    MG.scale = scale * 1.537
    MG.boardW = 1382 * scale
    MG.boardH = 1384 * scale

    MG.pieceDrawW = SRC_PIECE_W * MG.scale
    MG.pieceDrawH = SRC_PIECE_H * MG.scale
    MG.handDrawW = SRC_HAND_W * MG.scale * 0.85
    MG.handDrawH = SRC_HAND_H * MG.scale * 0.85
    UpdateHandDrawPosition()
end

local function DestroyOverlay()
    if IsValid(MG.overlay) then
        MG.overlay:Remove()
    end
    MG.overlay = nil
    MG.board = nil
end

local function LocalReset()
    if MG.externalClicker then
        MG.externalClicker = false
        if WoundSystem and WoundSystem.HealthGUI and WoundSystem.HealthGUI.SetScreenClickerOwned and not WoundSystemHealthHUDOpen then
            WoundSystem.HealthGUI.SetScreenClickerOwned(false, "zcity_glass_end")
        end
    end

    MG.external = false
    MG.active = false
    MG.closing = false
    MG.sessionId = 0
    MG.limbId = nil
    MG.pieces = {}
    MG.remaining = 0
    MG.hasTweezers = false
    MG.closeRequested = false
    MG.lastMouseDown = false
    MG.lastRightDown = false
    MG.pendingStartedClick = false
    MG.pendingStoppedClick = false
    MG.lastEscDown = false
    MG.openTime = 0
    MG.lastSampleAt = 0
    MG.lastHandY = 0
    MG.handX = 0
    MG.handY = 0
    MG.handBaseX = 0
    MG.handBaseY = 0
    MG.handScreenX = 0
    MG.handScreenY = ScrH() * 0.5
    MG.handScreenVelX = 0
    MG.handScreenVelY = 0
    MG.handDrawX = 0
    MG.handDrawY = 0
    MG.lastSentAt = 0
    MG._hp_acc = 0
    MG.inputSeq = 0
    MG.ackSeq = 0
    MG.visualHeldIndex = nil
    MG.visualGrabArmed = false
    MG.visualHoldSource = nil
    MG.visualHoldOffsetX = 0
    MG.visualHoldOffsetY = 0
    DestroyOverlay()
end

local function BeginClose()
    if not MG.active then return end
    MG.closeRequested = true
    LocalReset()
end

local function DrawMinigameHeader()
    if not (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.DrawHeader) then return end

    WoundSystem.MinigameClip.DrawHeader({
        minigame = "glass",
        title = "Glass shards",
        value = tostring(math.max(MG.remaining or 0, 0)) .. "/" .. tostring(PIECE_COUNT),
        curValue = MG.remaining or 0,
        maxValue = PIECE_COUNT,
        icon = "casunknown-images/shrapnelminigame/shrapnelpiece.png",
        pw = 30,
        ph = 30,
        valueColor = Color(150, 205, 235, 255)
    })
end

local function SimToBoard(pieceX, pieceY)
    if not IsValid(MG.board) then return 0, 0 end
    local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
    local cx = MG.board:GetWide() * 0.5
    local cy = MG.board:GetTall() * 0.5
    return cx + (pieceX * MG.scale), cy - (pieceY * MG.scale) + (SHARD_DRAW_OFFSET_Y * scale)
end

local function ScreenToSim(mouseX, mouseY)
    if not IsValid(MG.board) then return 0, 0 end
    local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
    local lx, ly = MG.board:ScreenToLocal(mouseX, mouseY)
    local sx = (lx - MG.board:GetWide() * 0.5) / MG.scale
    local sy = -((ly - MG.board:GetTall() * 0.5 - (SHARD_DRAW_OFFSET_Y * scale)) / MG.scale)
    return sx, sy
end

local function ClearVisualHold()
    MG.visualHeldIndex = nil
    MG.visualGrabArmed = false
    MG.visualHoldSource = nil
    MG.visualHoldOffsetX = 0
    MG.visualHoldOffsetY = 0
end

local function UpdateVisualShardDrag(startedClick, holdingClick, stoppedClick, handVelY, dt)
    if not MG.active then return end

    local clickStartedInPullArea = startedClick
        and ((MG.handY or 0) > SHRAPNEL_HAND_START_Y or (MG.handBaseY or 0) > SHRAPNEL_HAND_START_Y)

    if clickStartedInPullArea then
        MG.visualGrabArmed = true
    elseif not holdingClick then
        MG.visualGrabArmed = false
    end

    if not MG.visualHeldIndex and holdingClick and MG.visualGrabArmed then
        local closestDist = math.huge
        local closestIdx = nil
        local closestSource = nil
        local closestHandX = MG.handX or 0
        local closestHandY = MG.handY or 0
        local candidates = {
            {x = MG.handX or 0, y = MG.handY or 0, source = "grip"},
            {x = MG.handBaseX or 0, y = MG.handBaseY or 0, source = "base"}
        }

        for idx, piece in ipairs(MG.pieces or {}) do
            if piece and piece.active then
                for _, candidate in ipairs(candidates) do
                    local dx = math.abs((candidate.x or 0) - (piece.x or 0))
                    local dy = math.abs((candidate.y or 0) - (piece.y or 0))

                    if dx <= SHRAPNEL_GRAB_HALF_X and dy <= SHRAPNEL_GRAB_HALF_Y then
                        local dist = (dx * dx) + (dy * dy)
                        if dist < closestDist then
                            closestDist = dist
                            closestIdx = idx
                            closestSource = candidate.source
                            closestHandX = candidate.x or 0
                            closestHandY = candidate.y or 0
                        end
                    end
                end
            end
        end

        if closestIdx then
            local piece = MG.pieces[closestIdx]
            MG.visualHeldIndex = closestIdx
            MG.visualHoldSource = closestSource
            MG.visualHoldOffsetX = (piece.x or 0) - closestHandX
            MG.visualHoldOffsetY = (piece.y or 0) - closestHandY
        end
    end

    if stoppedClick or not holdingClick then
        ClearVisualHold()
        return
    end

    local heldIndex = MG.visualHeldIndex
    local heldPiece = heldIndex and MG.pieces and MG.pieces[heldIndex] or nil
    if not (heldPiece and heldPiece.active) then
        ClearVisualHold()
        return
    end

    local dragHandX = MG.visualHoldSource == "base" and (MG.handBaseX or 0) or (MG.handX or 0)
    local dragHandY = MG.visualHoldSource == "base" and (MG.handBaseY or 0) or (MG.handY or 0)
    local targetX = dragHandX + (MG.visualHoldOffsetX or 0)
    local targetY = dragHandY + (MG.visualHoldOffsetY or 0)
    local smooth = math.Clamp((tonumber(dt) or 0) * 24, 0.08, 0.72)

    if heldPiece.embedded == false then
        heldPiece.x = Lerp(smooth, heldPiece.x or targetX, targetX)
        heldPiece.y = Lerp(smooth, heldPiece.y or targetY, targetY)
        heldPiece.y = math.Clamp(heldPiece.y, SHRAPNEL_MIN_Y, SHRAPNEL_FREE_MAX_Y)

        if heldPiece.y <= SHRAPNEL_REIMPALE_Y then
            heldPiece.embedded = true
        end
    else
        heldPiece.y = Lerp(smooth, heldPiece.y or targetY, targetY)
        heldPiece.y = math.Clamp(heldPiece.y, SHRAPNEL_MIN_Y, SHRAPNEL_EXTRACT_Y)

        if heldPiece.y >= SHRAPNEL_EXTRACT_Y then
            heldPiece.y = SHRAPNEL_EXTRACT_Y
            heldPiece.embedded = false
        elseif not MG.hasTweezers then
            if math.abs(tonumber(handVelY) or 0) > SHRAPNEL_BREAK_VEL_Y
                or math.abs((heldPiece.x or 0) - targetX) > SHRAPNEL_BREAK_X_DIST then
                ClearVisualHold()
            end
        end
    end
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

    MG.overlay.Paint = function(_, _, _)
        if not MG.active then return end
        if not IsValid(MG.board) then return end

        local bx, by = MG.board:GetPos()

        if CLIP_BACKGROUND_ENABLED
            and WoundSystem
            and WoundSystem.MinigameClip
            and WoundSystem.MinigameClip.DrawBackdrop then
            WoundSystem.MinigameClip.DrawBackdrop({
                openTime = MG.openTime,
                alpha = CLIP_BACKGROUND_ALPHA,
                fadeTime = CLIP_BACKGROUND_FADE_TIME
            })
        end

        local filteredPieces = BeginPixelFilter()
        local pieceClipActive = WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Begin()

        surface.SetMaterial(matPiece)
        surface.SetDrawColor(255, 255, 255, 255)

        for i = 1, PIECE_COUNT do
            local piece = MG.pieces[i]
            if piece and piece.active then
                local px, py = SimToBoard(piece.x, piece.y)
                DrawRectInt(
                    bx + px - (MG.pieceDrawW * 0.5),
                    by + py - (MG.pieceDrawH * 0.5),
                    MG.pieceDrawW,
                    MG.pieceDrawH
                )
            end
        end

        if WoundSystem and WoundSystem.MinigameClip then
            WoundSystem.MinigameClip.End(pieceClipActive)
        end
        EndPixelFilter(filteredPieces)

        local filteredFront = BeginPixelFilter()
        local frontClipActive = WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Begin()
        local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
        surface.SetMaterial(matBackground)
        surface.SetDrawColor(255, 255, 255, 255)
        DrawRectInt(bx, by + (300 * scale), MG.boardW, MG.boardH)
        if WoundSystem and WoundSystem.MinigameClip then
            WoundSystem.MinigameClip.End(frontClipActive)
        end
        EndPixelFilter(filteredFront)
    end

    MG.overlay.PaintOver = function(_, _, _)
        if not MG.active then return end

        local clicking = input.IsMouseDown(MOUSE_LEFT)
        local handMat = clicking
            and (MG.hasTweezers and matTweezersClick or matHandClick)
            or (MG.hasTweezers and matTweezersIdle or matHandIdle)
        local filtered = BeginPixelFilter()
        local clipActive = WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Begin()
        surface.SetMaterial(handMat)
        
        -- Smooth pain color transition
        local gb = 255
        local state = WoundSystemClientState and WoundSystemClientState.PlayerLimbs and WoundSystemClientState.PlayerLimbs[MG.limbId]
        if state and state.pain then
            local painFactor = math.Clamp(state.pain, 0, 100) / 100
            gb = 255 * (1 - painFactor)
        end
        
        surface.SetDrawColor(255, gb, gb, 153)
        
        -- Draw rotated hand using hand draw pivot as center
        local cx = MG.handDrawX + (MG.handDrawW * HAND_CURSOR_PIVOT_X)
        local cy = MG.handDrawY + (MG.handDrawH * HAND_CURSOR_PIVOT_Y)
        local angle = (MG.handScreenVelX or 0) * 0.5
        surface.DrawTexturedRectRotated(cx, cy, MG.handDrawW, MG.handDrawH, angle)
        if WoundSystem and WoundSystem.MinigameClip then
            WoundSystem.MinigameClip.End(clipActive)
        end
        EndPixelFilter(filtered)

        DrawMinigameHeader()

        WoundSystem.MinigameClip.DrawExitGuide()
    end

    MG.board = vgui.Create("DPanel", MG.overlay)
    MG.board:SetSize(MG.boardW, MG.boardH)
    MG.board:Center()
    do
        local scale = (WoundSystem and WoundSystem.MinigameClip and WoundSystem.MinigameClip.Scale) and WoundSystem.MinigameClip.Scale() or (ScrH() / 1080)
        local bx, by = MG.board:GetPos()
        MG.board:SetPos(bx, by + (BOARD_OFFSET_Y * scale))
    end
    MG.board:SetMouseInputEnabled(false)
    MG.board:SetKeyboardInputEnabled(false)

    MG.board.Paint = function(_, w, h)
        if not MG.active then return end
    end
end

local function ReadPiecesFromNet()
    local pieces = {}
    for i = 1, PIECE_COUNT do
        local x = net.ReadFloat()
        local y = net.ReadFloat()
        local active = net.ReadBool()

        pieces[i] = {
            x = x,
            y = y,
            active = active
        }
    end
    local remaining = net.ReadUInt(4)
    if net.BytesLeft then
        local bytesLeft, bitsLeft = net.BytesLeft()
        if (bitsLeft or 0) >= PIECE_COUNT or (bytesLeft or 0) >= 1 then
            for i = 1, PIECE_COUNT do
                if pieces[i] then
                    pieces[i].embedded = net.ReadBool()
                end
            end
        end
    end
    local ackSeq = WoundSystem and WoundSystem.MinigameReadAck and WoundSystem.MinigameReadAck(0) or 0
    return pieces, remaining, ackSeq
end

local function ApplyServerPieces(serverPieces)
    MG.pieces = MG.pieces or {}

    for i = 1, PIECE_COUNT do
        local incoming = serverPieces and serverPieces[i] or nil
        if not incoming then continue end

        local current = MG.pieces[i]
        local keepLocalPosition = current
            and current.active
            and incoming.active
            and (MG.visualHeldIndex == i or current.embedded == false or incoming.embedded == false)

        if keepLocalPosition then
            current.active = incoming.active
            if MG.visualHeldIndex ~= i then
                current.embedded = incoming.embedded
            end
        else
            MG.pieces[i] = incoming
        end
    end
end

function MG.IsActive()
    return MG.active == true
end

function MG.RequestStart(limbId, slotIdx)
    if not limbId or limbId == "" then return end

    net.Start("WoundSystem_ShrapnelStart")
        net.WriteString(limbId)
        net.WriteUInt(slotIdx or 0, 3)
    net.SendToServer()
end

function MG.RequestClose(reason)
    if not MG.active or MG.closeRequested then return end
    MG.closeRequested = true

    net.Start("WoundSystem_ShrapnelClose")
    net.WriteUInt(MG.sessionId or 0, 24)
    net.WriteString(reason or "client_close")
    net.SendToServer()
    
    BeginClose()
end

net.Receive("WoundSystem_ShrapnelOpen", function()
    local incomingSession = net.ReadUInt(24)
    local incomingLimb = net.ReadString()
    local incomingHasTweezers = net.ReadBool()
    local incomingPieces, incomingRemaining, ackSeq = ReadPiecesFromNet()
    local incomingExternal = net.ReadBool()

    LocalReset()
    MG.active = true
    MG.sessionId = incomingSession
    MG.limbId = incomingLimb
    MG.hasTweezers = false -- TWEEZERS removed together with the shrapnel mechanic
    MG.external = incomingExternal == true
    MG.pieces = incomingPieces
    MG.remaining = incomingRemaining
    MG.ackSeq = ackSeq or 0
    MG.closeRequested = false
    MG.lastSentAt = 0
    MG.lastMouseDown = input.IsMouseDown(MOUSE_LEFT)
    MG.lastRightDown = input.IsMouseDown(MOUSE_RIGHT)
    MG.lastEscDown = input.IsKeyDown(KEY_ESCAPE)
    MG.openTime = CurTime()

    if MG.external and WoundSystem and WoundSystem.HealthGUI and WoundSystem.HealthGUI.SetScreenClickerOwned then
        MG.externalClicker = true
        WoundSystem.HealthGUI.SetScreenClickerOwned(true, "zcity_glass")
    end

    EnsureOverlay()

    local mx, my = gui.MousePos()
    if mx <= 0 and my <= 0 then
        mx, my = ScrW() * 0.5, ScrH() * 0.5
    end
    MG.handScreenX = mx
    MG.handScreenY = my
    local gripX, gripY = GetHandGripScreenPos()
    local sx, sy = ScreenToSim(gripX, gripY)
    local baseX, baseY = ScreenToSim(MG.handScreenX, MG.handScreenY)
    MG.handX = sx
    MG.handY = sy
    MG.handBaseX = baseX
    MG.handBaseY = baseY
    MG.lastHandY = sy
    MG.lastSampleAt = CurTime()
    UpdateHandDrawPosition()
    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.MarkOpened(MG)
    end
end)

net.Receive("WoundSystem_ShrapnelState", function()
    local sessionId = net.ReadUInt(24)
    if not MG.active or sessionId ~= MG.sessionId then return end
    local pieces, remaining, ackSeq = ReadPiecesFromNet()
    ApplyServerPieces(pieces)
    MG.remaining = remaining
    if WoundSystem and WoundSystem.MinigameAck then
        WoundSystem.MinigameAck(MG, ackSeq)
    end
end)

net.Receive("WoundSystem_ShrapnelClose", function()
    local sessionId = net.ReadUInt(24)
    net.ReadString()
    if not MG.active then return end
    if sessionId ~= MG.sessionId then return end
    BeginClose()
end)

hook.Add("OnScreenSizeChanged", "WoundSystem_ShrapnelResize", function(_, _)
    if not MG.active then return end
    EnsureOverlay()
    if WoundSystem and WoundSystem.MinigameClip then
        WoundSystem.MinigameClip.MarkOpened(MG)
    end
end)

hook.Add("Think", "WoundSystem_ShrapnelInput", function()
    if not MG.active then return end

    if not IsValid(MG.board) then
        EnsureOverlay()
        if not IsValid(MG.board) then return end
    end

    -- a session opened by Z-City glass damage owns the screen without the health HUD
    if WoundSystemHealthHUDOpen == false and not MG.external then
        MG.RequestClose("hud_closed")
        return
    end

    local now = CurTime()
    local dt = math.max(now - (MG.lastSampleAt or now), 0.001)

    -- Use shared HandPhysics for consistent movement and shake
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
        shakeX = 140,
        shakeY = 40,
        maxLength = 200,
        bounds = { 0, ScrW(), 0, ScrH() }
    })

    local gripX, gripY = GetHandGripScreenPos()
    MG.handX, MG.handY = ScreenToSim(gripX, gripY)
    MG.handBaseX, MG.handBaseY = ScreenToSim(MG.handScreenX, MG.handScreenY)
    UpdateHandDrawPosition()
    local handVelY = (MG.handY - MG.lastHandY) / math.max(dt * 60, 0.001)
    handVelY = handVelY * MG.handVelocityScale
    MG.lastSampleAt = now
    MG.lastHandY = MG.handY

    local isClicking = input.IsMouseDown(MOUSE_LEFT)
    local startedClick = isClicking and not MG.lastMouseDown
    local stoppedClick = (not isClicking) and MG.lastMouseDown
    MG.lastMouseDown = isClicking
    MG.pendingStartedClick = MG.pendingStartedClick or startedClick
    MG.pendingStoppedClick = MG.pendingStoppedClick or stoppedClick

    UpdateVisualShardDrag(startedClick, isClicking, stoppedClick, handVelY, dt)

    local rightDown = input.IsMouseDown(MOUSE_RIGHT)
    local escDown = input.IsKeyDown(KEY_ESCAPE)
    local startedRight = rightDown and not MG.lastRightDown
    local startedEsc = escDown and not MG.lastEscDown
    MG.lastRightDown = rightDown
    MG.lastEscDown = escDown

    if (startedRight or startedEsc) and (CurTime() - (MG.openTime or 0) > 0.2) then
        if startedEsc then
            gui.HideGameUI() 
        end
        MG.RequestClose("user_cancel")
        return
    end

    if MG.closeRequested then return end
    if now - MG.lastSentAt < MG.sendInterval then return end

    MG.lastSentAt = now
    local sendStartedClick = MG.pendingStartedClick == true
    local sendStoppedClick = MG.pendingStoppedClick == true
    MG.pendingStartedClick = false
    MG.pendingStoppedClick = false

    net.Start("WoundSystem_ShrapnelInput")
    net.WriteUInt(MG.sessionId or 0, 24)
    net.WriteFloat(MG.handX)
    net.WriteFloat(MG.handY)
    net.WriteFloat(handVelY)
    net.WriteBool(sendStartedClick)
    net.WriteBool(isClicking)
    net.WriteBool(sendStoppedClick)
    net.WriteFloat(MG.handBaseX)
    net.WriteFloat(MG.handBaseY)
    net.WriteUInt(WoundSystem and WoundSystem.MinigameNextInputSeq and WoundSystem.MinigameNextInputSeq(MG) or 0, 24)
    net.SendToServer()
end)

hook.Add("ShutDown", "WoundSystem_ShrapnelCleanup", function()
    DestroyOverlay()
end)
